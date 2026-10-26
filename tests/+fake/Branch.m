classdef Branch < metools.Step
    % Test step (like Smooth): reads bold, writes to a new stream bold_branch.
    properties
        Prefix (1,:) char = 'b'
    end
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('bold_branch');
        end
        function out = predict(obj, in, ~)
            out.Out = metools.Step.addPrefix(in.In, obj.Prefix);
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
