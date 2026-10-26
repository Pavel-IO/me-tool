classdef SignalTarget < metools.Step
    % Test step (like Nuisance): signal from bold, cleans bold_branch and writes back to it.
    methods
        function p = ports(~)
            p.Signal = metools.Port.input('bold');
            p.Target = metools.Port.input('bold_branch');
            p.Out    = metools.Port.output('', 'Follows', 'Target');
            p.Covars = metools.Port.output('covars');
        end
        function out = predict(~, in, ~)
            out.Out    = metools.Step.addPrefix(in.Target, 'q');
            out.Covars = {'covars.mat'};
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
