classdef ConfigStep < metools.Step
    % Test step: parameter TR is taken from cfg.acq.TR when it is not set explicitly.
    % The value is written into the output file name (e.g. tr0.85_x.nii) so tests can see it.
    properties
        TR double = []
    end
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function b = configBindings(~)
            b = struct('TR', 'acq.TR');
        end
        function out = predict(obj, in, ctx)
            cfg = [];
            if ~isempty(ctx)
                cfg = ctx.Cfg;
            end
            tr = obj.resolve('TR', cfg);
            if isempty(tr)
                tr = 0;
            end
            out.Out = metools.Step.addPrefix(in.In, sprintf('tr%g_', tr));
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
