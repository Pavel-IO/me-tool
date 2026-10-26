classdef StepCreateMask < metools.Step
    % STEPCREATEMASK  Creates a brain mask from the (normalized) functional image.
    %
    %   reads   In    (bold)         exactly one file
    %   writes  Mask  (brain_mask)   <name><Suffix>.nii next to the input
    %
    %   parameters  Threshold (default 0.8), Suffix (default '_mask8')
    %   computation metools.fmri.proc.createBrainMask

    properties
        Threshold (1,1) double {mustBePositive, mustBeLessThanOrEqual(Threshold, 1)} = 0.8
        Suffix (1,:) char = '_mask8'
    end

    methods
        function p = ports(~)
            p.In   = metools.Port.input('bold', 'Cardinality', 'one');
            p.Mask = metools.Port.output('brain_mask');
        end

        function out = predict(obj, in, ~)
            [folder, name, ext] = fileparts(in.In{1});
            out.Mask = {fullfile(folder, [name, obj.Suffix, ext])};
        end

        function names = requiredFunctions(~)
            names = {'spm_global'};
        end

        function execute(obj, in, out, ~)
            metools.fmri.proc.createBrainMask(in.In{1}, out.Mask{1}, obj.Threshold);
        end
    end
end
