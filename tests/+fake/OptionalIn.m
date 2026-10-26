classdef OptionalIn < metools.Step
    % Test step: optional input rp.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Opt = metools.Port.input('rp', 'Optional', true);
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            if isempty(in.Opt)
                out.Out = metools.Step.addPrefix(in.In, 'n');
            else
                out.Out = metools.Step.addPrefix(in.In, 'y');
            end
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
