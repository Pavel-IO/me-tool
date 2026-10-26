classdef Lazy < metools.Step
    % Test step: declares an output but does not create it (execute does nothing).
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'l');
        end
        function execute(~, ~, ~, ~)
        end
    end
end
