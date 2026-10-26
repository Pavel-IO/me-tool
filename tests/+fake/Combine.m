classdef Combine < metools.Step
    % Test step (like EchoCombination): at least 2 files -> 1 file c_bold.nii.
    properties
        TEs (1,:) double = [15 36 58]
    end
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold', 'Cardinality', 'many');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function msgs = check(obj, in, ~)
            msgs = {};
            if numel(obj.TEs) ~= numel(in.In)
                msgs = {sprintf('TEs has %d values but the input has %d files', numel(obj.TEs), numel(in.In))};
            end
        end
        function out = predict(~, in, ~)
            d = fileparts(in.In{1});
            out.Out = {fullfile(d, 'c_bold.nii')};
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
