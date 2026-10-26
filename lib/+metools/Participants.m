classdef Participants < handle
    % PARTICIPANTS  Subjects of a project and the folder layout used to find their data.
    %
    %   P = metools.Participants('g:/Data/Cosmic2', {'sub-01', 'sub-02'});
    %   P.add('sub-03');
    %
    % Expected layout (the folder names are properties and can be changed):
    %
    %   <ProjectDir>/<DataFolder>/<subject>/<session>/    functional data of one session
    %   <ProjectDir>/<DataFolder>/<subject>/<FieldsFolder>/   field maps of the subject
    %   <ProjectDir>/<DataFolder>/<subject>/anat/         anatomical data (used by steps)
    %   <ProjectDir>/<DataFolder>/<subject>/<LogsFolder>/     detailed run logs (when logging is on)
    %   <ProjectDir>/<OutputsFolder>/                     project-level outputs (e.g. QC figures)
    %
    % A unit of work is one subject in one session; Pipeline.runFor processes units.

    properties
        DataFolder = 'data'
        FieldsFolder = 'fields'
        OutputsFolder = 'outputs'
        LogsFolder = 'logs'
    end

    properties (SetAccess = private)
        ProjectDir = ''
        Subjects = {}
    end

    methods
        function obj = Participants(projectDir, subjects)
            if nargin < 1
                projectDir = '';
            end
            if nargin < 2
                subjects = {};
            end
            obj.ProjectDir = metools.Participants.asChar(projectDir);
            obj.add(subjects);
        end

        function add(obj, subjects)
            % Adds one subject id (char/string) or a list of ids (cellstr/string array).
            if ischar(subjects)
                subjects = {subjects};
            elseif isstring(subjects)
                subjects = cellstr(subjects(:)');
            elseif ~iscellstr(subjects) %#ok<ISCLSTR>
                error('Participants:BadSubject', 'Subject ids must be text or a list of text.');
            end
            for i = 1:numel(subjects)
                if isempty(subjects{i})
                    error('Participants:BadSubject', 'Subject ids must be non-empty text.');
                end
                if ~any(strcmp(subjects{i}, obj.Subjects))
                    obj.Subjects{end+1} = subjects{i};
                end
            end
        end

        function d = subjectDir(obj, subject)
            d = fullfile(obj.ProjectDir, obj.DataFolder, subject);
        end

        function d = sessionDir(obj, subject, session)
            d = fullfile(obj.ProjectDir, obj.DataFolder, subject, session);
        end

        function d = fieldsDir(obj, subject)
            d = fullfile(obj.ProjectDir, obj.DataFolder, subject, obj.FieldsFolder);
        end

        function d = logsDir(obj, subject)
            % Folder of the detailed run logs of a subject.
            d = fullfile(obj.ProjectDir, obj.DataFolder, subject, obj.LogsFolder);
        end

        function d = outputsDir(obj)
            d = fullfile(obj.ProjectDir, obj.OutputsFolder);
        end

        function u = units(obj, session)
            % Units of work (struct array with fields Subject and Session) for one session.
            u = repmat(struct('Subject', '', 'Session', session), 1, numel(obj.Subjects));
            for i = 1:numel(obj.Subjects)
                u(i).Subject = obj.Subjects{i};
            end
        end

        function ctx = context(obj, subject, session, cfg)
            % Context handed to steps: identity of the unit, its folders and the configuration.
            if nargin < 4
                cfg = [];
            end
            ctx = struct();
            ctx.Subject = subject;
            ctx.Session = session;
            ctx.ProjectDir = obj.ProjectDir;
            ctx.SubjectDir = obj.subjectDir(subject);
            ctx.SessionDir = obj.sessionDir(subject, session);
            ctx.FieldsDir = obj.fieldsDir(subject);
            ctx.OutputsDir = obj.outputsDir();
            ctx.Cfg = cfg;
            ctx.LogDir = '';        % detailed log folder of this run (set when logging is on)
            ctx.QcDir = '';         % folder for QC figures (set when logging is on)
        end
    end

    methods (Static, Access = private)
        function s = asChar(x)
            if isstring(x) && isscalar(x)
                x = char(x);
            end
            if ~ischar(x)
                error('Participants:BadPath', 'The project folder must be text.');
            end
            s = x;
        end
    end
end
