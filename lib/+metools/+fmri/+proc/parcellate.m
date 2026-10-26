function res = parcellate(fmriFile, atlasFile, options)
    % PARCELLATE  Region (ROI) time courses of a 4D image defined by an atlas or a template.
    %
    %   res = metools.fmri.proc.parcellate('qwbc_bold.nii', 'BN_Atlas_246.nii', ...
    %       Labels = 'BN_Atlas_246.txt', Mask = 'wbc_bold_mask8.nii')
    %   res = metools.fmri.proc.parcellate('qwbc_bold.nii', 'grid6mm.nii', AtlasType = 'voxels')
    %
    % Direction of resampling: the ATLAS is brought to the grid of the data (nearest
    % neighbour, labels are never interpolated); the data are not resampled. Every data
    % voxel gets the label of the atlas voxel its centre lies in, and the ROI signal is
    % computed from all data voxels with that label. For an atlas coarser than the data
    % (e.g. a 6 mm template and 2.5 mm data) this is the average over the data voxels
    % inside each atlas voxel.
    %
    %   AtlasType    'labels'  the atlas holds integer labels, 0 = background (default)
    %                'voxels'  every voxel with a value > 0 is its own ROI (a template on
    %                          a coarse grid); names are the MNI coordinates 'x_y_z'
    %   Labels       text file with ROI names (labels only): a BIDS dseg.tsv (columns
    %                index, name), or lines '<label> <name>' (extra colour columns of a
    %                lookup table are ignored), or one name per line (line i = label i).
    %                '' = names roi_<label>.
    %   Mask         brain mask on the data grid (any value > 0.5 = brain); '' = none
    %   Summary      'mean' (default) or 'eigen' (first principal component of the
    %                voxels, sign aligned with the mean, scaled to the RMS of the voxels)
    %   MinCoverage  ROIs whose coverage is below it get NaN signals (default 0)
    %
    % A data voxel is valid when it lies in the mask and its time course is finite and not
    % constant. coverage = volume of the valid voxels / volume of the ROI in the atlas.
    %
    % res: timeseries (scans x ROIs), labels, names, centroid (ROIs x 3, mm, atlas
    % space), atlasVoxels, gridVoxels, validVoxels, coverage, included (ROIs x 1 each),
    % nScans.
    arguments
        fmriFile {mustBeTextScalar}
        atlasFile {mustBeTextScalar}
        options.AtlasType {mustBeMember(options.AtlasType, {'labels', 'voxels'})} = 'labels'
        options.Labels {mustBeTextScalar} = ''
        options.Mask {mustBeTextScalar} = ''
        options.Summary {mustBeMember(options.Summary, {'mean', 'eigen'})} = 'mean'
        options.MinCoverage (1,1) double {mustBeInRange(options.MinCoverage, 0, 1)} = 0
    end
    [work, cleanup] = metools.util.tempFolder(); %#ok<ASGLU>
    fmriFile = char(fmriFile);

    % --- labels in the atlas space
    Va = spm_vol(char(atlasFile));
    Va = Va(1);
    A = spm_read_vols(Va);
    A(~isfinite(A)) = 0;
    switch options.AtlasType
        case 'labels'
            L = round(A);
            L(L < 0) = 0;
            if any(abs(A(:) - L(:)) > 1e-3)
                warning('parcellate:NonIntegerAtlas', ...
                    'The atlas %s has non-integer values; they are rounded to labels.', Va.fname);
            end
        case 'voxels'
            L = zeros(size(A));
            L(A > 0) = 1:nnz(A > 0);
    end
    idx = find(L > 0);
    labels = unique(L(idx));
    R = numel(labels);
    if R == 0
        error('parcellate:EmptyAtlas', 'The atlas %s contains no labels.', Va.fname);
    end
    [~, pos] = ismember(L(idx), labels);
    [i, j, k] = ind2sub(size(L), idx);
    mm = Va.mat * [i j k ones(numel(idx), 1)]';
    atlasVoxels = accumarray(pos, 1, [R 1]);
    centroid = [accumarray(pos, mm(1, :)', [R 1]), accumarray(pos, mm(2, :)', [R 1]), ...
        accumarray(pos, mm(3, :)', [R 1])] ./ atlasVoxels;

    % --- names
    switch options.AtlasType
        case 'labels'
            names = arrayfun(@(l) sprintf('roi_%d', l), labels, 'UniformOutput', false);
            if strlength(options.Labels) > 0
                [lv, ln] = readNames(char(options.Labels));
                [found, where] = ismember(labels, lv);
                names(found) = ln(where(found));
                if any(~found)
                    warning('parcellate:MissingNames', '%d labels of the atlas have no name in %s.', ...
                        nnz(~found), char(options.Labels));
                end
            end
        case 'voxels'
            c = round(centroid);
            names = arrayfun(@(r) sprintf('%d_%d_%d', c(r, 1), c(r, 2), c(r, 3)), (1:R)', 'UniformOutput', false);
    end

    % --- labels on the data grid (nearest neighbour)
    Vl = struct('fname', fullfile(work, 'labels.nii'), 'dim', Va.dim(1:3), 'mat', Va.mat, ...
        'dt', [spm_type('float32') spm_platform('bigend')], 'pinfo', [1 0 0]', 'n', [1 1], ...
        'descrip', 'parcellate labels');
    spm_write_vol(Vl, L);
    ref = [fmriFile ',1'];
    labelsOnGrid = fullfile(work, 'labels_grid.nii');
    metools.fmri.proc.resampleLike(ref, Vl.fname, labelsOnGrid, Interp = 0, DataType = 'float32');
    Ld = round(spm_read_vols(spm_vol(labelsOnGrid)));
    Ld(~isfinite(Ld)) = 0;

    Vd = spm_vol(fmriFile);
    nScans = numel(Vd);
    vox = find(Ld > 0);
    [~, vpos] = ismember(Ld(vox), labels);
    gridVoxels = accumarray(vpos(vpos > 0), 1, [R 1]);

    inMask = true(size(vox));
    if strlength(options.Mask) > 0
        maskOnGrid = fullfile(work, 'mask_grid.nii');
        metools.fmri.proc.resampleLike(ref, char(options.Mask), maskOnGrid, Interp = 0, DataType = 'float32');
        M = spm_read_vols(spm_vol(maskOnGrid));
        if ~any(M(:) > 0.5)
            error('parcellate:EmptyMask', 'The brain mask %s is empty.', char(options.Mask));
        end
        inMask = M(vox) > 0.5;
    end

    % --- data of the labelled voxels (scans x voxels)
    [i, j, k] = ind2sub(size(Ld), vox);
    Y = spm_get_data(Vd, [i j k]');
    valid = inMask(:)' & all(isfinite(Y), 1) & std(Y, 0, 1) > 0;
    Y = Y(:, valid);
    vpos = vpos(valid);
    validVoxels = accumarray(vpos, 1, [R 1]);

    volA = abs(det(Va.mat(1:3, 1:3)));
    volD = abs(det(Vd(1).mat(1:3, 1:3)));
    coverage = min(1, validVoxels * volD ./ (atlasVoxels * volA));
    included = validVoxels > 0 & coverage >= options.MinCoverage;

    % --- summary per ROI
    ts = NaN(nScans, R);
    switch options.Summary
        case 'mean'
            W = sparse(1:numel(vpos), vpos, 1, numel(vpos), R);
            S = full(Y * W) ./ max(validVoxels', 1);
            ts(:, included) = S(:, included);
        case 'eigen'
            groups = accumarray(vpos(:), (1:numel(vpos))', [R 1], @(x) {x});
            for r = find(included)'
                Yr = Y(:, groups{r});
                m = mean(Yr, 2);
                Yc = Yr - mean(Yr, 1);
                [U, Sv] = svd(Yc, 'econ');
                e = U(:, 1) * Sv(1, 1) / sqrt(size(Yr, 2));
                if e' * (m - mean(m)) < 0
                    e = -e;
                end
                ts(:, r) = e;
            end
    end

    res = struct('timeseries', ts, 'labels', labels, 'names', {names}, 'centroid', centroid, ...
        'atlasVoxels', atlasVoxels, 'gridVoxels', gridVoxels, 'validVoxels', validVoxels, ...
        'coverage', coverage, 'included', included, 'nScans', nScans);
end

function [values, names] = readNames(file)
    % Label values and names from a label file (see the help of parcellate).
    txt = strtrim(splitlines(fileread(file)));
    txt = txt(~cellfun(@isempty, txt) & ~startsWith(txt, '#'));
    values = [];
    names = {};
    if isempty(txt)
        return
    end
    head = lower(strsplit(txt{1}, sprintf('\t')));
    if contains(txt{1}, sprintf('\t')) && any(strcmp(head, 'index')) && any(strcmp(head, 'name'))
        ci = find(strcmp(head, 'index'), 1);
        cn = find(strcmp(head, 'name'), 1);
        for l = 2:numel(txt)
            parts = strsplit(txt{l}, sprintf('\t'), 'CollapseDelimiters', false);
            values(end+1, 1) = str2double(parts{ci}); %#ok<AGROW>
            names{end+1, 1} = strtrim(parts{cn}); %#ok<AGROW>
        end
        return
    end
    for l = 1:numel(txt)
        t = regexp(txt{l}, '^(\d+)[\s,;]+(.*)$', 'tokens', 'once');
        if isempty(t)
            values(end+1, 1) = l; %#ok<AGROW>
            names{end+1, 1} = txt{l}; %#ok<AGROW>
        else
            name = regexprep(strtrim(t{2}), '(\s+\d+){3,4}$', '');   % colour columns of a LUT
            values(end+1, 1) = str2double(t{1}); %#ok<AGROW>
            names{end+1, 1} = name; %#ok<AGROW>
        end
    end
end
