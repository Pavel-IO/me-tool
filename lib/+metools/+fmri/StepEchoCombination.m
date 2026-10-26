classdef StepEchoCombination < metools.Step
    % STEPECHOCOMBINATION  Combines the echoes into one image (tSNR-weighted).
    %
    %   reads   In   (bold)   all echoes
    %   writes  Out  (bold)   c_bold.nii in the folder of the first echo
    %
    % With a single input file nothing is done and the file is passed through unchanged.
    %
    %   parameters  TEs (echo times in ms; default: cfg.acq.TEs)
    %   computation metools.fmri.proc.combineEchoesTsnr

    properties
        TEs double {mustBePositive} = []
    end

    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end

        function b = configBindings(~)
            b = struct('TEs', 'acq.TEs');
        end

        function msgs = check(obj, in, cfg)
            msgs = {};
            if numel(in.In) > 1
                tes = obj.resolve('TEs', cfg);
                if numel(tes) ~= numel(in.In)
                    msgs = {sprintf('TEs has %d value(s), but the input has %d echo file(s).', ...
                        numel(tes), numel(in.In))};
                end
            end
        end

        function out = predict(~, in, ~)
            if numel(in.In) == 1
                out.Out = in.In;                               % pass-through
            else
                folder = fileparts(in.In{1});
                out.Out = {fullfile(folder, 'c_bold.nii')};
            end
        end

        function names = requiredFunctions(~)
            names = {'spm_vol'};
        end

        function execute(obj, in, out, ctx)
            if numel(in.In) == 1
                return                                         % pass-through
            end
            metools.fmri.proc.combineEchoesTsnr(in.In, obj.resolve('TEs', ctx.Cfg), out.Out{1});
        end
    end
end
