classdef NeedsOne < metools.Step
    % Test step: requires exactly 1 file (like Normalize after echo combination).
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold', 'Cardinality', 'one');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'n');
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
