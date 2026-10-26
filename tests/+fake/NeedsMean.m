classdef NeedsMean < metools.Step
    % Test step: requires the stream bold_mean (like Normalize).
    methods
        function p = ports(~)
            p.In   = metools.Port.input('bold');
            p.Mean = metools.Port.input('bold_mean');
            p.Out  = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'm');
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
