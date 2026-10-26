classdef RunLog < handle
    % RUNLOG  HTML logs of Pipeline.runFor (used internally; logging is on with LogDir).
    %
    %   <LogDir>/<pipeline>_<session>_<time>.html            summary of the whole run
    %   <subject>/logs/<pipeline>_<session>_<time>/log.html   detailed log of one unit
    %   <subject>/logs/<pipeline>_<session>_<time>/NN_<step>.txt   captured console output
    %   <subject>/logs/<pipeline>_<session>_<time>/qc/        QC figures written by steps
    %
    % The files are rewritten after every step, so a crash leaves a valid log behind.
    % When logging is off (empty LogDir) every method does nothing.

    properties (SetAccess = private)
        Enabled = false
        SummaryFile = ''
        UnitFile = ''          % detailed log of the unit that is running
    end

    properties (Access = private)
        PipeName
        Session
        Stamp
        Started
        Env
        Range
        StepNames
        PlanLines
        ConfigLines
        Caller
        CallerSource
        LibVersion
        Units = struct('Subject', {}, 'Session', {}, 'File', {}, 'Status', {})
        Unit                   % detailed record of the running unit
    end

    methods
        function obj = RunLog(pipe, session, logDir, env, range)
            if isempty(logDir)
                return
            end
            obj.Enabled = true;
            obj.PipeName = pipe.Name;
            obj.Session = session;
            obj.Stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
            obj.Started = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
            obj.Env = env;
            obj.Range = range;
            obj.StepNames = cellfun(@(s) s.Name, pipe.Steps, 'UniformOutput', false);
            obj.PlanLines = metools.PlanFormatter.format(pipe.compile());
            obj.ConfigLines = {};
            if ~isempty(pipe.Config) && ismethod(pipe.Config, 'describe')
                obj.ConfigLines = pipe.Config.describe();
            end
            [obj.Caller, obj.CallerSource] = metools.RunLog.callerScript();
            obj.LibVersion = strtrim(sprintf('%s %s', metools.version(), ...
                metools.RunLog.gitInfo(fileparts(mfilename('fullpath')))));
            if ~exist(logDir, 'dir')
                mkdir(logDir);
            end
            obj.SummaryFile = fullfile(logDir, sprintf('%s_%s_%s.html', obj.PipeName, session, obj.Stamp));
            obj.writeSummary(struct('Subject', {}, 'Session', {}, 'Step', {}, 'Name', {}, ...
                'Status', {}, 'Seconds', {}, 'Message', {}), false);
        end

        function ctx = startUnit(obj, unit, ctx, plan, participants)
            % Creates the log folder of a unit; returns ctx with LogDir and QcDir set.
            if ~obj.Enabled
                return
            end
            dirName = sprintf('%s_%s_%s', obj.PipeName, unit.Session, obj.Stamp);
            unitDir = fullfile(participants.logsDir(unit.Subject), dirName);
            if ~exist(unitDir, 'dir')
                mkdir(unitDir);
            end
            qcDir = fullfile(unitDir, 'qc');
            if ~exist(qcDir, 'dir')
                mkdir(qcDir);
            end
            ctx.LogDir = unitDir;
            ctx.QcDir = qcDir;
            obj.UnitFile = fullfile(unitDir, 'log.html');

            n = numel(obj.StepNames);
            steps = struct('Status', repmat({'pending'}, 1, n), 'Seconds', 0, 'Warnings', {{}}, ...
                'OutputFile', '', 'Output', '', 'Qc', {{}}, 'Error', '');
            u = struct();
            u.Subject = unit.Subject;
            u.Session = unit.Session;
            u.Dir = unitDir;
            u.Started = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
            u.Plan = plan;
            u.PlanLines = metools.PlanFormatter.format(plan);
            u.PlanErrors = {};
            u.Steps = steps;
            obj.Unit = u;
            obj.Units(end+1) = struct('Subject', unit.Subject, 'Session', unit.Session, ...
                'File', obj.UnitFile, 'Status', 'running');
            obj.writeUnit();
        end

        function planFailed(obj, errors)
            if ~obj.Enabled
                return
            end
            obj.Unit.PlanErrors = errors;
            obj.Units(end).Status = 'failed';
            obj.writeUnit();
        end

        function stepSkipped(obj, k)
            if ~obj.Enabled
                return
            end
            obj.Unit.Steps(k).Status = 'skipped';
        end

        function stepDone(obj, k, status, seconds, warns, output, qcItems, ME)
            if ~obj.Enabled
                return
            end
            s = obj.Unit.Steps(k);
            s.Status = status;
            s.Seconds = seconds;
            s.Warnings = warns;
            s.Qc = qcItems;
            if ~isempty(ME)
                s.Error = ME.getReport('extended', 'hyperlinks', 'off');
            end
            if ~isempty(output) || ~isempty(ME)
                name = sprintf('%02d_%s.txt', k, obj.StepNames{k});
                metools.RunLog.writeText(fullfile(obj.Unit.Dir, name), output);
                s.OutputFile = name;
                s.Output = metools.RunLog.tail(output, 200000);
            end
            obj.Unit.Steps(k) = s;
            if strcmp(status, 'failed')
                obj.Units(end).Status = 'failed';
            elseif k == obj.Range(2) && strcmp(obj.Units(end).Status, 'running')
                obj.Units(end).Status = 'ok';
            end
            obj.writeUnit();
        end

        function writeSummary(obj, rows, finished)
            if ~obj.Enabled
                return
            end
            H = metools.RunLog.html();
            b = {};
            b{end+1} = sprintf('<h1>%s <span class="dim">/ %s</span></h1>', H.esc(obj.PipeName), H.esc(obj.Session));
            if finished
                state = sprintf('finished %s', datestr(now, 'yyyy-mm-dd HH:MM:SS')); %#ok<TNOW1,DATST>
            else
                state = 'running';
            end
            meta = {'Started', obj.Started; 'State', state; ...
                'Steps run', sprintf('%d to %d of %d', obj.Range(1), obj.Range(2), numel(obj.StepNames)); ...
                'Environment', strjoin(obj.Env, ', '); 'METools', obj.LibVersion; 'Script', obj.Caller};
            b{end+1} = H.kv(meta);

            % status matrix: units x steps
            b{end+1} = '<h2>Status</h2><table><tr><th>subject</th><th>session</th>';
            for k = 1:numel(obj.StepNames)
                b{end+1} = sprintf('<th>%d %s</th>', k, H.esc(obj.StepNames{k})); %#ok<AGROW>
            end
            b{end+1} = '<th>log</th></tr>';
            for u = 1:numel(obj.Units)
                U = obj.Units(u);
                b{end+1} = sprintf('<tr><td>%s</td><td>%s</td>', H.esc(U.Subject), H.esc(U.Session)); %#ok<AGROW>
                for k = 1:numel(obj.StepNames)
                    r = rows(strcmp({rows.Subject}, U.Subject) & strcmp({rows.Session}, U.Session) & [rows.Step] == k);
                    if isempty(r)
                        b{end+1} = '<td class="st-pending"></td>'; %#ok<AGROW>
                    else
                        tip = H.esc(r(1).Message);
                        b{end+1} = sprintf('<td class="st-%s" title="%s">%s%s</td>', r(1).Status, tip, ...
                            r(1).Status, metools.RunLog.secText(r(1))); %#ok<AGROW>
                    end
                end
                b{end+1} = sprintf('<td><a href="%s">%s</a></td></tr>', H.url(U.File), 'open'); %#ok<AGROW>
            end
            b{end+1} = '</table>';

            failed = rows(strcmp({rows.Status}, 'failed'));
            if ~isempty(failed)
                b{end+1} = '<h2>Failures</h2><ul>';
                for i = 1:numel(failed)
                    b{end+1} = sprintf('<li><b>%s / %s</b>, step %d %s: %s</li>', H.esc(failed(i).Subject), ...
                        H.esc(failed(i).Session), failed(i).Step, H.esc(failed(i).Name), H.esc(failed(i).Message)); %#ok<AGROW>
                end
                b{end+1} = '</ul>';
            end
            b{end+1} = H.details('Plan', H.pre(strjoin(obj.PlanLines, newline)), false);
            if ~isempty(obj.ConfigLines)
                b{end+1} = H.details('Configuration', H.pre(strjoin(obj.ConfigLines, newline)), false);
            end
            if ~isempty(obj.CallerSource)
                b{end+1} = H.details(['Script ' obj.Caller], H.pre(obj.CallerSource), false);
            end
            metools.RunLog.writeText(obj.SummaryFile, H.page(sprintf('%s %s', obj.PipeName, obj.Session), b));
        end
    end

    methods (Access = private)
        function writeUnit(obj)
            H = metools.RunLog.html();
            U = obj.Unit;
            plan = U.Plan;
            b = {};
            b{end+1} = sprintf('<h1>%s <span class="dim">/ %s / %s</span></h1>', H.esc(obj.PipeName), ...
                H.esc(U.Subject), H.esc(U.Session));
            meta = {'Started', U.Started; 'Environment', strjoin(obj.Env, ', '); 'METools', obj.LibVersion; ...
                'Script', obj.Caller; 'Session folder', fileparts(fileparts(U.Dir))};
            b{end+1} = H.kv(meta(1:end-1, :));
            b{end+1} = sprintf('<p><a href="%s">summary of the run</a></p>', H.url(obj.SummaryFile));

            if ~isempty(U.PlanErrors)
                b{end+1} = '<h2 class="bad">Invalid plan</h2><ul>';
                for i = 1:numel(U.PlanErrors)
                    b{end+1} = sprintf('<li>%s</li>', H.esc(U.PlanErrors{i})); %#ok<AGROW>
                end
                b{end+1} = '</ul>';
            end

            % overview
            b{end+1} = '<h2>Steps</h2><table><tr><th>#</th><th>step</th><th>status</th><th>seconds</th><th>output</th><th>message</th></tr>';
            for k = 1:numel(U.Steps)
                s = U.Steps(k);
                if isempty(s.OutputFile)
                    link = '';
                else
                    link = sprintf('<a href="%s">%s</a>', H.esc(s.OutputFile), H.esc(s.OutputFile));
                end
                msg = strjoin(s.Warnings, ' | ');
                if strcmp(s.Status, 'failed')
                    msg = metools.RunLog.firstLine(s.Error);
                end
                b{end+1} = sprintf(['<tr><td><a href="#step%d">%d</a></td><td>%s</td><td class="st-%s">%s</td>' ...
                    '<td>%.1f</td><td>%s</td><td>%s</td></tr>'], k, k, H.esc(obj.StepNames{k}), s.Status, s.Status, ...
                    s.Seconds, link, H.esc(msg)); %#ok<AGROW>
            end
            b{end+1} = '</table>';

            % details of every step
            for k = 1:numel(U.Steps)
                s = U.Steps(k);
                b{end+1} = sprintf('<h2 id="step%d">%d %s <span class="st-%s badge">%s</span></h2>', ...
                    k, k, H.esc(obj.StepNames{k}), s.Status, s.Status); %#ok<AGROW>
                if numel(plan.Steps) >= k
                    ps = plan.Steps(k);
                    if ~isempty(ps.params)
                        b{end+1} = sprintf('<p class="dim">%s</p>', H.esc(ps.params)); %#ok<AGROW>
                    end
                    b{end+1} = metools.RunLog.portTable(H, 'reads', ps.in); %#ok<AGROW>
                    b{end+1} = metools.RunLog.portTable(H, 'writes', ps.out); %#ok<AGROW>
                end
                for w = 1:numel(s.Warnings)
                    b{end+1} = sprintf('<p class="warn">WARNING: %s</p>', H.esc(s.Warnings{w})); %#ok<AGROW>
                end
                if ~isempty(s.Error)
                    b{end+1} = ['<h3 class="bad">Error</h3>' H.pre(s.Error)]; %#ok<AGROW>
                end
                if ~isempty(s.Qc)
                    b{end+1} = metools.RunLog.qcHtml(H, s.Qc, U.Dir); %#ok<AGROW>
                end
                if ~isempty(s.Output)
                    b{end+1} = H.details(sprintf('Console output (%s)', s.OutputFile), ...
                        H.pre(s.Output), strcmp(s.Status, 'failed')); %#ok<AGROW>
                end
            end
            b{end+1} = H.details('Plan', H.pre(strjoin(U.PlanLines, newline)), false);
            metools.RunLog.writeText(obj.UnitFile, H.page(sprintf('%s %s %s', obj.PipeName, U.Subject, U.Session), b));
        end
    end

    methods (Static)
        function [items, problem] = normalizeQc(result)
            % Converts the result of Step.qc to a cell of structs (Title, Kind, Content).
            items = {};
            problem = '';
            if isempty(result)
                return
            end
            if isstruct(result)
                result = num2cell(result);
            end
            if ~iscell(result)
                problem = 'qc() must return a struct array or a cell array of structs.';
                return
            end
            for i = 1:numel(result)
                r = result{i};
                if ~isstruct(r) || ~isscalar(r)
                    problem = 'qc() returned an item that is not a scalar struct.';
                    continue
                end
                item = struct('Title', '', 'Kind', '', 'Content', '');
                if isfield(r, 'Title')
                    item.Title = char(string(r.Title));
                end
                if isfield(r, 'Image') && ~isempty(r.Image)
                    item.Kind = 'image';
                    item.Content = char(r.Image);
                elseif isfield(r, 'Value')
                    item.Kind = 'value';
                    item.Content = metools.Step.formatValue(r.Value);
                elseif isfield(r, 'Text')
                    item.Kind = 'text';
                    item.Content = char(strjoin(string(r.Text), newline));
                else
                    problem = 'qc() returned an item without Image, Value or Text.';
                    continue
                end
                items{end+1} = item; %#ok<AGROW>
            end
        end
    end

    methods (Static, Access = private)
        function H = html()
            H.esc = @metools.RunLog.esc;
            H.pre = @(t) ['<pre>' metools.RunLog.esc(t) '</pre>'];
            H.url = @metools.RunLog.fileUrl;
            H.details = @(title, body, open) metools.RunLog.detailsHtml(title, body, open);
            H.kv = @metools.RunLog.kvHtml;
            H.page = @metools.RunLog.pageHtml;
        end

        function s = esc(t)
            if isempty(t)
                s = '';
                return
            end
            s = char(t);
            s = strrep(s, '&', '&amp;');
            s = strrep(s, '<', '&lt;');
            s = strrep(s, '>', '&gt;');
            s = strrep(s, '"', '&quot;');
        end

        function u = fileUrl(p)
            p = strrep(char(p), '\', '/');
            p = strrep(p, ' ', '%20');
            if ~isempty(regexp(p, '^[A-Za-z]:', 'once'))
                u = ['file:///' p];
            elseif startsWith(p, '//')
                u = ['file:' p];
            else
                u = ['file://' p];
            end
        end

        function s = detailsHtml(title, body, open)
            if open
                o = ' open';
            else
                o = '';
            end
            s = sprintf('<details%s><summary>%s</summary>%s</details>', o, metools.RunLog.esc(title), body);
        end

        function s = kvHtml(pairs)
            s = '<table class="kv">';
            for i = 1:size(pairs, 1)
                s = [s sprintf('<tr><th>%s</th><td>%s</td></tr>', metools.RunLog.esc(pairs{i, 1}), ...
                    metools.RunLog.esc(pairs{i, 2}))]; %#ok<AGROW>
            end
            s = [s '</table>'];
        end

        function s = pageHtml(title, body)
            css = ['body{font-family:Segoe UI,Helvetica,Arial,sans-serif;margin:24px;color:#222;max-width:1400px}' ...
                'h1{font-size:22px}h2{font-size:17px;margin-top:28px;border-bottom:1px solid #ddd}h3{font-size:15px}' ...
                'table{border-collapse:collapse;margin:8px 0}td,th{border:1px solid #ddd;padding:3px 8px;' ...
                'text-align:left;vertical-align:top;font-size:13px}th{background:#f4f4f4}' ...
                'table.kv th{width:140px}pre{background:#f7f7f7;border:1px solid #e3e3e3;padding:8px;' ...
                'overflow:auto;max-height:600px;font-size:12px}.dim{color:#777;font-weight:normal}' ...
                '.st-ok{background:#d9f2d9}.st-failed{background:#f8d0d0}.st-skipped{background:#eee;color:#777}' ...
                '.st-running,.st-pending{background:#fff}.badge{font-size:12px;padding:1px 6px;border-radius:3px}' ...
                '.bad{color:#b00}.warn{color:#a60}details{margin:8px 0}summary{cursor:pointer;color:#036}' ...
                'img{max-width:900px;border:1px solid #ddd;display:block;margin:4px 0}'];
            s = sprintf(['<!DOCTYPE html>\n<html><head><meta charset="utf-8"><title>%s</title>' ...
                '<style>%s</style></head><body>\n%s\n</body></html>\n'], metools.RunLog.esc(title), css, ...
                strjoin(body, newline));
        end

        function s = portTable(H, label, ports)
            s = '';
            if isempty(ports) || ~isstruct(ports)
                return
            end
            names = fieldnames(ports);
            if isempty(names)
                return
            end
            s = sprintf('<table><tr><th colspan="2">%s</th></tr>', label);
            for i = 1:numel(names)
                files = ports.(names{i});
                s = [s sprintf('<tr><td>%s</td><td>%s</td></tr>', H.esc(names{i}), ...
                    strjoin(cellfun(H.esc, files, 'UniformOutput', false), '<br>'))]; %#ok<AGROW>
            end
            s = [s '</table>'];
        end

        function s = qcHtml(H, items, unitDir)
            s = '<h3>Quality control</h3>';
            values = {};
            for i = 1:numel(items)
                it = items{i};
                switch it.Kind
                    case 'value'
                        values(end+1, :) = {it.Title, it.Content}; %#ok<AGROW>
                    case 'text'
                        s = [s sprintf('<p><b>%s</b></p>%s', H.esc(it.Title), H.pre(it.Content))]; %#ok<AGROW>
                    case 'image'
                        src = it.Content;
                        if startsWith(src, [unitDir filesep])
                            src = strrep(src(numel(unitDir) + 2:end), '\', '/');
                        else
                            src = H.url(src);
                        end
                        s = [s sprintf('<p><b>%s</b></p><img src="%s" alt="%s">', H.esc(it.Title), ...
                            H.esc(src), H.esc(it.Title))]; %#ok<AGROW>
                end
            end
            if ~isempty(values)
                s = [s H.kv(values)];
            end
        end

        function t = secText(r)
            if strcmp(r.Status, 'skipped') || r.Seconds == 0
                t = '';
            else
                t = sprintf(' %.0fs', r.Seconds);
            end
        end

        function s = firstLine(t)
            s = strtrim(regexprep(char(t), '[\r\n].*', ''));
        end

        function t = tail(t, n)
            if numel(t) > n
                t = sprintf('... (%d characters omitted, see the text file)\n%s', numel(t) - n, t(end-n+1:end));
            end
        end

        function writeText(file, text)
            % Writes to a temporary file first, so a reader never sees a half-written log.
            tmp = [file '.tmp'];
            fid = fopen(tmp, 'w', 'n', 'UTF-8');
            if fid < 0
                warning('RunLog:Write', 'Cannot write the log file %s', file);
                return
            end
            fprintf(fid, '%s', text);
            fclose(fid);
            movefile(tmp, file, 'f');
        end

        function [file, source] = callerScript()
            % The outermost script or function that called runFor (for the log).
            file = '';
            source = '';
            st = dbstack('-completenames');
            libDir = fileparts(fileparts(mfilename('fullpath')));
            for i = numel(st):-1:1
                if ~isempty(st(i).file) && ~startsWith(st(i).file, libDir)
                    file = st(i).file;
                    break
                end
            end
            if ~isempty(file) && exist(file, 'file') == 2
                info = dir(file);
                if info.bytes < 200000
                    source = fileread(file);
                end
                v = metools.RunLog.gitInfo(fileparts(file));
                if ~isempty(v)
                    file = sprintf('%s   [%s]', file, v);
                end
            end
        end

        function v = gitInfo(folder)
            % 'branch abc1234567' of the git repository containing folder, '' if none.
            v = '';
            d = folder;
            while true
                g = fullfile(d, '.git');
                if exist(fullfile(g, 'HEAD'), 'file') == 2
                    break
                end
                parent = fileparts(d);
                if isempty(parent) || strcmp(parent, d)
                    return
                end
                d = parent;
            end
            try
                head = strtrim(fileread(fullfile(g, 'HEAD')));
                if startsWith(head, 'ref: ')
                    ref = strtrim(head(6:end));
                    branch = regexprep(ref, '^refs/heads/', '');
                    hash = '';
                    rf = fullfile(g, strrep(ref, '/', filesep));
                    if exist(rf, 'file') == 2
                        hash = strtrim(fileread(rf));
                    elseif exist(fullfile(g, 'packed-refs'), 'file') == 2
                        tok = regexp(fileread(fullfile(g, 'packed-refs')), ['(\w{40}) ' regexptranslate('escape', ref)], ...
                            'tokens', 'once');
                        if ~isempty(tok)
                            hash = tok{1};
                        end
                    end
                    v = strtrim(sprintf('%s %s', branch, hash(1:min(10, end))));
                else
                    v = head(1:min(10, end));
                end
            catch
            end
        end
    end
end
