classdef Noisy < metools.Step
    % Test step: prints to the console and then fails.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'n');
        end
        function execute(~, ~, ~, ~)
            fprintf('last words before the failure\n');
            error('fake:Boom', 'noisy failure');
        end
    end
end
