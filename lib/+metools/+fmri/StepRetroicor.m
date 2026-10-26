classdef StepRetroicor < metools.Step
    % STEPRETROICOR  Physiological noise correction (RETROICOR) of every input file.
    %
    %   reads   In   (bold)
    %   writes  Out  (bold)   b<name> for every file
    %
    %   parameters  TR (seconds; default: cfg.acq.TR)
    %   files       <session folder>/markers.csv, <session folder>/acq_params.json (SliceTiming)
    %   side output control figures <outputs folder>/retroicor/retrocor_<session>_<subject>_echo<n>.png
    %   computation metools.fmri.proc.readMarkers, readSliceTiming, retroicor

    properties
        TR double {mustBeScalarOrEmpty, mustBePositive} = []
    end

    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end

        function b = configBindings(~)
            b = struct('TR', 'acq.TR');
        end

        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'b');
        end

        function files = externalFiles(~, ctx)
            files = {fullfile(ctx.SessionDir, 'markers.csv'), ...
                     fullfile(ctx.SessionDir, 'acq_params.json')};
        end

        function names = requiredFunctions(~)
            names = {'spm_vol', 'spm_dctmtx'};
        end

        function items = qc(obj, in, ~, ctx)
            % The control figures written by RETROICOR (one per echo).
            items = {};
            for e = 1:numel(in.In)
                png = obj.figureFile(ctx, e);
                if exist(png, 'file') == 2
                    items{end+1} = struct('Title', sprintf('RETROICOR, file %d', e), 'Image', png); %#ok<AGROW>
                end
            end
        end

        function execute(obj, in, out, ctx)
            tr = obj.resolve('TR', ctx.Cfg);
            markers = metools.fmri.proc.readMarkers(fullfile(ctx.SessionDir, 'markers.csv'), Verbose = true);
            sliceTiming = metools.fmri.proc.readSliceTiming(fullfile(ctx.SessionDir, 'acq_params.json'));
            for e = 1:numel(in.In)
                metools.fmri.proc.retroicor(in.In{e}, out.Out{e}, markers, sliceTiming, tr, ...
                    FigureFile = obj.figureFile(ctx, e));
            end
        end
    end

    methods (Access = private)
        function f = figureFile(~, ctx, e)
            f = fullfile(ctx.OutputsDir, 'retroicor', sprintf('retrocor_%s_%s_echo%d.png', ctx.Session, ctx.Subject, e));
        end
    end
end
