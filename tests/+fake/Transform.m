classdef Transform < metools.Step
    % Test step: bold -> bold (in place: writes into the stream it reads), adds a prefix.
    properties
        Prefix (1,:) char = 'f'
        Lambda (1,1) double {mustBePositive} = 1
    end
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(obj, in, ~)
            out.Out = metools.Step.addPrefix(in.In, obj.Prefix);
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
