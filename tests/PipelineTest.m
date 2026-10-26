classdef PipelineTest < matlab.unittest.TestCase
    % Tests of the static compilation of pipelines (no data, no SPM). The steps of package +fake compute nothing.

    methods (Test)
        function chainUsesLastVersion(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEqual(plan.Steps(1).reads(1).files, {'x.nii'});
            tc.verifyEqual(plan.Steps(2).reads(1).files, {'rx.nii'});
            tc.verifyEqual(plan.Steps(2).writes(1).files, {'brx.nii'});
            v = plan.Env.current('bold');
            tc.verifyEqual(v.files, {'brx.nii'});
            tc.verifyNumElements(plan.Env.history('bold'), 3);
        end

        function nameValueSyntaxWorks(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform(), Prefix = 'n');
            plan = p.compile();
            tc.verifyEqual(plan.Steps(1).writes(1).files, {'nx.nii'});
        end

        function branchAndSignalTarget(tc)
            p = metools.Pipeline('t', [], Input = {'e.nii'});
            p.add(fake.Producer());
            p.add(fake.Branch());
            p.add(fake.SignalTarget());
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEmpty(plan.Warnings);
            tc.verifyEqual(plan.Steps(3).reads(1).port, 'Signal');
            tc.verifyEqual(plan.Steps(3).reads(1).files, {'re.nii'});
            tc.verifyEqual(plan.Steps(3).reads(2).port, 'Target');
            tc.verifyEqual(plan.Steps(3).reads(2).files, {'bre.nii'});
            v = plan.Env.current('bold_branch');
            tc.verifyEqual(v.files, {'qbre.nii'});
            v = plan.Env.current('bold');
            tc.verifyEqual(v.files, {'re.nii'});
            tc.verifyNumElements(plan.Env.history('bold_branch'), 2);
        end

        function followsRedirectsOutputToBoundStream(tc)
            in = struct('bold_other', {{'o.nii'}});
            p = metools.Pipeline('t', [], Input = in);
            p.add(fake.Transform(), 'In', 'bold_other');
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyFalse(plan.Env.has('bold'));
            v = plan.Env.current('bold_other');
            tc.verifyEqual(v.files, {'fo.nii'});
        end

        function multipleInputStreams(tc)
            in = struct('bold', {{'x.nii'}}, 'bold_mean', 'm.nii');
            p = metools.Pipeline('t', [], Input = in);
            p.add(fake.NeedsMean());
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEqual(plan.Steps(1).reads(2).files, {'m.nii'});
        end

        function missingStreamIsError(tc)
            p = metools.Pipeline('t', [], Input = {'e.nii'});
            p.add(fake.NeedsMean());
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifyNumElements(plan.Errors, 1);
            tc.verifySubstring(plan.Errors{1}, 'bold_mean');
            tc.verifyError(@() p.validate(), 'Pipeline:Invalid');
        end

        function failureDoesNotCascade(tc)
            p = metools.Pipeline('t', [], Input = {'e.nii'});
            p.add(fake.NeedsMean());
            p.add(fake.Transform());
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifyNumElements(plan.Errors, 1);
            tc.verifyEqual(plan.Steps(2).status, 'skipped');
        end

        function noInputIsError(tc)
            p = metools.Pipeline('t');
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
        end

        function cardinalityOne(tc)
            p = metools.Pipeline('t', [], Input = {'a.nii', 'b.nii', 'c.nii'});
            p.add(fake.NeedsOne());
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'expects exactly 1');
        end

        function cardinalityMany(tc)
            p = metools.Pipeline('t', [], Input = {'a.nii'});
            p.add(fake.Combine());
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'at least 2');
        end

        function combinationReducesCardinality(tc)
            p = metools.Pipeline('t', [], Input = {'a.nii', 'b.nii', 'c.nii'});
            p.add(fake.Combine());
            p.add(fake.NeedsOne());
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            v = plan.Env.current('bold');
            tc.verifyEqual(v.files, {'nc_bold.nii'});
        end

        function stepSpecificCheck(tc)
            p = metools.Pipeline('t', [], Input = {'a.nii', 'b.nii'});
            p.add(fake.Combine());     % TEs has 3 values, the input has 2 files
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'TEs');
        end

        function optionalInput(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.OptionalIn());
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEqual(plan.Steps(1).writes(1).files, {'nx.nii'});

            in = struct('bold', {{'x.nii'}}, 'rp', 'rp.txt');
            p2 = metools.Pipeline('t', [], Input = in);
            p2.add(fake.OptionalIn());
            plan2 = p2.compile();
            tc.verifyTrue(plan2.Ok);
            tc.verifyEqual(plan2.Steps(1).writes(1).files, {'yx.nii'});
        end

        function parameterValidation(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            tc.verifyError(@() p.add(fake.Transform(), 'Lambda', -1), 'Step:BadValue');
            tc.verifyError(@() p.add(fake.Transform(), 'Prefix', struct('a', 1)), 'Step:BadValue');
            tc.verifyError(@() p.add(fake.Transform(), 'Preffix', 'r'), 'Step:UnknownOption');
            tc.verifyError(@() p.add(fake.Transform(), 'In', 5), 'Step:BadBinding');
            tc.verifyError(@() p.add(fake.Transform(), 'Prefix'), 'Step:BadArguments');
            tc.verifyEqual(p.numSteps(), 0);
        end

        function parameterNames(tc)
            step = fake.Transform();
            names = step.parameterNames();
            tc.verifyEqual(sort(names), sort({'Prefix', 'Lambda'}));
        end

        function addRejectsNonStep(tc)
            p = metools.Pipeline('t');
            tc.verifyError(@() p.add(42), 'Pipeline:BadStep');
        end

        function retainFreesIntermediates(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.add(fake.Transform(), 'Prefix', 'c');
            p.Retain('bold');
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEmpty(plan.Warnings);
            tc.verifyEmpty(plan.DeleteAfter{1});
            tc.verifyEqual(plan.DeleteAfter{2}, {'rx.nii'});
            tc.verifyEqual(plan.DeleteAfter{3}, {'brx.nii'});
            tc.verifyEqual(plan.FreeAfter{2}, 2);
            tc.verifyEqual(plan.FreeAfter{3}, 3);
        end

        function retainAllDeletesNothing(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.Retain('bold');
            p.Retain('all');
            plan = p.compile();
            tc.verifyTrue(plan.RetainAll);
            tc.verifyEmpty(plan.DeleteAfter{1});
            tc.verifyEmpty(plan.DeleteAfter{2});
        end

        function retainKeepsRawInputs(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform(), 'Prefix', 'r');
            p.Retain('bold');
            plan = p.compile();
            allDeleted = [plan.DeleteAfter{:}];
            tc.verifyFalse(any(strcmp(allDeleted, 'x.nii')));
        end

        function retainUnknownStreamIsError(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform());
            p.Retain('nonexistent');
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'nonexistent');
        end

        function retainRequiresArgument(tc)
            p = metools.Pipeline('t');
            tc.verifyError(@() p.Retain(), 'Pipeline:BadRetain');
        end

        function unusedOutputWarning(tc)
            p = metools.Pipeline('t', [], Input = {'e.nii'});
            p.add(fake.Producer());    % bold, bold_mean, rp
            p.Retain('bold');
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyNumElements(plan.Warnings, 2);
        end

        function passThroughFileIsNeverDeleted(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.PassThrough());
            p.Retain('bold');
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEmpty(plan.DeleteAfter{1});
            tc.verifyEmpty(plan.DeleteAfter{2});
        end

        function staleBranchWarning(tc)
            p = metools.Pipeline('t', [], Input = {'e.nii'});
            p.add(fake.Producer());
            p.add(fake.Branch());
            p.add(fake.Transform(), 'Prefix', 'z');    % changes bold, bold_branch derives from the old bold
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyNumElements(plan.Warnings, 1);
            tc.verifySubstring(plan.Warnings{1}, 'bold_branch');
        end

        function outputCollisionIsError(tc)
            p = metools.Pipeline('t', [], Input = {'x.nii'});
            p.add(fake.Branch());
            p.add(fake.Branch(), 'Out', 'bold_branch2');    % same prefix -> same file bx.nii
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'bx.nii');
        end

        function overwritingRawInputIsError(tc)
            % the step Branch (prefix b) would overwrite the second input file 'be.nii'
            in = struct('bold', {{'e.nii'}}, 'aux', 'be.nii');
            p = metools.Pipeline('t', [], Input = in);
            p.add(fake.Branch());
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'input file');
        end

        function copyIsDeep(tc)
            a = metools.Pipeline('a', [], Input = {'x.nii'});
            a.add(fake.Transform(), 'Prefix', 'r');
            b = a.copy('b');
            b.add(fake.Transform(), 'Prefix', 'z');
            s = b.Steps{1};
            s.Prefix = 'q';
            tc.verifyEqual(a.numSteps(), 1);
            tc.verifyEqual(b.numSteps(), 2);
            tc.verifyEqual(b.Name, 'b');
            tc.verifyEqual(a.Name, 'a');
            first = a.Steps{1};
            tc.verifyEqual(first.Prefix, 'r');
        end

        function describeProducesText(tc)
            p = metools.Pipeline('rest', [], Input = {'e.nii'});
            p.add(fake.Producer());
            p.add(fake.Branch(), 'Prefix', 's');
            p.Retain('bold', 'bold_branch', 'bold_mean', 'rp');
            plan = p.compile();
            text = strjoin(metools.PlanFormatter.format(plan), newline);
            tc.verifySubstring(text, 'Pipeline ''rest''');
            tc.verifySubstring(text, 'bold <- input');
            tc.verifySubstring(text, 'bold_branch -> sre.nii');
            tc.verifySubstring(text, 'Validation: OK');
            tc.verifySubstring(text, 'Retain: bold, bold_branch, bold_mean, rp');
        end

        function describeShowsErrors(tc)
            p = metools.Pipeline('t', [], Input = {'e.nii'});
            p.add(fake.NeedsMean());
            plan = p.compile();
            text = strjoin(metools.PlanFormatter.format(plan), newline);
            tc.verifySubstring(text, 'ERROR');
            tc.verifySubstring(text, 'Validation: FAILED');
        end

        function badInputType(tc)
            tc.verifyError(@() metools.Pipeline('t', [], Input = 5), 'StreamEnv:BadFiles');
        end
    end
end
