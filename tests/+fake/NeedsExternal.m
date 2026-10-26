classdef NeedsExternal < metools.Step
    % Test step: needs the file <subject folder>/anat/t1.nii that is not a stream.
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'e');
        end
        function files = externalFiles(~, ctx)
            files = {fullfile(ctx.SubjectDir, 'anat', 't1.nii')};
        end
        function execute(~, ~, out, ~)
            fake.touchAll(out);
        end
    end
end
