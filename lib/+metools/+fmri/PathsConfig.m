classdef PathsConfig < matlab.mixin.Copyable
    % PATHSCONFIG  Folders and files shared by the steps of a study.
    %
    %   project   root folder of the project (see Participants for the expected layout)
    %   masks     folder with the WM/CSF masks used by NuisanceSignalRegression
    %
    % Values are stored as char vectors (strings are converted).

    properties
        project = ''
        masks   = ''
    end

    methods
        function set.project(obj, value)
            obj.project = metools.fmri.PathsConfig.asChar(value, 'project');
        end

        function set.masks(obj, value)
            obj.masks = metools.fmri.PathsConfig.asChar(value, 'masks');
        end
    end

    methods (Static, Access = private)
        function s = asChar(value, name)
            if isstring(value) && isscalar(value)
                value = char(value);
            end
            if ~ischar(value) || (~isempty(value) && ~isrow(value))
                error('PathsConfig:BadValue', 'paths.%s must be a text value (a path).', name);
            end
            s = value;
        end
    end
end
