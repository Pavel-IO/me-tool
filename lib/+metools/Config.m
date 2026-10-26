classdef Config < matlab.mixin.Copyable
    % CONFIG  Base class of study configurations: typed values reachable by a dotted path.
    %
    % A domain configuration (e.g. metools.fmri.FmriConfig) derives from this class and
    % adds its sections as properties holding Copyable objects with typed properties:
    %
    %   cfg = metools.fmri.FmriConfig();
    %   cfg.acq.TR = 0.851;                       % typed: a typo or a bad value is an error
    %   cfg.getValue('acq.TR')                    % access by path (used by config bindings)
    %   cfg.addOverride('video', 'acq.TR', 0.9);  % value used only in session 'video'
    %   cfgVideo = cfg.forSession('video');       % copy with the overrides applied
    %
    % Steps take values from the configuration when the corresponding parameter is left
    % empty (see Step.configBindings). Precedence: explicit step parameter > session
    % override > study value > default of the step class.

    properties (SetAccess = private)
        Overrides = struct('session', {}, 'path', {}, 'value', {})
    end

    methods
        function v = getValue(obj, path)
            % Value at a dotted path, e.g. 'acq.TR'.
            parts = metools.Config.splitPath(path);
            v = obj;
            for i = 1:numel(parts)
                if ~isobject(v) || ~isprop(v, parts{i})
                    error('Config:BadPath', 'Unknown configuration path "%s".', path);
                end
                v = v.(parts{i});
            end
        end

        function setValue(obj, path, value)
            % Sets the value at a dotted path (validated by the typed property).
            parts = metools.Config.splitPath(path);
            target = obj;
            for i = 1:numel(parts) - 1
                if ~isobject(target) || ~isprop(target, parts{i})
                    error('Config:BadPath', 'Unknown configuration path "%s".', path);
                end
                target = target.(parts{i});
            end
            if ~isobject(target) || ~isprop(target, parts{end}) || strcmp(parts{end}, 'Overrides')
                error('Config:BadPath', 'Unknown configuration path "%s".', path);
            end
            target.(parts{end}) = value;
        end

        function addOverride(obj, session, path, value)
            % Value used instead of the study value when running the given session.
            if isstring(session) && isscalar(session)
                session = char(session);
            end
            if ~ischar(session) || isempty(session)
                error('Config:BadSession', 'Session name must be non-empty text.');
            end
            probe = obj.copy();
            probe.setValue(path, value);          % fails early on a typo or an invalid value
            ov = struct();
            ov.session = session;
            ov.path = char(path);
            ov.value = value;
            obj.Overrides(end+1) = ov;
        end

        function cp = forSession(obj, session)
            % Copy of the configuration with the overrides of the session applied.
            cp = obj.copy();
            for i = 1:numel(obj.Overrides)
                if strcmp(obj.Overrides(i).session, session)
                    cp.setValue(obj.Overrides(i).path, obj.Overrides(i).value);
                end
            end
        end

        function lines = describe(obj)
            % All values as 'path = value' lines (used by the logs).
            lines = metools.Config.valueLines(obj, '');
            for i = 1:numel(obj.Overrides)
                ov = obj.Overrides(i);
                lines{end+1} = sprintf('override [%s] %s = %s', ov.session, ov.path, ...
                    metools.Step.formatValue(ov.value)); %#ok<AGROW>
            end
        end
    end

    methods (Access = protected)
        function cp = copyElement(obj)
            % Deep copy: every section (Copyable property) is copied as well.
            cp = copyElement@matlab.mixin.Copyable(obj);
            names = metools.Config.sectionNames(obj);
            for i = 1:numel(names)
                cp.(names{i}) = copy(obj.(names{i}));
            end
        end
    end

    methods (Static, Access = private)
        function parts = splitPath(path)
            parts = strsplit(char(path), '.');
        end

        function names = sectionNames(obj)
            names = {};
            pl = metaclass(obj).PropertyList;
            for i = 1:numel(pl)
                p = pl(i);
                if p.Dependent || p.Constant || ~ischar(p.SetAccess) || ~strcmp(p.SetAccess, 'public')
                    continue
                end
                if isa(obj.(p.Name), 'matlab.mixin.Copyable')
                    names{end+1} = p.Name; %#ok<AGROW>
                end
            end
        end

        function lines = valueLines(obj, prefix)
            lines = {};
            pl = metaclass(obj).PropertyList;
            for i = 1:numel(pl)
                p = pl(i);
                if p.Dependent || p.Constant || p.Hidden || strcmp(p.Name, 'Overrides')
                    continue
                end
                v = obj.(p.Name);
                if isobject(v) && isscalar(v)
                    lines = [lines, metools.Config.valueLines(v, [prefix p.Name '.'])]; %#ok<AGROW>
                else
                    lines{end+1} = sprintf('%s%s = %s', prefix, p.Name, metools.Step.formatValue(v)); %#ok<AGROW>
                end
            end
        end
    end
end
