classdef Sloppy < metools.Step
    % Test step: creates the declared output and, in addition, an undeclared file.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 's');
        end
        function execute(~, in, out, ~)
            fake.touchAll(out);
            d = fileparts(in.In{1});
            fid = fopen(fullfile(d, 'surprise.txt'), 'w');
            fclose(fid);
        end
    end
end
