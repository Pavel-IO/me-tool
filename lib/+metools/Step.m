classdef (Abstract) Step < matlab.mixin.Copyable
    % STEP  Base class of all pipeline steps.
    %
    % A subclass declares
    %   - its parameters as public properties with validators (type, size, default),
    %   - ports()                a struct of Port objects (inputs and outputs, default streams),
    %   - predict(in, ctx)       names of the output files, derived from the input files,
    %   - execute(in, out, ctx)  the real work: a call of a processing function that
    %                            receives concrete files and knows nothing about streams,
    % and optionally
    %   - check(in, cfg)         step-specific static checks (returns a cellstr of problems),
    %   - externalFiles(ctx)     extra files the step needs (verified by Pipeline.dryRun),
    %   - requiredFunctions()    functions that must be on the MATLAB path,
    %   - configBindings()       struct: parameter name -> configuration path used when the
    %                            parameter is left empty (e.g. struct('TR', 'acq.TR')),
    %   - qc(in, out, ctx)       quality control items for the log (only when logging is on).
    %
    % The structs in and out have one field per port; each value is a row cellstr of files.
    % predict() must not rely on ctx (it is empty during static validation).
    %
    % Usage: pipe.add(MyStep(), 'Param', value, 'PortName', 'other_stream', 'Keep', {'stream'}).

    properties
        Keep = {}             % streams written by this step whose files Retain must never delete
    end

    properties (SetAccess = protected)
        Bindings = struct()   % port name -> stream name overriding the port default
    end

    properties (Dependent)
        Name
    end

    methods (Abstract)
        p = ports(obj)
        out = predict(obj, in, ctx)
        execute(obj, in, out, ctx)
    end

    methods
        function n = get.Name(obj)
            n = regexprep(class(obj), '^.*\.', '');          % strip package
            n = regexprep(n, '^Step(?=.)', '');              % strip the Step prefix
        end

        function set.Keep(obj, value)
            obj.Keep = metools.Step.toNameList(value);
        end

        function items = qc(~, ~, ~, ~)
            % Optional quality control, called after a successful execute when logging is
            % on (ctx.QcDir is then a folder for figures). Returns a struct array (or a cell
            % of structs) with the field Title and one of Image (file), Value, Text.
            items = [];
        end

        function msgs = check(~, ~, ~)
            msgs = {};
        end

        function files = externalFiles(~, ~)
            files = {};
        end

        function names = requiredFunctions(~)
            names = {};
        end

        function b = configBindings(~)
            b = struct();
        end

        function v = resolve(obj, name, cfg)
            % Value of a parameter: the explicit value, otherwise the one bound in the config.
            v = obj.(name);
            if ~isempty(v)
                return
            end
            b = obj.configBindings();
            if isfield(b, name) && ~isempty(cfg)
                v = cfg.getValue(b.(name));
            end
        end

        function s = signature(obj)
            % Identity of the step: class and parameters (used to compare pipelines).
            s = [class(obj) '(' obj.paramString() ')'];
        end

        function configure(obj, varargin)
            % Sets parameters, port overrides and Keep from name/value pairs.
            if mod(numel(varargin), 2) ~= 0
                error('Step:BadArguments', '%s: options must be name/value pairs.', obj.Name);
            end
            params = obj.parameterNames();
            pnames = fieldnames(obj.ports());
            for i = 1:2:numel(varargin)
                key = varargin{i};
                if ~(ischar(key) || (isstring(key) && isscalar(key)))
                    error('Step:BadArguments', '%s: option names must be text.', obj.Name);
                end
                key = char(key);
                value = varargin{i + 1};
                if any(strcmp(key, params))
                    if isstring(value) && isscalar(value) && ischar(obj.(key))
                        value = char(value);
                    end
                    try
                        obj.(key) = value;
                    catch ME
                        error('Step:BadValue', '%s: parameter "%s": %s', obj.Name, key, ME.message);
                    end
                elseif strcmp(key, 'Keep')
                    obj.Keep = value;
                elseif any(strcmp(key, pnames))
                    obj.bind(key, value);
                else
                    error('Step:UnknownOption', ...
                        '%s: unknown option "%s". Parameters: %s. Ports (stream override): %s. Also: Keep.', ...
                        obj.Name, key, strjoin(params, ', '), strjoin(pnames', ', '));
                end
            end
        end

        function bind(obj, portName, stream)
            % Overrides the stream a port is bound to.
            if isstring(stream) && isscalar(stream)
                stream = char(stream);
            end
            if ~ischar(stream) || isempty(stream) || ~isvarname(stream)
                error('Step:BadBinding', ...
                    '%s: port "%s" can only be overridden by a stream name (variable-like text, e.g. "bold_smooth").', ...
                    obj.Name, portName);
            end
            obj.Bindings.(portName) = stream;
        end

        function s = streamFor(obj, portName)
            % Effective stream of a port (override > Follows > default).
            if isfield(obj.Bindings, portName)
                s = obj.Bindings.(portName);
                return
            end
            p = obj.ports();
            port = p.(portName);
            if ~isempty(port.Follows)
                s = obj.streamFor(port.Follows);
            else
                s = port.Stream;
            end
        end

        function names = portNames(obj, direction)
            p = obj.ports();
            all = fieldnames(p);
            names = {};
            for i = 1:numel(all)
                if strcmp(p.(all{i}).Direction, direction)
                    names{end+1} = all{i}; %#ok<AGROW>
                end
            end
        end

        function validatePorts(obj)
            % Checks that ports() returns a sensible declaration.
            p = obj.ports();
            if ~isstruct(p)
                error('Step:BadPorts', '%s: ports() must return a struct of Port objects.', obj.Name);
            end
            names = fieldnames(p);
            for i = 1:numel(names)
                port = p.(names{i});
                if ~isa(port, 'metools.Port')
                    error('Step:BadPorts', '%s: field "%s" returned by ports() is not a Port.', obj.Name, names{i});
                end
                if ~isempty(port.Follows)
                    if ~isfield(p, port.Follows) || ~strcmp(p.(port.Follows).Direction, 'in')
                        error('Step:BadPorts', '%s: port "%s" has Follows="%s", but no such input port exists.', ...
                            obj.Name, names{i}, port.Follows);
                    end
                end
            end
        end

        function names = parameterNames(obj)
            % Public settable properties defined by the subclass (= parameters of the step).
            pl = metaclass(obj).PropertyList;
            names = {};
            for i = 1:numel(pl)
                p = pl(i);
                if ~strcmp(p.DefiningClass.Name, 'metools.Step') && ~p.Constant && ~p.Dependent && ~p.Hidden ...
                        && ischar(p.SetAccess) && strcmp(p.SetAccess, 'public')
                    names{end+1} = p.Name; %#ok<AGROW>
                end
            end
        end

        function s = paramString(obj)
            % Parameters, port overrides and Keep as a short text for describe().
            parts = {};
            names = obj.parameterNames();
            for i = 1:numel(names)
                parts{end+1} = sprintf('%s=%s', names{i}, metools.Step.formatValue(obj.(names{i}))); %#ok<AGROW>
            end
            b = fieldnames(obj.Bindings);
            for i = 1:numel(b)
                parts{end+1} = sprintf('%s=>%s', b{i}, obj.Bindings.(b{i})); %#ok<AGROW>
            end
            if ~isempty(obj.Keep)
                parts{end+1} = ['Keep=' metools.Step.formatValue(obj.Keep)];
            end
            s = strjoin(parts, ', ');
        end
    end

    methods (Static)
        function out = addPrefix(files, prefix)
            % Prepends a prefix to the name of every file (the folder stays the same).
            % Same as metools.util.addPrefix; kept here for convenience in predict().
            out = metools.util.addPrefix(files, prefix);
        end

        function names = toNameList(value)
            % Normalizes char, string or cellstr to a row cellstr of stream names.
            if isempty(value)
                names = {};
                return
            end
            if ischar(value)
                names = {value};
            elseif isstring(value)
                names = cellstr(value(:)');
            elseif iscellstr(value) %#ok<ISCLSTR>
                names = value(:)';
            else
                error('Step:BadKeep', 'Keep must be a stream name or a list of stream names.');
            end
            for i = 1:numel(names)
                if ~isvarname(names{i})
                    error('Step:BadKeep', 'Invalid stream name "%s" in Keep.', names{i});
                end
            end
            names = unique(names, 'stable');
        end

        function s = formatValue(v)
            if ischar(v)
                s = v;
            elseif isstring(v)
                s = strjoin(cellstr(v(:)'), ',');
            elseif islogical(v) && isscalar(v)
                if v, s = 'true'; else, s = 'false'; end
            elseif isnumeric(v)
                if isempty(v)
                    s = '[]';
                elseif isscalar(v)
                    s = sprintf('%g', v);
                else
                    s = ['[' strtrim(sprintf('%g ', v)) ']'];
                end
            elseif iscell(v)
                s = ['{' strjoin(cellfun(@metools.Step.formatValue, v(:)', 'UniformOutput', false), ',') '}'];
            else
                s = ['<' class(v) '>'];
            end
        end
    end
end
