classdef Producer < metools.Step
    % Test step (like Realign): bold -> bold, bold_mean, rp.
    properties
        Prefix (1,:) char = 'r'
    end
    methods
        function p = ports(~)
            p.In   = metools.Port.input('bold');
            p.Out  = metools.Port.output('', 'Follows', 'In');
            p.Mean = metools.Port.output('bold_mean');
            p.Rp   = metools.Port.output('rp');
        end
        function out = predict(obj, in, ~)
            out.Out  = metools.Step.addPrefix(in.In, obj.Prefix);
            out.Mean = metools.Step.addPrefix(in.In(1), 'mean_');
            [~, n] = fileparts(in.In{1});
            out.Rp   = {['rp_' n '.txt']};
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
