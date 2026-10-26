classdef Pipeline < handle
    % PIPELINE  Declarative assembly and execution of processing pipelines (generic core).
    %
    % This class knows nothing about a particular modality. Domain pipelines derive from
    % it and add convenience methods for their built-in steps (metools.fmri.FmriPipeline).
    %
    %   pipe = metools.fmri.FmriPipeline('rest', cfg, Input = {'_echo_1.nii', '_echo_2.nii'});
    %   pipe.Realign(Master = 2);                         % built-in step of the fMRI pipeline
    %   pipe.add(MyStep(), 'Param', value);               % any metools.Step subclass
    %   pipe.Retain('bold', 'bold_smooth');               % delete the other intermediates
    %   pipe.describe();                                  % plan + static validation
    %   P = metools.Participants(cfg.paths.project, subjects);
    %   pipe.dryRun(P, Session = "rest");                 % check data and environment
    %   pipe.LogDir = 'logs';                             % HTML logs (optional)
    %   report = pipe.runFor(P, Session = "rest");        % run
    %
    % A pipeline knows only its steps and the data flow between them (streams); it does
    % not know subjects. compile() walks the steps symbolically: each step reads the
    % latest version of the stream bound to each of its input ports, predict() names the
    % output files, and the outputs are written back into the stream environment. The
    % resulting plan drives validation, describe() and the execution for a subject.

    properties
        Name = 'pipeline'
        Config = []            % metools.Config (a shared reference, not copied by copy())
        LogDir char = ''       % folder of the summary HTML log; '' = no logs. A relative
                               % folder is placed in the project folder of the participants.
        LogConsole char {mustBeMember(LogConsole, {'quiet', 'full'})} = 'quiet'
                               % with logs: 'quiet' = only progress in the console,
                               % 'full' = also the captured output of every step
    end

    properties (SetAccess = private)
        Steps = {}             % cell array of Step objects
        Inputs = struct()      % input streams: name -> row cellstr of files
        RetainAll = true       % true = nothing is deleted
        RetainList = {}        % streams whose latest version is kept
    end

    methods
        function obj = Pipeline(name, cfg, options)
            arguments
                name (1,:) char = 'pipeline'
                cfg = []
                options.Input = []
            end
            obj.Name = name;
            obj.Config = cfg;
            if ~isempty(options.Input)
                obj.setInput(options.Input);
            end
        end

        function setInput(obj, input)
            % Input: cellstr / string / char (= stream 'bold') or a struct stream -> files.
            % Relative names are resolved against the session folder when the pipeline runs.
            obj.Inputs = metools.Pipeline.normalizeInput(input);
        end

        function step = add(obj, step, varargin)
            % Appends a step; varargin are name/value pairs (parameters, port overrides, Keep).
            if ~isa(step, 'metools.Step')
                error('Pipeline:BadStep', 'Pipeline.add: the argument must be a Step object.');
            end
            step.validatePorts();
            step.configure(varargin{:});
            obj.Steps{end+1} = step;
        end

        function n = numSteps(obj)
            n = numel(obj.Steps);
        end

        function Retain(obj, varargin)
            % Retain('bold', 'bold_smooth') keeps the latest version of these streams; all
            % other files are deleted after their last use (pipeline inputs never).
            % Retain('all') deletes nothing (default). Step option Keep protects the output
            % of one particular step as well.
            if isempty(varargin)
                error('Pipeline:BadRetain', 'Retain: give stream names or "all".');
            end
            names = {};
            for i = 1:numel(varargin)
                a = varargin{i};
                if iscell(a)
                    for j = 1:numel(a)
                        names{end+1} = metools.Pipeline.retainName(a{j}); %#ok<AGROW>
                    end
                else
                    names{end+1} = metools.Pipeline.retainName(a); %#ok<AGROW>
                end
            end
            if isscalar(names) && strcmp(names{1}, 'all')
                obj.RetainAll = true;
                obj.RetainList = {};
            else
                obj.RetainAll = false;
                obj.RetainList = unique(names, 'stable');
            end
        end

        function cp = copy(obj, newName)
            % Deep copy (steps are copied); the Config stays a shared reference.
            cp = feval(class(obj), obj.Name, obj.Config);     % keeps the subclass
            cp.Inputs = obj.Inputs;
            cp.RetainAll = obj.RetainAll;
            cp.RetainList = obj.RetainList;
            cp.LogDir = obj.LogDir;
            cp.LogConsole = obj.LogConsole;
            cp.Steps = cell(1, numel(obj.Steps));
            for i = 1:numel(obj.Steps)
                cp.Steps{i} = obj.Steps{i}.copy();
            end
            if nargin > 1
                cp.Name = newName;
            end
        end

        function info = environmentInfo(~)
            % Software versions written to the console and the logs. Domain pipelines
            % extend it (e.g. with the SPM and CAT12 versions).
            info = {['METools ' metools.version()], ['MATLAB ' version]};
        end
        % ------------------------------------------------------------------
        % Static validation and description
        % ------------------------------------------------------------------
        function plan = validate(obj)
            % Prints warnings; throws Pipeline:Invalid when the pipeline has errors.
            plan = obj.compile();
            for i = 1:numel(plan.Warnings)
                fprintf('WARNING: %s\n', plan.Warnings{i});
            end
            if ~plan.Ok
                error('Pipeline:Invalid', 'Pipeline "%s" is invalid:\n  %s', ...
                    obj.Name, strjoin(plan.Errors, sprintf('\n  ')));
            end
        end

        function plan = describe(obj)
            % Prints the plan (what each step reads and writes) and the validation result.
            plan = obj.compile();
            lines = metools.PlanFormatter.format(plan);
            for i = 1:numel(lines)
                fprintf('%s\n', lines{i});
            end
            if nargout == 0
                clear plan
            end
        end

        function plan = compile(obj, inputs, ctx)
            % Symbolic walk through the pipeline. inputs (optional) replaces Inputs (e.g.
            % absolute paths of one subject), ctx is the context of a unit (empty during
            % static validation - predict() must cope with that).
            if nargin < 2 || isempty(inputs)
                inputs = obj.Inputs;
            end
            if nargin < 3
                ctx = [];
            end
            cfg = obj.Config;
            if isstruct(ctx) && isfield(ctx, 'Cfg') && ~isempty(ctx.Cfg)
                cfg = ctx.Cfg;
            end

            env = metools.StreamEnv();
            errors = {};
            warnings = {};
            producedBy = containers.Map('KeyType', 'char', 'ValueType', 'double');

            inNames = fieldnames(inputs);
            if isempty(inNames)
                errors{end+1} = 'The pipeline has no input streams (option Input).';
            end
            for i = 1:numel(inNames)
                files = metools.StreamEnv.toFiles(inputs.(inNames{i}));
                if isempty(files)
                    errors{end+1} = sprintf('Input stream "%s" is empty.', inNames{i}); %#ok<AGROW>
                    continue
                end
                env.add(inNames{i}, files, '', 0, [], ['input:' inNames{i} '=' strjoin(files, '|')]);
                for j = 1:numel(files)
                    producedBy(files{j}) = 0;
                end
            end

            nSteps = numel(obj.Steps);
            stepInfo = struct('index', {}, 'name', {}, 'params', {}, 'status', {}, ...
                'reads', {}, 'writes', {}, 'in', {}, 'out', {});
            poisoned = {};

            for k = 1:nSteps
                step = obj.Steps{k};
                label = sprintf('Step #%d %s', k, step.Name);
                status = 'ok';
                reads = repmat(metools.Pipeline.mkref('', '', 0, {}), 1, 0);
                writes = reads;
                ports = step.ports();
                inPorts = step.portNames('in');
                outPorts = step.portNames('out');
                in = struct();
                parents = [];
                skipped = false;

                % --- inputs: the latest version of the stream of every input port
                for p = 1:numel(inPorts)
                    pn = inPorts{p};
                    port = ports.(pn);
                    stream = step.streamFor(pn);
                    if any(strcmp(stream, poisoned))
                        skipped = true;
                        in.(pn) = {};
                        continue
                    end
                    if ~env.has(stream)
                        in.(pn) = {};
                        if port.Optional
                            continue
                        end
                        errors{end+1} = sprintf(['%s: stream "%s" (port %s) is not available - no earlier ' ...
                            'step produces it and it is not a pipeline input.'], label, stream, pn); %#ok<AGROW>
                        status = 'error';
                        continue
                    end
                    v = env.current(stream);
                    n = numel(v.files);
                    if strcmp(port.Cardinality, 'one') && n ~= 1
                        errors{end+1} = sprintf('%s: port %s expects exactly 1 file, stream "%s" has %d.', ...
                            label, pn, stream, n); %#ok<AGROW>
                        status = 'error';
                    elseif strcmp(port.Cardinality, 'many') && n < 2
                        errors{end+1} = sprintf('%s: port %s expects at least 2 files, stream "%s" has %d.', ...
                            label, pn, stream, n); %#ok<AGROW>
                        status = 'error';
                    end
                    in.(pn) = v.files;
                    reads(end+1) = metools.Pipeline.mkref(pn, stream, v.id, v.files); %#ok<AGROW>
                    parents(end+1) = v.id; %#ok<AGROW>
                end
                if strcmp(status, 'ok') && skipped
                    status = 'skipped';
                end

                % --- parameters bound to the configuration
                if strcmp(status, 'ok')
                    bindings = step.configBindings();
                    bnames = fieldnames(bindings);
                    for q = 1:numel(bnames)
                        if isempty(step.resolve(bnames{q}, cfg))
                            errors{end+1} = sprintf('%s: parameter "%s" is not set and cfg.%s is empty.', ...
                                label, bnames{q}, bindings.(bnames{q})); %#ok<AGROW>
                            status = 'error';
                        end
                    end
                end

                % --- step-specific checks
                if strcmp(status, 'ok')
                    msgs = step.check(in, cfg);
                    if ischar(msgs)
                        msgs = {msgs};
                    elseif isstring(msgs)
                        msgs = cellstr(msgs);
                    end
                    for m = 1:numel(msgs)
                        errors{end+1} = sprintf('%s: %s', label, msgs{m}); %#ok<AGROW>
                        status = 'error';
                    end
                end

                % --- prediction of the outputs
                outFiles = struct();
                if strcmp(status, 'ok')
                    try
                        out = step.predict(in, ctx);
                    catch ME
                        out = [];
                        errors{end+1} = sprintf('%s: predict() failed: %s', label, ME.message); %#ok<AGROW>
                        status = 'error';
                    end
                end
                if strcmp(status, 'ok')
                    [outFiles, problems] = metools.Pipeline.checkOutputs(ports, outPorts, out);
                    for m = 1:numel(problems)
                        errors{end+1} = sprintf('%s: %s', label, problems{m}); %#ok<AGROW>
                        status = 'error';
                    end
                end

                % --- collisions of output files
                if strcmp(status, 'ok')
                    inFiles = {};
                    for r = 1:numel(reads)
                        inFiles = [inFiles, reads(r).files]; %#ok<AGROW>
                    end
                    claimed = {};
                    for p = 1:numel(outPorts)
                        pn = outPorts{p};
                        if ~isfield(outFiles, pn)
                            continue
                        end
                        f = outFiles.(pn);
                        for j = 1:numel(f)
                            if ismember(f{j}, inFiles)
                                continue    % pass-through step: same file as the input
                            end
                            if isKey(producedBy, f{j})
                                who = producedBy(f{j});
                                if who == 0
                                    src = 'it is an input file of the pipeline, the step would overwrite it';
                                else
                                    src = sprintf('it is already produced by step #%d', who);
                                end
                                errors{end+1} = sprintf('%s: output file "%s" - %s.', label, f{j}, src); %#ok<AGROW>
                                status = 'error';
                            elseif ismember(f{j}, claimed)
                                errors{end+1} = sprintf('%s: several output ports of the step produce the same file "%s".', ...
                                    label, f{j}); %#ok<AGROW>
                                status = 'error';
                            end
                            claimed{end+1} = f{j}; %#ok<AGROW>
                        end
                    end
                end

                % --- Keep must refer to streams the step really writes
                if strcmp(status, 'ok') && ~isempty(step.Keep)
                    written = {};
                    for p = 1:numel(outPorts)
                        if isfield(outFiles, outPorts{p})
                            written{end+1} = step.streamFor(outPorts{p}); %#ok<AGROW>
                        end
                    end
                    for q = 1:numel(step.Keep)
                        if ~any(strcmp(step.Keep{q}, written))
                            errors{end+1} = sprintf('%s: Keep refers to stream "%s", which the step does not write.', ...
                                label, step.Keep{q}); %#ok<AGROW>
                            status = 'error';
                        end
                    end
                end

                if strcmp(status, 'ok')
                    % --- stale branch: the step modifies stream S, but another stream T is
                    % derived from the version of S it reads, and the step does not read T
                    readStreams = {reads.stream};
                    for p = 1:numel(outPorts)
                        S = step.streamFor(outPorts{p});
                        idx = find(strcmp(readStreams, S), 1);
                        if isempty(idx) || ~isfield(outFiles, outPorts{p})
                            continue
                        end
                        readVersion = reads(idx).version;
                        others = setdiff(env.streams(), {S});
                        for o = 1:numel(others)
                            T = others{o};
                            if any(strcmp(readStreams, T))
                                continue
                            end
                            cur = env.current(T);
                            if ismember(readVersion, cur.ancestors)
                                warnings{end+1} = sprintf(['%s: modifies stream "%s", but stream "%s" is derived ' ...
                                    'from its previous version and will be left stale.'], label, S, T); %#ok<AGROW>
                            end
                        end
                    end

                    % --- write the outputs into the environment
                    parentSigs = cell(1, numel(parents));
                    for q = 1:numel(parents)
                        pv = env.Versions(parents(q));
                        parentSigs{q} = pv.sig;
                    end
                    sigBase = sprintf('%s [%s]', step.signature(), strjoin(parentSigs, '; '));
                    for p = 1:numel(outPorts)
                        pn = outPorts{p};
                        if ~isfield(outFiles, pn)
                            continue
                        end
                        S = step.streamFor(pn);
                        id = env.add(S, outFiles.(pn), pn, k, parents, [sigBase ' -> ' pn '=' S]);
                        writes(end+1) = metools.Pipeline.mkref(pn, S, id, outFiles.(pn)); %#ok<AGROW>
                        f = outFiles.(pn);
                        for j = 1:numel(f)
                            if ~isKey(producedBy, f{j})
                                producedBy(f{j}) = k;
                            end
                        end
                    end
                else
                    % outputs are not available; later steps must not pretend they are
                    for p = 1:numel(outPorts)
                        poisoned{end+1} = step.streamFor(outPorts{p}); %#ok<AGROW>
                    end
                end

                info = struct('index', k, 'name', step.Name, 'params', step.paramString(), ...
                    'status', status, 'reads', reads, 'writes', writes, 'in', in, 'out', outFiles);
                stepInfo(k) = info;
            end

            % --- consumers of every version
            nV = numel(env.Versions);
            consumers = cell(1, nV);
            for k = 1:numel(stepInfo)
                for r = 1:numel(stepInfo(k).reads)
                    id = stepInfo(k).reads(r).version;
                    consumers{id}(end+1) = k;
                end
            end

            % --- release of files (Retain / Keep)
            freeAfter = cell(1, nSteps);
            for k = 1:nSteps
                freeAfter{k} = [];
            end
            deleteAfter = repmat({{}}, 1, nSteps);
            if ~obj.RetainAll
                retained = false(1, nV);
                for i = 1:numel(obj.RetainList)
                    nm = obj.RetainList{i};
                    if env.has(nm)
                        cur = env.current(nm);
                        retained(cur.id) = true;
                    elseif ~any(strcmp(nm, poisoned))
                        errors{end+1} = sprintf('Retain: stream "%s" does not exist in the pipeline.', nm); %#ok<AGROW>
                    end
                end
                for id = 1:nV
                    ver = env.Versions(id);
                    if ver.step > 0 && any(strcmp(ver.stream, obj.Steps{ver.step}.Keep))
                        retained(id) = true;
                    end
                end
                if isempty(errors)
                    freeStep = inf(1, nV);
                    for id = 1:nV
                        ver = env.Versions(id);
                        if ver.step == 0 || retained(id)
                            continue
                        end
                        freeStep(id) = max([ver.step, consumers{id}]);
                        if isempty(consumers{id})
                            warnings{end+1} = sprintf(['Step #%d %s produces "%s", which is never used and is ' ...
                                'not retained (it will be deleted right after the step).'], ...
                                ver.step, obj.Steps{ver.step}.Name, ver.stream); %#ok<AGROW>
                        end
                    end
                    % A file is deleted after the last version that needs it
                    % (pass-through steps share files between versions).
                    lastNeeded = containers.Map('KeyType', 'char', 'ValueType', 'double');
                    for id = 1:nV
                        f = env.Versions(id).files;
                        for j = 1:numel(f)
                            if isKey(lastNeeded, f{j})
                                lastNeeded(f{j}) = max(lastNeeded(f{j}), freeStep(id));
                            else
                                lastNeeded(f{j}) = freeStep(id);
                            end
                        end
                    end
                    fileKeys = keys(lastNeeded);
                    for j = 1:numel(fileKeys)
                        ln = lastNeeded(fileKeys{j});
                        if isfinite(ln)
                            deleteAfter{ln}{end+1} = fileKeys{j};
                        end
                    end
                    for id = 1:nV
                        if isfinite(freeStep(id))
                            freeAfter{freeStep(id)}(end+1) = id;
                        end
                    end
                end
            end

            plan = struct();
            plan.Name = obj.Name;
            plan.Inputs = inputs;
            plan.Steps = stepInfo;
            plan.Versions = env.Versions;
            plan.Env = env;
            plan.RetainAll = obj.RetainAll;
            plan.RetainList = obj.RetainList;
            plan.FreeAfter = freeAfter;
            plan.DeleteAfter = deleteAfter;
            plan.Errors = errors;
            plan.Warnings = warnings;
            plan.Ok = isempty(errors);
        end

        % ------------------------------------------------------------------
        % Dry run and execution
        % ------------------------------------------------------------------
        function [ok, problems] = dryRun(obj, participants, options)
            % Checks everything that can be checked without running the steps: the static
            % plan, the functions the steps need, the input files and the external files
            % of every unit. Prints a summary; returns ok and the list of problems.
            arguments
                obj
                participants
                options.Session = ''
            end
            session = metools.Pipeline.sessionName(options.Session);
            units = participants.units(session);
            fprintf('Dry run of pipeline "%s": %d subject(s), session "%s", %s\n', ...
                obj.Name, numel(units), session, strjoin(obj.environmentInfo(), ', '));

            problems = {};
            plan0 = obj.compile();
            for i = 1:numel(plan0.Warnings)
                fprintf('WARNING: %s\n', plan0.Warnings{i});
            end
            if ~plan0.Ok
                for i = 1:numel(plan0.Errors)
                    problems{end+1} = ['Static validation: ' plan0.Errors{i}]; %#ok<AGROW>
                end
            else
                for k = 1:numel(obj.Steps)
                    fns = obj.Steps{k}.requiredFunctions();
                    for q = 1:numel(fns)
                        if isempty(which(fns{q}))
                            problems{end+1} = sprintf(['Step #%d %s requires the function "%s", which is not ' ...
                                'on the MATLAB path.'], k, obj.Steps{k}.Name, fns{q}); %#ok<AGROW>
                        end
                    end
                end
                for u = 1:numel(units)
                    [ctx, inputs] = obj.unitContext(participants, units(u));
                    prefix = sprintf('%s / %s: ', units(u).Subject, units(u).Session);
                    plan = obj.compile(inputs, ctx);
                    if ~plan.Ok
                        for i = 1:numel(plan.Errors)
                            problems{end+1} = [prefix plan.Errors{i}]; %#ok<AGROW>
                        end
                        continue
                    end
                    names = fieldnames(inputs);
                    for i = 1:numel(names)
                        files = inputs.(names{i});
                        for j = 1:numel(files)
                            if exist(files{j}, 'file') ~= 2
                                problems{end+1} = sprintf('%sinput file not found: %s', prefix, files{j}); %#ok<AGROW>
                            end
                        end
                    end
                    for k = 1:numel(obj.Steps)
                        ext = obj.Steps{k}.externalFiles(ctx);
                        for j = 1:numel(ext)
                            if exist(ext{j}, 'file') ~= 2
                                problems{end+1} = sprintf('%sstep #%d %s needs the file "%s", which does not exist.', ...
                                    prefix, k, obj.Steps{k}.Name, ext{j}); %#ok<AGROW>
                            end
                        end
                    end
                end
            end

            ok = isempty(problems);
            if ok
                fprintf('Dry run OK: no problems found.\n');
            else
                fprintf('Dry run found %d problem(s):\n', numel(problems));
                for i = 1:numel(problems)
                    fprintf('  - %s\n', problems{i});
                end
            end
            if nargout == 0
                clear ok problems
            end
        end

        function report = runFor(obj, participants, options)
            % Runs the pipeline for every subject of the participants in one session.
            %   Session          required, e.g. "rest"
            %   StartStep        steps before it are skipped (their outputs must already exist)
            %   EndStep          steps after it are skipped (default: the last step)
            %   ContinueOnError  true: a failed subject is reported and the next one is run
            % The report is a table with one row per unit and step. Logging is set on the
            % pipeline (properties LogDir and LogConsole): a summary in LogDir, detailed logs
            % with the captured output of every step and QC in <subject>/logs/.
            arguments
                obj
                participants
                options.Session = ''
                options.StartStep (1,1) double {mustBeInteger, mustBePositive} = 1
                options.EndStep (1,1) double {mustBePositive} = Inf
                options.ContinueOnError (1,1) logical = true
            end
            session = metools.Pipeline.sessionName(options.Session);
            n = numel(obj.Steps);
            first = options.StartStep;
            last = min(options.EndStep, n);
            if first > n || first > last
                error('Pipeline:BadRange', 'Invalid step range: StartStep = %d, EndStep = %g, the pipeline has %d step(s).', ...
                    first, options.EndStep, n);
            end
            units = participants.units(session);
            env = obj.environmentInfo();
            fprintf('Pipeline "%s": %d subject(s), session "%s", %s\n', ...
                obj.Name, numel(units), session, strjoin(env, ', '));

            logDir = obj.LogDir;
            if ~isempty(logDir) && isempty(regexp(logDir, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
                logDir = fullfile(participants.ProjectDir, logDir);
            end
            runLog = metools.RunLog(obj, session, logDir, env, [first last]);
            if runLog.Enabled
                fprintf('Log: %s\n', runLog.SummaryFile);
            end

            rows = repmat(metools.Pipeline.mkrow('', '', 0, '', '', 0, ''), 1, 0);
            for u = 1:numel(units)
                fprintf('--- %s / %s (%d/%d) ---\n', units(u).Subject, units(u).Session, u, numel(units));
                [rows, failMsg] = obj.runUnit(rows, participants, units(u), first, last, runLog, obj.LogConsole);
                runLog.writeSummary(rows, false);
                if ~isempty(failMsg) && ~options.ContinueOnError
                    runLog.writeSummary(rows, true);
                    error('Pipeline:RunFailed', '%s / %s: %s', units(u).Subject, units(u).Session, failMsg);
                end
            end
            runLog.writeSummary(rows, true);

            report = metools.Pipeline.rowsToTable(rows);
            failed = rows(strcmp({rows.Status}, 'failed'));
            if isempty(failed)
                fprintf('Run finished: all %d unit(s) completed.\n', numel(units));
            else
                bad = unique(strcat({failed.Subject}, ' / ', {failed.Session}));
                fprintf('Run finished: %d of %d unit(s) failed:\n', numel(bad), numel(units));
                for i = 1:numel(failed)
                    fprintf('  - %s / %s, step %d %s: %s\n', failed(i).Subject, failed(i).Session, ...
                        failed(i).Step, failed(i).Name, failed(i).Message);
                end
            end
            if runLog.Enabled
                fprintf('Log: %s\n', runLog.SummaryFile);
            end
        end
    end

    methods (Static)
        function problems = checkCollisions(pipelines, participants, options)
            % Checks that pipelines which will run on the same data do not write the same
            % file from different steps or parameters (e.g. two variants of a pipeline).
            %   problems = Pipeline.checkCollisions([a b], P, Session = "rest")
            arguments
                pipelines
                participants
                options.Session = ''
            end
            session = metools.Pipeline.sessionName(options.Session);
            problems = {};
            units = participants.units(session);
            if isempty(units)
                return
            end
            owner = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(pipelines)
                if iscell(pipelines)
                    p = pipelines{i};
                else
                    p = pipelines(i);
                end
                [ctx, inputs] = p.unitContext(participants, units(1));
                plan = p.compile(inputs, ctx);
                if ~plan.Ok
                    problems{end+1} = sprintf('Pipeline "%s" is invalid: %s', p.Name, strjoin(plan.Errors, ' | ')); %#ok<AGROW>
                    continue
                end
                for id = 1:numel(plan.Versions)
                    ver = plan.Versions(id);
                    if ver.step == 0
                        continue
                    end
                    for j = 1:numel(ver.files)
                        f = ver.files{j};
                        if isKey(owner, f)
                            prev = owner(f);
                            if prev.pipe == i
                                continue            % the same pipeline (e.g. pass-through step)
                            end
                            if ~strcmp(prev.sig, ver.sig)
                                problems{end+1} = sprintf(['Pipelines "%s" (step #%d) and "%s" (step #%d) write ' ...
                                    'the same file "%s" from different steps or parameters.'], ...
                                    prev.name, prev.step, p.Name, ver.step, f); %#ok<AGROW>
                            end
                        else
                            entry = struct('pipe', i, 'name', p.Name, 'step', ver.step, 'sig', ver.sig);
                            owner(f) = entry;
                        end
                    end
                end
            end
        end
    end

    methods (Access = private)
        function [ctx, inputs] = unitContext(obj, participants, unit)
            % Context of one unit and the absolute paths of the pipeline inputs.
            cfg = obj.Config;
            if ~isempty(cfg) && ismethod(cfg, 'forSession')
                cfg = cfg.forSession(unit.Session);
            end
            ctx = participants.context(unit.Subject, unit.Session, cfg);
            inputs = metools.Pipeline.absolutize(obj.Inputs, ctx.SessionDir);
        end

        function [rows, failMsg] = runUnit(obj, rows, participants, unit, first, last, runLog, consoleMode)
            failMsg = '';
            [ctx, inputs] = obj.unitContext(participants, unit);
            plan = obj.compile(inputs, ctx);
            ctx = runLog.startUnit(unit, ctx, plan, participants);
            if ~plan.Ok
                failMsg = strjoin(plan.Errors, ' | ');
                rows(end+1) = metools.Pipeline.mkrow(unit.Subject, unit.Session, 0, 'plan', 'failed', 0, failMsg);
                runLog.planFailed(plan.Errors);
                fprintf('  FAILED: invalid plan: %s\n', failMsg);
                return
            end
            n = numel(obj.Steps);
            for k = 1:n
                name = obj.Steps{k}.Name;
                if k < first || k > last
                    rows(end+1) = metools.Pipeline.mkrow(unit.Subject, unit.Session, k, name, 'skipped', 0, ''); %#ok<AGROW>
                    runLog.stepSkipped(k);
                    continue
                end
                fprintf('  [%d/%d] %s ... ', k, n, name);
                t0 = tic;
                [warns, output, qcItems, ME] = obj.executeStep(k, plan, ctx, runLog.Enabled);
                sec = toc(t0);
                if strcmp(consoleMode, 'full') && ~isempty(output)
                    fprintf('\n%s\n', output);
                end
                if isempty(ME)
                    rows(end+1) = metools.Pipeline.mkrow(unit.Subject, unit.Session, k, name, 'ok', sec, ...
                        strjoin(warns, ' | ')); %#ok<AGROW>
                    runLog.stepDone(k, 'ok', sec, warns, output, qcItems, []);
                    fprintf('done (%.1f s)\n', sec);
                    for w = 1:numel(warns)
                        fprintf('      WARNING: %s\n', warns{w});
                    end
                else
                    failMsg = ME.message;
                    rows(end+1) = metools.Pipeline.mkrow(unit.Subject, unit.Session, k, name, 'failed', sec, ...
                        ME.message); %#ok<AGROW>
                    runLog.stepDone(k, 'failed', sec, warns, output, qcItems, ME);
                    fprintf('FAILED\n      %s\n', ME.message);
                    if runLog.Enabled
                        fprintf('      details: %s\n', runLog.UnitFile);
                    end
                    return
                end
            end
        end

        function [warns, output, qcItems, failure] = executeStep(obj, k, plan, ctx, capture)
            % Runs one step: removes stale outputs, executes, verifies the outputs exist,
            % reports files nobody declared, runs QC (only with logging) and deletes files
            % that are no longer needed. Errors are returned in failure (an MException).
            % With capture = true the console output of the step is returned in output.
            warns = {};
            output = '';
            qcItems = {};
            failure = [];
            step = obj.Steps{k};
            in = plan.Steps(k).in;
            out = plan.Steps(k).out;
            try
                inFiles = metools.Pipeline.allFiles(in);
                outFiles = metools.Pipeline.allFiles(out);

                for i = 1:numel(inFiles)
                    if exist(inFiles{i}, 'file') ~= 2
                        error('Pipeline:MissingInput', 'Step %s: input file does not exist: %s', step.Name, inFiles{i});
                    end
                end

                % outputs left over from an earlier run must not be mistaken for new ones
                for i = 1:numel(outFiles)
                    f = outFiles{i};
                    if ~ismember(f, inFiles) && exist(f, 'file') == 2
                        delete(f);
                        if exist(f, 'file') == 2
                            error('Pipeline:StaleOutput', 'Step %s: cannot remove the old output file %s', step.Name, f);
                        end
                    end
                end

                dirs = metools.Pipeline.stepDirs([inFiles, outFiles]);
                before = metools.Pipeline.snapshot(dirs);

                if capture
                    stepError = [];
                    output = evalc('stepError = metools.Pipeline.invokeStep(step, in, out, ctx);');
                    if ~isempty(stepError)
                        rethrow(stepError);
                    end
                else
                    step.execute(in, out, ctx);
                end

                for i = 1:numel(outFiles)
                    if exist(outFiles{i}, 'file') ~= 2
                        error('Pipeline:MissingOutput', 'Step %s did not create the expected file %s', ...
                            step.Name, outFiles{i});
                    end
                end

                created = setdiff(metools.Pipeline.snapshot(dirs), before);
                undeclared = setdiff(created, outFiles);
                if ~isempty(undeclared)
                    warns{end+1} = ['files created but not declared: ' strjoin(undeclared, ', ')];
                end

                % quality control (optional, only when logging)
                if capture && ~isempty(ctx.QcDir)
                    qcResult = [];
                    qcError = [];
                    qcOutput = evalc('[qcResult, qcError] = metools.Pipeline.invokeQc(step, in, out, ctx);');
                    if ~isempty(qcOutput)
                        output = sprintf('%s\n--- qc ---\n%s', output, qcOutput);
                    end
                    if isempty(qcError)
                        [qcItems, qcProblem] = metools.RunLog.normalizeQc(qcResult);
                        if ~isempty(qcProblem)
                            warns{end+1} = ['qc: ' qcProblem];
                        end
                    else
                        warns{end+1} = ['qc failed: ' qcError.message];
                    end
                end

                toDelete = plan.DeleteAfter{k};
                for i = 1:numel(toDelete)
                    if exist(toDelete{i}, 'file') == 2
                        delete(toDelete{i});
                    end
                end
            catch ME
                failure = ME;
            end
        end
    end

    methods (Static, Hidden)
        function err = invokeStep(step, in, out, ctx)
            % Calls step.execute and returns the error instead of throwing it, so that the
            % output captured by evalc is kept even when the step fails.
            err = [];
            try
                step.execute(in, out, ctx);
            catch ME
                err = ME;
            end
        end

        function [items, err] = invokeQc(step, in, out, ctx)
            items = [];
            err = [];
            try
                items = step.qc(in, out, ctx);
            catch ME
                err = ME;
            end
        end
    end

    methods (Static, Access = private)
        function r = mkref(port, stream, version, files)
            r = struct();
            r.port = port;
            r.stream = stream;
            r.version = version;
            r.files = files;
        end

        function r = mkrow(subject, session, step, name, status, seconds, message)
            r = struct();
            r.Subject = subject;
            r.Session = session;
            r.Step = step;
            r.Name = name;
            r.Status = status;
            r.Seconds = seconds;
            r.Message = message;
        end

        function t = rowsToTable(rows)
            if isempty(rows)
                t = table();
            else
                t = struct2table(rows(:), 'AsArray', true);
            end
        end

        function s = normalizeInput(input)
            s = struct();
            if isstruct(input)
                names = fieldnames(input);
                for i = 1:numel(names)
                    s.(names{i}) = metools.StreamEnv.toFiles(input.(names{i}));
                end
            else
                s.bold = metools.StreamEnv.toFiles(input);
            end
        end

        function out = absolutize(inputs, baseDir)
            out = struct();
            names = fieldnames(inputs);
            for i = 1:numel(names)
                files = inputs.(names{i});
                resolved = cell(size(files));
                for j = 1:numel(files)
                    if ~isempty(regexp(files{j}, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
                        resolved{j} = files{j};
                    else
                        resolved{j} = fullfile(baseDir, files{j});
                    end
                end
                out.(names{i}) = resolved;
            end
        end

        function files = allFiles(s)
            % All files of a struct of cellstr fields as one row cellstr.
            files = {};
            names = fieldnames(s);
            for i = 1:numel(names)
                files = [files, s.(names{i})]; %#ok<AGROW>
            end
        end

        function dirs = stepDirs(files)
            dirs = {};
            for i = 1:numel(files)
                d = fileparts(files{i});
                if ~isempty(d)
                    dirs{end+1} = d; %#ok<AGROW>
                end
            end
            dirs = unique(dirs);
        end

        function files = snapshot(dirs)
            % Files (not folders) currently present in the given folders.
            files = {};
            for i = 1:numel(dirs)
                if exist(dirs{i}, 'dir') ~= 7
                    continue
                end
                d = dir(dirs{i});
                d = d(~[d.isdir]);
                if isempty(d)
                    continue
                end
                names = fullfile(dirs{i}, {d.name});
                files = [files, names(:)']; %#ok<AGROW>
            end
        end

        function s = sessionName(x)
            if isstring(x) && isscalar(x)
                x = char(x);
            end
            if ~ischar(x) || isempty(x)
                error('Pipeline:NoSession', 'The option Session is required (e.g. Session="rest").');
            end
            s = x;
        end

        function name = retainName(a)
            if isstring(a) && isscalar(a)
                a = char(a);
            end
            if ~ischar(a) || isempty(a)
                error('Pipeline:BadRetain', 'Retain: stream names must be non-empty text.');
            end
            name = a;
        end

        function [outFiles, problems] = checkOutputs(ports, outPorts, out)
            outFiles = struct();
            problems = {};
            if ~isstruct(out)
                problems{end+1} = 'predict() must return a struct with one field per output port.';
                return
            end
            given = fieldnames(out);
            extra = setdiff(given, outPorts);
            for i = 1:numel(extra)
                problems{end+1} = sprintf('predict() returned the field "%s", which is not an output port.', extra{i}); %#ok<AGROW>
            end
            for i = 1:numel(outPorts)
                pn = outPorts{i};
                optional = ports.(pn).Optional;
                if ~isfield(out, pn)
                    if ~optional
                        problems{end+1} = sprintf('predict() did not return the output port "%s".', pn); %#ok<AGROW>
                    end
                    continue
                end
                try
                    files = metools.StreamEnv.toFiles(out.(pn));
                catch ME
                    problems{end+1} = sprintf('port "%s": %s', pn, ME.message); %#ok<AGROW>
                    continue
                end
                if isempty(files)
                    if ~optional
                        problems{end+1} = sprintf('port "%s": predict() returned an empty file list.', pn); %#ok<AGROW>
                    end
                    continue
                end
                outFiles.(pn) = files;
            end
        end
    end
end
