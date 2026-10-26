classdef Fail < metools.Step
    % Test step: always throws an error when executed.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'x');
        end
        function execute(~, ~, ~, ~)
            error('fake:Boom', 'deliberate failure');
        end
    end
end
