classdef StepParcellation < metools.Step
    % STEPPARCELLATION  ROI time courses by an atlas (or a coarse voxel template) and the
    % connectivity matrix between the ROIs, written as tab-separated text files.
    %
    %   reads   In      (bold)        exactly one file: cleaned, normally UNSMOOTHED data,
    %                                 e.g. In="bold_clean"
    %           Mask    (brain_mask)  optional; used when UseMask = true
    %           Covars  (covars)      optional; column 'outlier' of NuisanceSignalRegression,
    %                                 used when ExcludeOutliers = true
    %   writes  Timeseries   (roi_timeseries)  <in>_atlas-<AtlasName>_timeseries.tsv
    %                        scans x ROIs, header = ROI names   (when SaveTimeseries)
    %           Connectivity (connectivity)    <in>_atlas-<AtlasName>_meas-<Measure>_relmat.tsv
    %                        ROIs x ROIs, header = ROI names    (when SaveConnectivity)
    %           Rois         (roi_info)        <in>_atlas-<AtlasName>_rois.tsv   one row per ROI:
    %                        index, label, name, voxel counts, coverage, centroid, included
    %                        <in>_atlas-<AtlasName>_parcellation.json   settings and scan counts
    % Missing values are n/a (ROIs not covered by the data, the diagonal of the matrix).
    %
    % Parameters (defaults in brackets)
    %   Atlas             NIfTI file of the atlas or template (required)
    %   AtlasType         'labels' | 'voxels' ('labels'); 'voxels' = every voxel > 0 of the
    %                     template is a ROI (e.g. a 6 mm grid)
    %   Labels            text file with the ROI names ('' = roi_<label>)
    %   AtlasName         short name used in the file names ('' = from the atlas file name)
    %   Summary           'mean' | 'eigen' ('mean')
    %   Measure           'pearsonr' | 'fisherz' ('pearsonr')
    %   MinCoverage       ROIs with smaller coverage get n/a (0)
    %   UseMask           restrict the ROIs to the brain mask (true)
    %   ExcludeOutliers   leave the censored scans out of the correlation (false)
    %   SaveTimeseries, SaveConnectivity   which outputs are written (true, true)
    %
    % The atlas is resampled to the data (nearest neighbour), never the data to the atlas;
    % see metools.fmri.proc.parcellate.
    %
    %   computation metools.fmri.proc.parcellate, connectivityMatrix; metools.util.writeTsv

    properties
        Atlas char = ''
        AtlasType char {mustBeMember(AtlasType, {'labels', 'voxels'})} = 'labels'
        Labels char = ''
        AtlasName char = ''
        Summary char {mustBeMember(Summary, {'mean', 'eigen'})} = 'mean'
        Measure char {mustBeMember(Measure, {'pearsonr', 'fisherz'})} = 'pearsonr'
        MinCoverage (1,1) double {mustBeInRange(MinCoverage, 0, 1)} = 0
        UseMask (1,1) logical = true
        ExcludeOutliers (1,1) logical = false
        SaveTimeseries (1,1) logical = true
        SaveConnectivity (1,1) logical = true
    end

    methods
        function p = ports(~)
            p.In = metools.Port.input('bold', 'Cardinality', 'one');
            p.Mask = metools.Port.input('brain_mask', 'Cardinality', 'one', 'Optional', true);
            p.Covars = metools.Port.input('covars', 'Cardinality', 'one', 'Optional', true);
            p.Timeseries = metools.Port.output('roi_timeseries', 'Optional', true);
            p.Connectivity = metools.Port.output('connectivity', 'Optional', true);
            p.Rois = metools.Port.output('roi_info');
        end

        function out = predict(obj, in, ~)
            [folder, base] = fileparts(in.In{1});
            stem = fullfile(folder, [base '_atlas-' obj.atlasName()]);
            if obj.SaveTimeseries
                out.Timeseries = {[stem '_timeseries.tsv']};
            end
            if obj.SaveConnectivity
                out.Connectivity = {[stem '_meas-' obj.Measure '_relmat.tsv']};
            end
            out.Rois = {[stem '_rois.tsv'], [stem '_parcellation.json']};
        end

        function msgs = check(obj, in, ~)
            msgs = {};
            if isempty(obj.Atlas)
                msgs{end+1} = 'parameter Atlas (NIfTI file of the atlas) is not set.';
            end
            if isempty(obj.atlasName())
                msgs{end+1} = 'AtlasName must contain letters or digits (it is used in the file names).';
            end
            if ~isempty(obj.AtlasName) && ~isempty(regexp(obj.AtlasName, '[^A-Za-z0-9]', 'once'))
                msgs{end+1} = sprintf('AtlasName "%s": use only letters and digits.', obj.AtlasName);
            end
            if ~obj.SaveTimeseries && ~obj.SaveConnectivity
                msgs{end+1} = 'SaveTimeseries and SaveConnectivity are both false - nothing to compute.';
            end
            if obj.UseMask && isempty(in.Mask)
                msgs{end+1} = ['UseMask = true, but stream "' obj.streamFor('Mask') ...
                    '" is not available (add CreateMask or set UseMask = false).'];
            end
            if obj.ExcludeOutliers && isempty(in.Covars)
                msgs{end+1} = ['ExcludeOutliers = true, but stream "' obj.streamFor('Covars') ...
                    '" is not available (NuisanceSignalRegression writes it).'];
            end
            if strcmp(obj.AtlasType, 'voxels') && ~isempty(obj.Labels)
                msgs{end+1} = 'Labels cannot be used with AtlasType = ''voxels'' (names are coordinates).';
            end
        end

        function files = externalFiles(obj, ~)
            files = {obj.Atlas};
            if ~isempty(obj.Labels)
                files{end+1} = obj.Labels;
            end
        end

        function names = requiredFunctions(~)
            names = {'spm_vol', 'spm_read_vols', 'spm_get_data', 'spm_imcalc'};
        end

        function execute(obj, in, out, ~)
            mask = '';
            if obj.UseMask
                mask = in.Mask{1};
            end
            res = metools.fmri.proc.parcellate(in.In{1}, obj.Atlas, AtlasType = obj.AtlasType, ...
                Labels = obj.Labels, Mask = mask, Summary = obj.Summary, MinCoverage = obj.MinCoverage);

            censored = false(res.nScans, 1);
            if obj.ExcludeOutliers
                [cov, h] = metools.util.readTsv(in.Covars{1});
                col = find(strcmp(h, 'outlier'), 1);
                if isempty(col)
                    error('Parcellation:NoOutliers', '%s has no column "outlier".', in.Covars{1});
                end
                if size(cov, 1) ~= res.nScans
                    error('Parcellation:ScanCount', '%s has %d rows, the data %d volumes.', ...
                        in.Covars{1}, size(cov, 1), res.nScans);
                end
                censored = cov(:, col) > 0;
            end
            used = ~censored;
            fprintf('Parcellation %s: %d ROIs (%d with data), %d of %d scans used for the correlation.\n', ...
                obj.atlasName(), numel(res.labels), nnz(res.included), nnz(used), res.nScans);

            if obj.SaveTimeseries
                metools.util.writeTsv(out.Timeseries{1}, res.names, res.timeseries);
            end
            if obj.SaveConnectivity
                M = metools.fmri.proc.connectivityMatrix(res.timeseries(used, :), Measure = obj.Measure);
                metools.util.writeTsv(out.Connectivity{1}, res.names, M);
            end

            R = numel(res.labels);
            T = table((1:R)', res.labels, res.names, res.atlasVoxels, res.gridVoxels, res.validVoxels, ...
                res.coverage, res.centroid(:, 1), res.centroid(:, 2), res.centroid(:, 3), double(res.included), ...
                'VariableNames', {'index', 'label', 'name', 'atlas_voxels', 'grid_voxels', 'valid_voxels', ...
                'coverage', 'x', 'y', 'z', 'included'});
            writetable(T, out.Rois{1}, 'FileType', 'text', 'Delimiter', '\t');

            info = struct('Atlas', obj.Atlas, 'AtlasType', obj.AtlasType, 'Labels', obj.Labels, ...
                'AtlasName', obj.atlasName(), 'Input', in.In{1}, 'Mask', mask, 'Summary', obj.Summary, ...
                'Measure', obj.Measure, 'MinCoverage', obj.MinCoverage, ...
                'ExcludeOutliers', obj.ExcludeOutliers, 'NumScans', res.nScans, ...
                'NumScansUsed', nnz(used), 'CensoredScans', find(censored)', ...
                'NumRois', R, 'NumRoisIncluded', nnz(res.included), ...
                'METools', metools.version(), 'Created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
            fid = fopen(out.Rois{2}, 'w');
            closer = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', jsonencode(info, 'PrettyPrint', true));
        end

        function items = qc(~, ~, out, ~)
            T = readtable(out.Rois{1}, 'FileType', 'text', 'Delimiter', '\t');
            items = {struct('Title', 'ROIs', 'Value', height(T)), ...
                struct('Title', 'ROIs with data', 'Value', nnz(T.included)), ...
                struct('Title', 'Median coverage', 'Value', median(T.coverage))};
        end
    end

    methods (Access = private)
        function n = atlasName(obj)
            n = obj.AtlasName;
            if isempty(n)
                [~, n] = fileparts(obj.Atlas);
                n = regexprep(regexprep(n, '\.nii$', ''), '[^A-Za-z0-9]', '');
            end
        end
    end
end
