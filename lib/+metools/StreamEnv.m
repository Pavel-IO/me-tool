classdef StreamEnv < handle
    % STREAMENV  Environment of streams (bold, bold_mean, bold_smooth, ...) and their versions.
    %
    % Every write creates a new, immutable version: a struct with the id, stream name,
    % producing port, index of the producing step, file paths, parents (versions the step
    % read), ancestors (all versions it derives from) and a signature string. A stream
    % name always points to its latest version; readers obtain it with current(). The
    % history only serves debugging, dependency analysis and deletion of files.
    %
    % Versions of the pipeline inputs have step = 0.

    properties (SetAccess = private)
        Versions = struct('id', {}, 'stream', {}, 'port', {}, 'step', {}, ...
                          'files', {}, 'parents', {}, 'ancestors', {}, 'sig', {})
        Current = struct()    % stream name -> id of the latest version
    end

    methods
        function id = add(obj, stream, files, port, stepIdx, parents, sig)
            % Adds a new version of a stream and returns its id.
            if nargin < 7
                sig = '';
            end
            if ~isvarname(stream)
                error('StreamEnv:BadStream', 'Invalid stream name "%s".', stream);
            end
            files = metools.StreamEnv.toFiles(files);
            id = numel(obj.Versions) + 1;
            anc = parents;
            for i = 1:numel(parents)
                anc = [anc, obj.Versions(parents(i)).ancestors]; %#ok<AGROW>
            end
            ver = struct();
            ver.id = id;
            ver.stream = stream;
            ver.port = port;
            ver.step = stepIdx;
            ver.files = files;
            ver.parents = parents;
            ver.ancestors = unique(anc);
            ver.sig = sig;
            obj.Versions(id) = ver;
            obj.Current.(stream) = id;
        end

        function tf = has(obj, stream)
            tf = isfield(obj.Current, stream);
        end

        function v = current(obj, stream)
            % Latest version of a stream (struct).
            if ~obj.has(stream)
                error('StreamEnv:Missing', 'Stream "%s" does not exist.', stream);
            end
            v = obj.Versions(obj.Current.(stream));
        end

        function h = history(obj, stream)
            % All versions of a stream in order of creation (struct array).
            if isempty(obj.Versions)
                h = obj.Versions;
                return
            end
            h = obj.Versions(strcmp({obj.Versions.stream}, stream));
        end

        function names = streams(obj)
            names = fieldnames(obj.Current);
        end

        function cp = clone(obj)
            cp = metools.StreamEnv();
            cp.Versions = obj.Versions;
            cp.Current = obj.Current;
        end
    end

    methods (Static)
        function files = toFiles(x)
            % Normalizes char, string or cellstr input to a row cellstr.
            if ischar(x)
                if isempty(x)
                    files = {};
                else
                    files = {x};
                end
            elseif isstring(x)
                files = cellstr(x(:)');
            elseif iscellstr(x) %#ok<ISCLSTR>
                files = x(:)';
            else
                error('StreamEnv:BadFiles', 'Files must be text or a list of text (cellstr / string array).');
            end
            files = reshape(files, 1, []);
        end
    end
end
