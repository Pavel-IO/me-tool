classdef PassThrough < metools.Step
    % Test step: creates nothing, the output is the same file as the input.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = in.In;
        end
        function execute(~, ~, ~, ~)
        end
    end
end
