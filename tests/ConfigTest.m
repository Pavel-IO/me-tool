classdef ConfigTest < matlab.unittest.TestCase
    % Tests of metools.Config (via FmriConfig) and Participants.

    methods (Test)
        function typedValuesAreValidated(tc)
            cfg = metools.fmri.FmriConfig();
            tc.verifyError(@() setfield_(cfg.acq, 'TR', -1), ?MException);
            tc.verifyError(@() setfield_(cfg.acq, 'Tr', 1), ?MException);   % typo
            tc.verifyError(@() setfield_(cfg.paths, 'project', 5), 'PathsConfig:BadValue');
            cfg.paths.project = "g:/x";                                     % string -> char
            tc.verifyClass(cfg.paths.project, 'char');
        end

        function getAndSetByPath(tc)
            cfg = metools.fmri.FmriConfig();
            cfg.setValue('acq.TR', 0.5);
            tc.verifyEqual(cfg.getValue('acq.TR'), 0.5);
            tc.verifyEqual(cfg.acq.TR, 0.5);
            tc.verifyError(@() cfg.getValue('acq.Nope'), 'Config:BadPath');
            tc.verifyError(@() cfg.setValue('foo.bar', 1), 'Config:BadPath');
        end

        function overridesApplyOnlyToTheirSession(tc)
            cfg = metools.fmri.FmriConfig();
            cfg.acq.TR = 0.85;
            cfg.addOverride('task', 'acq.TR', 2);
            tc.verifyEqual(cfg.forSession('task').acq.TR, 2);
            tc.verifyEqual(cfg.forSession('rest').acq.TR, 0.85);
            tc.verifyEqual(cfg.acq.TR, 0.85);
            tc.verifyError(@() cfg.addOverride('task', 'acq.Nope', 1), 'Config:BadPath');
            tc.verifyError(@() cfg.addOverride('', 'acq.TR', 1), 'Config:BadSession');
        end

        function copyIsDeep(tc)
            a = metools.fmri.FmriConfig();
            a.acq.TR = 1;
            b = a.copy();
            b.acq.TR = 2;
            b.paths.project = 'other';
            tc.verifyEqual(a.acq.TR, 1);
            tc.verifyEmpty(a.paths.project);
        end

        function participantsLayout(tc)
            P = metools.Participants('proj', {'s1', 's2'});
            tc.verifyEqual(P.sessionDir('s1', 'rest'), fullfile('proj', 'data', 's1', 'rest'));
            tc.verifyEqual(P.fieldsDir('s1'), fullfile('proj', 'data', 's1', 'fields'));
            tc.verifyEqual(P.outputsDir(), fullfile('proj', 'outputs'));
            u = P.units('rest');
            tc.verifyEqual({u.Subject}, {'s1', 's2'});
            tc.verifyEqual({u.Session}, {'rest', 'rest'});
            ctx = P.context('s2', 'rest', []);
            tc.verifyEqual(ctx.SubjectDir, fullfile('proj', 'data', 's2'));
            tc.verifyEqual(ctx.SessionDir, fullfile('proj', 'data', 's2', 'rest'));
        end

        function participantsAddIgnoresDuplicates(tc)
            P = metools.Participants('proj', {'s1'});
            P.add({'s1', 's2'});
            P.add("s3");
            tc.verifyEqual(P.Subjects, {'s1', 's2', 's3'});
            tc.verifyError(@() P.add(5), 'Participants:BadSubject');
            tc.verifyError(@() P.add({''}), 'Participants:BadSubject');
        end
    end
end

function setfield_(obj, name, value)
    obj.(name) = value;
end
