classdef Port
    % PORT  Input or output port of a pipeline step.
    %
    %   metools.Port.input('bold')                         reads stream 'bold' (always its latest version)
    %   metools.Port.input('bold', 'Cardinality', 'one')   exactly 1 file ('any' | 'one' | 'many' = at least 2)
    %   metools.Port.input('rp', 'Optional', true)         the stream does not have to exist
    %   metools.Port.output('bold_smooth')                 writes to stream 'bold_smooth'
    %   metools.Port.output('', 'Follows', 'In')           writes to the stream read by input port 'In'
    %
    % The stream name is only a default; the user can override it per step
    % (e.g. In="bold_smooth"). A port never touches files, it only names streams.

    properties (SetAccess = immutable)
        Direction     % 'in' | 'out'
        Stream        % default stream name (empty when Follows is used)
        Cardinality   % 'any' | 'one' | 'many'
        Optional      % logical
        Follows       % name of the input port whose stream is used (output ports only)
    end

    methods
        function obj = Port(direction, stream, cardinality, optional, follows)
            direction = validatestring(direction, {'in', 'out'});
            cardinality = validatestring(cardinality, {'any', 'one', 'many'});
            stream = metools.Port.toChar(stream, 'Stream');
            follows = metools.Port.toChar(follows, 'Follows');
            if isempty(follows)
                if ~isvarname(stream)
                    error('Port:BadStream', ...
                        'Invalid stream name "%s" (use a variable-like name, e.g. bold_smooth).', stream);
                end
            elseif ~strcmp(direction, 'out')
                error('Port:BadFollows', 'Option Follows can only be used with output ports.');
            end
            obj.Direction = direction;
            obj.Stream = stream;
            obj.Cardinality = cardinality;
            obj.Optional = logical(optional);
            obj.Follows = follows;
        end
    end

    methods (Static)
        function p = input(stream, varargin)
            opt = metools.Port.parse(varargin, struct('Cardinality', 'any', 'Optional', false), 'input');
            p = metools.Port('in', stream, opt.Cardinality, opt.Optional, '');
        end

        function p = output(stream, varargin)
            opt = metools.Port.parse(varargin, struct('Optional', false, 'Follows', ''), 'output');
            p = metools.Port('out', stream, 'any', opt.Optional, opt.Follows);
        end
    end

    methods (Static, Access = private)
        function s = toChar(x, what)
            if isstring(x) && isscalar(x)
                x = char(x);
            end
            if ~ischar(x)
                error('Port:BadArgument', 'Port: %s must be text.', what);
            end
            s = x;
        end

        function opt = parse(args, defaults, kind)
            opt = defaults;
            if mod(numel(args), 2) ~= 0
                error('Port:BadOptions', 'Port.%s: options must be name/value pairs.', kind);
            end
            valid = fieldnames(defaults);
            for i = 1:2:numel(args)
                name = args{i};
                if ~(ischar(name) || (isstring(name) && isscalar(name)))
                    error('Port:BadOptions', 'Port.%s: option names must be text.', kind);
                end
                idx = find(strcmpi(char(name), valid), 1);
                if isempty(idx)
                    error('Port:BadOptions', 'Port.%s: unknown option "%s" (valid: %s).', ...
                        kind, char(name), strjoin(valid', ', '));
                end
                opt.(valid{idx}) = args{i + 1};
            end
        end
    end
end
