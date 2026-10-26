classdef ExecutionTest < matlab.unittest.TestCase
    % Tests of running pipelines on a temporary project folder, using the fake steps of
    % package +fake (they only create empty files).

    properties
        Root
    end

    methods (TestMethodSetup)
        function makeRoot(tc)
            fx = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.Root = fx.Folder;
        end
    end

    methods (Access = private)
        function P = project(tc, subjects, withInput, session)
            % Creates <root>/data/<subject>/<session>/e.nii for each subject.
            if nargin < 4
                session = 'rest';
            end
            P = metools.Participants(tc.Root, subjects);
            for i = 1:numel(subjects)
                d = P.sessionDir(subjects{i}, session);
                mkdir(d);
                if withInput
                    ExecutionTest.touch(fullfile(d, 'e.nii'));
                end
            end
        end
    end

    methods (Static, Access = private)
        function touch(f)
            fid = fopen(f, 'w');
            fclose(fid);
        end
    end

    methods (Test)
        function runCreatesFilesAndAppliesRetain(tc)
            P = tc.project({'sub-01', 'sub-02'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.Retain('bold');
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(height(report), 4);
            tc.verifyTrue(all(strcmp(report.Status, 'ok')));
            for s = {'sub-01', 'sub-02'}
                d = P.sessionDir(s{1}, 'rest');
                tc.verifyTrue(isfile(fullfile(d, 'e.nii')));       % raw input is never deleted
                tc.verifyFalse(isfile(fullfile(d, 're.nii')));     % intermediate, deleted
                tc.verifyTrue(isfile(fullfile(d, 'bre.nii')));     % retained
            end
        end

        function retainAllKeepsEverything(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.runFor(P, Session = 'rest');
            d = P.sessionDir('sub-01', 'rest');
            tc.verifyTrue(isfile(fullfile(d, 're.nii')));
            tc.verifyTrue(isfile(fullfile(d, 'bre.nii')));
        end

        function keepProtectsStepOutput(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r', 'Keep', 'bold');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.Retain('bold');
            plan = p.compile();
            tc.verifyTrue(plan.Ok);
            tc.verifyEmpty(plan.DeleteAfter{2});
            p.runFor(P, Session = 'rest');
            d = P.sessionDir('sub-01', 'rest');
            tc.verifyTrue(isfile(fullfile(d, 're.nii')));
        end

        function keepOfUnwrittenStreamIsError(tc)
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Keep', 'rp');
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'Keep');
            p2 = metools.Pipeline('t');
            tc.verifyError(@() p2.add(fake.Transform(), 'Keep', 'bad name'), 'Step:BadKeep');
        end

        function missingOutputIsFailureAndStaleFileRemoved(tc)
            P = tc.project({'sub-01'}, true);
            d = P.sessionDir('sub-01', 'rest');
            ExecutionTest.touch(fullfile(d, 'le.nii'));            % left over from an earlier run
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Lazy());
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(report.Status{1}, 'failed');
            tc.verifySubstring(report.Message{1}, 'did not create');
            tc.verifyFalse(isfile(fullfile(d, 'le.nii')));
        end

        function undeclaredFilesAreReported(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Sloppy());
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(report.Status{1}, 'ok');
            tc.verifySubstring(report.Message{1}, 'surprise.txt');
        end

        function failedSubjectDoesNotStopOthers(tc)
            P = tc.project({'sub-01', 'sub-02'}, true);
            delete(fullfile(P.sessionDir('sub-01', 'rest'), 'e.nii'));
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(report.Status{1}, 'failed');
            tc.verifySubstring(report.Message{1}, 'does not exist');
            tc.verifyEqual(report.Status{2}, 'ok');
            tc.verifyTrue(isfile(fullfile(P.sessionDir('sub-02', 'rest'), 'fe.nii')));
        end

        function stopOnErrorWhenRequested(tc)
            P = tc.project({'sub-01', 'sub-02'}, true);
            delete(fullfile(P.sessionDir('sub-01', 'rest'), 'e.nii'));
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            tc.verifyError(@() p.runFor(P, Session = 'rest', ContinueOnError = false), 'Pipeline:RunFailed');
            tc.verifyFalse(isfile(fullfile(P.sessionDir('sub-02', 'rest'), 'fe.nii')));
        end

        function exceptionInStepIsReported(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Fail());
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(report.Status{1}, 'failed');
            tc.verifySubstring(report.Message{1}, 'deliberate failure');
        end

        function startStepSkipsEarlierSteps(tc)
            P = tc.project({'sub-01'}, true);
            d = P.sessionDir('sub-01', 'rest');
            ExecutionTest.touch(fullfile(d, 're.nii'));            % output of step 1 already exists
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            report = p.runFor(P, Session = 'rest', StartStep = 2);
            tc.verifyEqual(report.Status, {'skipped'; 'ok'});
            tc.verifyTrue(isfile(fullfile(d, 'bre.nii')));
        end

        function sessionIsRequired(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            tc.verifyError(@() p.runFor(P), 'Pipeline:NoSession');
        end

        function dryRunFindsMissingInputs(tc)
            P = tc.project({'sub-01'}, false);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            [ok, problems] = p.dryRun(P, Session = 'rest');
            tc.verifyFalse(ok);
            tc.verifySubstring(problems{1}, 'input file not found');
        end

        function dryRunChecksExternalFiles(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.NeedsExternal());
            [ok, problems] = p.dryRun(P, Session = 'rest');
            tc.verifyFalse(ok);
            tc.verifySubstring(problems{1}, 't1.nii');
            mkdir(fullfile(P.subjectDir('sub-01'), 'anat'));
            ExecutionTest.touch(fullfile(P.subjectDir('sub-01'), 'anat', 't1.nii'));
            [ok, problems] = p.dryRun(P, Session = 'rest');
            tc.verifyTrue(ok, strjoin(problems, newline));
        end

        function dryRunChecksRequiredFunctions(tc)
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.NeedsFunction());
            [ok, problems] = p.dryRun(P, Session = 'rest');
            tc.verifyFalse(ok);
            tc.verifySubstring(problems{1}, 'metools_no_such_function_xyz');
        end

        function dryRunOkOnValidProject(tc)
            P = tc.project({'sub-01', 'sub-02'}, true);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            [ok, problems] = p.dryRun(P, Session = 'rest');
            tc.verifyTrue(ok, strjoin(problems, newline));
        end

        function configBindingUsesConfigAndSessionOverride(tc)
            cfg = metools.fmri.FmriConfig();
            cfg.acq.TR = 0.85;
            cfg.addOverride('task', 'acq.TR', 2);
            P = tc.project({'sub-01'}, true, 'rest');
            tc.project({'sub-01'}, true, 'task');
            p = metools.Pipeline('t', cfg, Input = 'e.nii');
            p.add(fake.ConfigStep());
            p.runFor(P, Session = 'rest');
            p.runFor(P, Session = 'task');
            tc.verifyTrue(isfile(fullfile(P.sessionDir('sub-01', 'rest'), 'tr0.85_e.nii')));
            tc.verifyTrue(isfile(fullfile(P.sessionDir('sub-01', 'task'), 'tr2_e.nii')));
        end

        function explicitParameterBeatsConfig(tc)
            cfg = metools.fmri.FmriConfig();
            cfg.acq.TR = 0.85;
            P = tc.project({'sub-01'}, true);
            p = metools.Pipeline('t', cfg, Input = 'e.nii');
            p.add(fake.ConfigStep(), 'TR', 3);
            p.runFor(P, Session = 'rest');
            tc.verifyTrue(isfile(fullfile(P.sessionDir('sub-01', 'rest'), 'tr3_e.nii')));
        end

        function missingConfigValueIsStaticError(tc)
            p = metools.Pipeline('t', metools.fmri.FmriConfig(), Input = 'e.nii');
            p.add(fake.ConfigStep());
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'acq.TR');
            tc.verifyError(@() p.validate(), 'Pipeline:Invalid');
        end

        function collisionsBetweenVariants(tc)
            P = tc.project({'sub-01'}, true);
            a = metools.Pipeline('a', [], Input = 'e.nii');
            a.add(fake.Transform(), 'Prefix', 'r', 'Lambda', 1);
            b = a.copy('b');
            % identical copies write identical files from identical steps: no problem
            tc.verifyEmpty(metools.Pipeline.checkCollisions([a b], P, Session = 'rest'));
            c = metools.Pipeline('c', [], Input = 'e.nii');
            c.add(fake.Transform(), 'Prefix', 'r', 'Lambda', 2);   % same file re.nii, other parameters
            problems = metools.Pipeline.checkCollisions([a c], P, Session = 'rest');
            tc.verifyNumElements(problems, 1);
            tc.verifySubstring(problems{1}, 're.nii');
            d = metools.Pipeline('d', [], Input = 'e.nii');
            d.add(fake.Transform(), 'Prefix', 'z', 'Lambda', 2);   % different prefix: no collision
            tc.verifyEmpty(metools.Pipeline.checkCollisions({a, d}, P, Session = 'rest'));
        end
    end
end
