classdef NeedsFunction < metools.Step
    % Test step: requires a function that does not exist on the MATLAB path.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'f');
        end
        function names = requiredFunctions(~)
            names = {'metools_no_such_function_xyz'};
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
