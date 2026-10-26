function createBrainMask(inFile, outFile, threshold)
    % CREATEBRAINMASK  Brain mask by intensity threshold, as SPM's analysis mask (spm_spm).
    %
    %   metools.fmri.proc.createBrainMask('wbc_bold.nii', 'wbc_bold_mask8.nii', 0.8)
    %
    % The data are scaled to a grand mean of 100 (spm_global over all volumes); a voxel
    % is in the mask when its value exceeds threshold times the global value and the data
    % are not constant. Output: uint8 mask with the geometry of the input.
    %
    % Port of create_mask_Explorer (MaskExplorer, derived from SPM spm_spm) without the
    % GUI calls and without changing the working folder; the results are identical.
    %
    % NOTE: like the original, only the FIRST volume of a 4D input is tested against the
    % threshold (the number of scans is taken from the number of file names, i.e. 1), and
    % the test "data not constant" (diff over scans) is then empty. With a single 4D file
    % this most likely produces an empty mask. Kept for equivalence; to be fixed.
    arguments
        inFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        threshold (1,1) double {mustBePositive}
    end
    P = char(inFile);
    nScan = size(P, 1);          % number of file names (see NOTE above)

    VY = spm_vol(P);
    spm_check_orientations(VY);

    % global values and grand mean scaling
    GM = 100;
    q = length(VY);
    g = zeros(q, 1);
    for i = 1:q
        g(i) = spm_global(VY(i));
    end
    gSF = GM ./ mean(g);
    for i = 1:q
        VY(i).pinfo(1:2, :) = VY(i).pinfo(1:2, :) * gSF;
    end
    TH = g .* gSF * threshold;

    M = VY(1).mat;
    DIM = VY(1).dim(1:3)';
    xdim = DIM(1); ydim = DIM(2); zdim = DIM(3);

    VM = struct('fname', char(outFile), ...
        'dim', DIM', ...
        'dt', [spm_type('uint8') spm_platform('bigend')], ...
        'mat', M, ...
        'pinfo', [1 0 0]', ...
        'descrip', 'spm_spm:resultant analysis mask');
    metools.util.ensureFolder(fileparts(char(outFile)));
    VM = spm_create_vol(VM);

    MAXMEM = spm_get_defaults('stats.maxmem');
    mmv = MAXMEM/8/nScan;
    blksz = min(xdim*ydim, ceil(mmv));
    nbch = ceil(xdim*ydim/blksz);
    nbz = 1;
    blksz = blksz * nbz;

    [xords, yords] = ndgrid(1:xdim, 1:ydim);
    xords = xords(:)'; yords = yords(:)';
    S = 0;

    for z = 1:nbz:zdim
        CrPl = z:min(z+nbz-1, zdim);
        zords = CrPl(:)*ones(1, xdim*ydim);
        Q = [];
        for bch = 1:nbch
            I = (1:blksz) + (bch - 1)*blksz;
            I = I(I <= numel(CrPl)*xdim*ydim);
            xyz = [repmat(xords, 1, numel(CrPl)); ...
                   repmat(yords, 1, numel(CrPl)); ...
                   reshape(zords', 1, [])];
            xyz = xyz(:, I);
            nVox = size(xyz, 2);

            Cm = true(1, nVox);
            Y = zeros(nScan, nVox);
            for i = 1:nScan
                if ~any(Cm)
                    break
                end
                Y(i, Cm) = spm_get_data(VY(i), xyz(:, Cm), false);
                Cm(Cm) = Y(i, Cm) > TH(i);
            end
            Cm(Cm) = any(diff(Y(:, Cm), 1));      % not constant over scans
            CrS = sum(Cm);
            Q = [Q I(Cm)]; %#ok<AGROW>
            S = S + CrS;
        end
        jj = NaN(xdim, ydim, numel(CrPl));
        if ~isempty(Q)
            jj(Q) = 1;
        end
        VM = spm_write_plane(VM, ~isnan(jj), CrPl);
    end
    if S == 0
        warning('createBrainMask:Empty', 'The mask %s is empty.', char(outFile));
    end
end
