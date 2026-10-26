classdef StepNuisanceSignalRegression < metools.Step
    % STEPNUISANCESIGNALREGRESSION  Regresses nuisance signals out of every voxel, together
    % with a temporal band-pass filter and optional censoring of high-motion scans.
    %
    % Everything the regression contains is set by parameters, and the complete design
    % matrix is saved with named columns. The model (see docs/steps/NuisanceSignalRegression.md):
    %
    %   y_clean = y - X*beta + constant,   X = [motion, FD, tissue, DCT filter basis]
    %
    % With censoring, beta is estimated from the uncensored scans, the censored scans are
    % interpolated and only then the low-pass part of the filter is applied.
    %
    %   reads   Signal  (bold)       exactly one file; the tissue signals are extracted from it
    %                                (normally the normalized, UNSMOOTHED data)
    %           Target  (bold)       exactly one file; the image that is cleaned
    %                                (e.g. Target="bold_smooth")
    %           Mean    (bold_mean)  mean image in the space of the Signal image
    %           Rp      (rp)         motion parameters
    %   writes  Out     (follows Target)  <Prefix><name of the target>
    %           Covars  (covars)     <out>_covars.tsv   per scan: framewise_displacement,
    %                                outlier (0/1), the tissue signals
    %           Design  (design_matrix)  <out>_design.tsv   the design matrix, named columns
    %
    % Parameters (defaults in brackets)
    %   MotionModel        0 | 6 | 12 | 24 (24)  motion regressors (motionRegressors)
    %   FdMethod           'power' | 'legacy' ('power')  how FD is computed:
    %                      power  = Power 2012: raw parameters, rotations x 50 mm
    %                      legacy = original Cosmic2: filtered and detrended parameters,
    %                               rotations not converted
    %   FdRegressor        include FD as a regressor (false)
    %   TissueSignals      'mean' | 'acompcor' | 'none' ('acompcor')  WM and CSF signals:
    %                      mean signal of each mask, or CompCorComponents principal
    %                      components of each mask (aCompCor)
    %   CompCorComponents  components per mask for 'acompcor' (5)
    %   Band               pass band [low high] in Hz ([1/128 Inf] = SPM high-pass 128 s,
    %                      no low-pass); e.g. [0.008 0.09]. low = 0: no high-pass
    %   ScrubFd            FD threshold in mm for censoring ([] = no censoring)
    %   ScrubNeighbors     [before after] scans censored around each outlier ([0 0])
    %   CensorInterp       'pchip' | 'linear' | 'spline' ('pchip')  interpolation of the
    %                      censored scans before the low-pass
    %   MasksDir (cfg.paths.masks), WmMask ('WM09.nii'), CsfMask ('CSFmaskVENTlat.nii'),
    %   TR (cfg.acq.TR), Prefix ('q'), CovarsName, DesignName ('' = derived from the output)
    %
    % The original Cosmic2 regression: MotionModel=24, FdMethod='legacy', FdRegressor=true,
    % TissueSignals='mean', Band=[1/128 Inf], ScrubFd=[].
    %
    %   computation metools.fmri.proc.motionRegressors, framewiseDisplacement, maskSignal,
    %               compCor, outlierScans, dctFilterBasis, nuisanceDesign, regressOut

    properties
        MotionModel (1,1) double {mustBeMember(MotionModel, [0 6 12 24])} = 24
        FdMethod char {mustBeMember(FdMethod, {'power', 'legacy'})} = 'power'
        FdRegressor (1,1) logical = false
        TissueSignals char {mustBeMember(TissueSignals, {'mean', 'acompcor', 'none'})} = 'acompcor'
        CompCorComponents (1,1) double {mustBeInteger, mustBePositive} = 5
        Band (1,2) double {mustBeNonnegative} = [1/128 Inf]
        ScrubFd double {mustBeScalarOrEmpty, mustBePositive} = []
        ScrubNeighbors (1,2) double {mustBeInteger, mustBeNonnegative} = [0 0]
        CensorInterp char {mustBeMember(CensorInterp, {'pchip', 'linear', 'spline'})} = 'pchip'
        MasksDir char = ''
        WmMask char = 'WM09.nii'
        CsfMask char = 'CSFmaskVENTlat.nii'
        TR double {mustBeScalarOrEmpty, mustBePositive} = []
        Prefix (1,:) char = 'q'
        CovarsName char = ''
        DesignName char = ''
    end

    methods
        function p = ports(~)
            p.Signal = metools.Port.input('bold', 'Cardinality', 'one');
            p.Target = metools.Port.input('bold', 'Cardinality', 'one');
            p.Mean   = metools.Port.input('bold_mean', 'Cardinality', 'one');
            p.Rp     = metools.Port.input('rp', 'Cardinality', 'one');
            p.Out    = metools.Port.output('', 'Follows', 'Target');
            p.Covars = metools.Port.output('covars');
            p.Design = metools.Port.output('design_matrix');
        end

        function b = configBindings(~)
            b = struct('MasksDir', 'paths.masks', 'TR', 'acq.TR');
        end

        function out = predict(obj, in, ~)
            [folder, name] = fileparts(in.Target{1});
            stem = [obj.Prefix name];
            out.Out = metools.Step.addPrefix(in.Target, obj.Prefix);
            out.Covars = {fullfile(folder, metools.fmri.StepNuisanceSignalRegression.orDefault( ...
                obj.CovarsName, [stem '_covars.tsv']))};
            out.Design = {fullfile(folder, metools.fmri.StepNuisanceSignalRegression.orDefault( ...
                obj.DesignName, [stem '_design.tsv']))};
        end

        function msgs = check(obj, ~, cfg)
            msgs = {};
            if obj.Band(1) >= obj.Band(2)
                msgs{end+1} = sprintf('Band = [%g %g]: the lower frequency must be below the upper one.', obj.Band);
            end
            tr = obj.resolve('TR', cfg);
            if ~isempty(tr) && isfinite(obj.Band(2)) && obj.Band(2) >= 1/(2*tr)
                msgs{end+1} = sprintf(['Band(2) = %g Hz is not below the Nyquist frequency %g Hz ' ...
                    '(TR %g s); use Inf for no low-pass.'], obj.Band(2), 1/(2*tr), tr);
            end
            names = {obj.CovarsName, obj.DesignName};
            for i = 1:numel(names)
                if ~isempty(names{i}) && ~endsWith(names{i}, '.tsv')
                    msgs{end+1} = sprintf('CovarsName/DesignName "%s" must end with .tsv.', names{i}); %#ok<AGROW>
                end
            end
        end

        function files = externalFiles(obj, ctx)
            files = {};
            if ~strcmp(obj.TissueSignals, 'none')
                masksDir = obj.resolve('MasksDir', ctx.Cfg);
                files = {fullfile(masksDir, obj.WmMask), fullfile(masksDir, obj.CsfMask)};
            end
        end

        function names = requiredFunctions(~)
            names = {'spm_imcalc', 'spm_filter', 'spm_load', 'spm_dctmtx', 'spm_read_vols'};
        end

        function execute(obj, in, out, ctx)
            tr = obj.resolve('TR', ctx.Cfg);
            target = in.Target{1};
            n = metools.util.scanCount(target);
            rp = spm_load(in.Rp{1});
            if size(rp, 1) < n
                error('NuisanceSignalRegression:Rp', '%s has %d rows, the target %d volumes.', in.Rp{1}, size(rp, 1), n);
            end
            rp = rp(1:n, :);

            % motion and framewise displacement
            [regs, names] = metools.fmri.proc.motionRegressors(rp, obj.MotionModel);
            fd = obj.computeFd(rp, tr);
            if obj.FdRegressor
                regs = [regs fd];
                names{end+1} = 'framewise_displacement';
            end

            % tissue signals
            [tissue, tissueNames] = obj.tissueSignals(in, ctx, tr, n);
            regs = [regs tissue];
            names = [names tissueNames];

            % censoring
            censored = false(n, 1);
            if ~isempty(obj.ScrubFd)
                censored = metools.fmri.proc.outlierScans(fd, obj.ScrubFd, ...
                    Before = obj.ScrubNeighbors(1), After = obj.ScrubNeighbors(2));
            end

            [X, xnames, c, lp] = metools.fmri.proc.nuisanceDesign(regs, names, tr, Band = obj.Band);
            nFilter = size(X, 2) - size(regs, 2);
            used = nnz(~censored);
            fprintf(['Nuisance regression: %d scans (%d censored), %d columns = %d regressors (motion %d, ' ...
                'FD %d, tissue %d) + %d filter (band %g-%g Hz, incl. constant, %d low-pass); ' ...
                'about %d degrees of freedom left.\n'], ...
                n, nnz(censored), size(X, 2), size(regs, 2), obj.MotionModel, double(obj.FdRegressor), ...
                size(tissue, 2), nFilter, obj.Band(1), obj.Band(2), numel(lp), used - rank(X(~censored, :)));
            if size(X, 2) - numel(lp) >= used
                error('NuisanceSignalRegression:Saturated', ...
                    'The design has %d columns for %d uncensored scans - nothing would be left of the data.', ...
                    size(X, 2) - numel(lp), used);
            end
            if any(censored)
                fprintf(['Censoring: betas from the %d uncensored scans, censored scans interpolated (%s)' ...
                    ' before the low-pass.\n'], used, obj.CensorInterp);
            end

            metools.fmri.proc.regressOut(target, out.Out{1}, X, Keep = c, Censored = censored, LowPass = lp, ...
                Interp = obj.CensorInterp);
            metools.util.writeTsv(out.Covars{1}, [{'framewise_displacement', 'outlier'} tissueNames], ...
                [fd double(censored) tissue]);
            metools.util.writeTsv(out.Design{1}, xnames, X);
        end

        function items = qc(~, ~, out, ~)
            [cov, h] = metools.util.readTsv(out.Covars{1});
            fd = cov(:, strcmp(h, 'framewise_displacement'));
            outl = cov(:, strcmp(h, 'outlier'));
            [X, xnames] = metools.util.readTsv(out.Design{1});
            isFilter = startsWith(xnames, 'dct_');
            u = ~(outl > 0);
            items = {struct('Title', 'Scans', 'Value', size(X, 1)), ...
                struct('Title', 'Nuisance regressors (without filter)', 'Value', nnz(~isFilter)), ...
                struct('Title', 'Censored scans', 'Value', nnz(~u)), ...
                struct('Title', 'Filter basis columns (incl. constant)', 'Value', nnz(isFilter)), ...
                struct('Title', 'Degrees of freedom left (approx.)', 'Value', nnz(u) - rank(X(u, :))), ...
                struct('Title', 'Mean framewise displacement (mm)', 'Value', mean(fd)), ...
                struct('Title', 'Regressors', 'Text', strjoin(xnames(~isFilter), ', '))};
        end
    end

    methods (Access = private)
        function fd = computeFd(obj, rp, tr)
            switch obj.FdMethod
                case 'power'
                    fd = metools.fmri.proc.framewiseDisplacement(rp);
                case 'legacy'
                    X0 = metools.fmri.proc.dctFilterBasis(size(rp, 1), tr, obj.Band);
                    rpf = rp - X0*(pinv(X0'*X0)*X0'*rp);
                    fd = metools.fmri.proc.framewiseDisplacement(rpf, RotationUnits = 'none', Detrend = true);
            end
        end

        function [tissue, names] = tissueSignals(obj, in, ctx, tr, n)
            masksDir = obj.resolve('MasksDir', ctx.Cfg);
            wm = fullfile(masksDir, obj.WmMask);
            csf = fullfile(masksDir, obj.CsfMask);
            cutoff = 1/obj.Band(1);                  % s; Inf when Band(1) = 0
            switch obj.TissueSignals
                case 'none'
                    tissue = zeros(n, 0);
                    names = {};
                case 'mean'
                    w = metools.fmri.proc.maskSignal(in.Signal{1}, in.Mean{1}, wm, tr, Cutoff = cutoff);
                    c = metools.fmri.proc.maskSignal(in.Signal{1}, in.Mean{1}, csf, tr, Cutoff = cutoff);
                    tissue = [w(1:n) c(1:n)];
                    names = {'white_matter', 'csf'};
                case 'acompcor'
                    k = obj.CompCorComponents;
                    [w, ew] = metools.fmri.proc.compCor(in.Signal{1}, in.Mean{1}, wm, tr, k, Cutoff = cutoff);
                    [c, ec] = metools.fmri.proc.compCor(in.Signal{1}, in.Mean{1}, csf, tr, k, Cutoff = cutoff);
                    tissue = [w(1:n, :) c(1:n, :)];
                    names = [arrayfun(@(i) sprintf('wm_comp_cor_%02d', i), 1:size(w, 2), 'UniformOutput', false), ...
                        arrayfun(@(i) sprintf('csf_comp_cor_%02d', i), 1:size(c, 2), 'UniformOutput', false)];
                    fprintf('aCompCor: WM %d components (%.1f %% of variance), CSF %d components (%.1f %%).\n', ...
                        size(w, 2), 100*sum(ew), size(c, 2), 100*sum(ec));
            end
        end
    end

    methods (Static, Access = private)
        function s = orDefault(value, default)
            s = value;
            if isempty(s)
                s = default;
            end
        end
    end
end
