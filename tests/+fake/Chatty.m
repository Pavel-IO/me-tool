classdef Chatty < metools.Step
    % Test step: prints to the console (like SPM) and returns QC items.
    properties
        FailQc (1,1) logical = false
    end
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'c');
        end
        function execute(~, ~, out, ~)
            fprintf('hello from the chatty step\n');
            fake.touchAll(out);
        end
        function items = qc(obj, ~, ~, ctx)
            if obj.FailQc
                error('fake:QcBoom', 'qc exploded');
            end
            fprintf('qc of the chatty step\n');
            txt = fullfile(ctx.QcDir, 'note.txt');
            fid = fopen(txt, 'w');
            fclose(fid);
            items = {struct('Title', 'Answer', 'Value', 42), struct('Title', 'Note', 'Text', 'all fine')};
        end
    end
end
