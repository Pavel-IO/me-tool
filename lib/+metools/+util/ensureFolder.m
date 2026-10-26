function ensureFolder(folder)
    % ENSUREFOLDER  Creates the folder (with parents) if it does not exist.
    arguments
        folder {mustBeTextScalar}
    end
    folder = char(folder);
    if ~isempty(folder) && exist(folder, 'dir') ~= 7
        mkdir(folder);
    end
end
