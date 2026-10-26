classdef LoggingTest < matlab.unittest.TestCase
    % Tests of the step range of runFor and of the HTML logs (LogDir, captured output, QC).

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
        function P = project(tc, subjects)
            P = metools.Participants(fullfile(tc.Root, 'proj'), subjects);
            for i = 1:numel(subjects)
                d = P.sessionDir(subjects{i}, 'rest');
                mkdir(d);
                fid = fopen(fullfile(d, 'e.nii'), 'w');
                fclose(fid);
            end
        end

        function d = unitLogDir(~, P, subject)
            listing = dir(fullfile(P.logsDir(subject), 't_rest_*'));
            listing = listing([listing.isdir]);
            d = '';
            if ~isempty(listing)
                d = fullfile(listing(1).folder, listing(1).name);
            end
        end
    end

    methods (Test)
        function endStepStopsEarly(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.add(fake.Transform(), 'Prefix', 'c');
            p.Retain('bold');
            report = p.runFor(P, Session = 'rest', EndStep = 2);
            tc.verifyEqual(report.Status, {'ok'; 'ok'; 'skipped'});
            d = P.sessionDir('sub-01', 'rest');
            tc.verifyTrue(isfile(fullfile(d, 'bre.nii')));     % still needed by step 3: kept
            tc.verifyFalse(isfile(fullfile(d, 're.nii')));     % no longer needed: deleted
            tc.verifyFalse(isfile(fullfile(d, 'cbre.nii')));
        end

        function startAndEndStep(tc)
            P = tc.project({'sub-01'});
            d = P.sessionDir('sub-01', 'rest');
            fid = fopen(fullfile(d, 're.nii'), 'w');
            fclose(fid);
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Transform(), 'Prefix', 'b');
            p.add(fake.Transform(), 'Prefix', 'c');
            report = p.runFor(P, Session = 'rest', StartStep = 2, EndStep = 2);
            tc.verifyEqual(report.Status, {'skipped'; 'ok'; 'skipped'});
        end

        function badRangeIsError(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            p.add(fake.Transform(), 'Prefix', 'b');
            tc.verifyError(@() p.runFor(P, Session = 'rest', StartStep = 2, EndStep = 1), 'Pipeline:BadRange');
            tc.verifyError(@() p.runFor(P, Session = 'rest', StartStep = 3), 'Pipeline:BadRange');
        end

        function noLogsByDefault(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Chatty());
            p.runFor(P, Session = 'rest');
            tc.verifyFalse(isfolder(P.logsDir('sub-01')));
        end

        function logsAreWritten(tc)
            P = tc.project({'sub-01', 'sub-02'});
            logDir = fullfile(tc.Root, 'logs');
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform(), 'Prefix', 'r');
            p.add(fake.Chatty());
            p.LogDir = logDir;
            report = p.runFor(P, Session = 'rest');
            tc.verifyTrue(all(strcmp(report.Status, 'ok')));

            summary = dir(fullfile(logDir, 't_rest_*.html'));
            tc.verifyNumElements(summary, 1);
            html = fileread(fullfile(summary(1).folder, summary(1).name));
            tc.verifySubstring(html, 'sub-01');
            tc.verifySubstring(html, 'sub-02');
            tc.verifySubstring(html, 'finished');

            for s = {'sub-01', 'sub-02'}
                d = tc.unitLogDir(P, s{1});
                tc.assertNotEmpty(d);
                unitHtml = fileread(fullfile(d, 'log.html'));
                tc.verifySubstring(unitHtml, 'hello from the chatty step');   % captured output
                tc.verifySubstring(unitHtml, 'Answer');                       % QC value
                tc.verifySubstring(unitHtml, 'all fine');                     % QC text
                out = fileread(fullfile(d, '02_Chatty.txt'));
                tc.verifySubstring(out, 'hello from the chatty step');
                tc.verifySubstring(out, 'qc of the chatty step');
                tc.verifyTrue(isfile(fullfile(d, 'qc', 'note.txt')));
            end
        end

        function outputOfFailedStepIsKept(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Noisy());
            p.LogDir = fullfile(tc.Root, 'logs');
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(report.Status{1}, 'failed');
            tc.verifySubstring(report.Message{1}, 'noisy failure');
            d = tc.unitLogDir(P, 'sub-01');
            out = fileread(fullfile(d, '01_Noisy.txt'));
            tc.verifySubstring(out, 'last words before the failure');
            unitHtml = fileread(fullfile(d, 'log.html'));
            tc.verifySubstring(unitHtml, 'noisy failure');
            tc.verifySubstring(unitHtml, 'last words before the failure');
        end

        function failingQcIsOnlyWarning(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Chatty(), 'FailQc', true);
            p.LogDir = fullfile(tc.Root, 'logs');
            report = p.runFor(P, Session = 'rest');
            tc.verifyEqual(report.Status{1}, 'ok');
            tc.verifySubstring(report.Message{1}, 'qc exploded');
        end

        function consoleFullPrintsCapturedOutput(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Chatty());
            p.LogDir = fullfile(tc.Root, 'logs');
            p.LogConsole = 'full';
            txt = evalc('p.runFor(P, Session = ''rest'');');
            tc.verifySubstring(txt, 'hello from the chatty step');
            p.LogDir = fullfile(tc.Root, 'logs2');
            p.LogConsole = 'quiet';
            txt = evalc('p.runFor(P, Session = ''rest'');');
            tc.verifyTrue(~contains(txt, 'hello from the chatty step'));
        end

        function relativeLogDirIsInProject(tc)
            P = tc.project({'sub-01'});
            p = metools.Pipeline('t', [], Input = 'e.nii');
            p.add(fake.Transform());
            p.LogDir = 'logs';
            p.runFor(P, Session = 'rest');
            tc.verifyNotEmpty(dir(fullfile(P.ProjectDir, 'logs', 't_rest_*.html')));
        end

        function logSettingsAreValidatedAndCopied(tc)
            p = metools.Pipeline('t', [], Input = 'e.nii');
            tc.verifyError(@() setLogConsole(p, 'loud'), ?MException);
            p.LogDir = "g:/logs";
            p.LogConsole = "full";
            tc.verifyClass(p.LogDir, 'char');
            c = p.copy('c');
            tc.verifyEqual(c.LogDir, 'g:/logs');
            tc.verifyEqual(c.LogConsole, 'full');
        end

        function normalizeQcAcceptsStructArrayAndCell(tc)
            items = metools.RunLog.normalizeQc(struct('Title', {'a', 'b'}, 'Value', {1, 2}));
            tc.verifyNumElements(items, 2);
            tc.verifyEqual(items{2}.Kind, 'value');
            [items, problem] = metools.RunLog.normalizeQc({struct('Title', 'x')});
            tc.verifyEmpty(items);
            tc.verifyNotEmpty(problem);
            [~, problem] = metools.RunLog.normalizeQc(5);
            tc.verifyNotEmpty(problem);
        end

        function fmriCopyKeepsClass(tc)
            a = metools.fmri.FmriPipeline('a', [], Input = {'x.nii'});
            a.Smooth(FWHM = 4);
            b = a.copy('b');
            tc.verifyClass(b, 'metools.fmri.FmriPipeline');
            b.Smooth(FWHM = 8, Out = 'bold_smooth8', Prefix = 's8');
            tc.verifyEqual(a.numSteps(), 1);
            tc.verifyEqual(b.numSteps(), 2);
        end

        function configDescribeListsValues(tc)
            cfg = metools.fmri.FmriConfig();
            cfg.acq.TR = 0.851;
            cfg.addOverride('video', 'acq.TR', 2);
            text = strjoin(cfg.describe(), newline);
            tc.verifySubstring(text, 'acq.TR = 0.851');
            tc.verifySubstring(text, 'override [video] acq.TR = 2');
        end
    end
end

function setLogConsole(p, value)
    p.LogConsole = value;
end
