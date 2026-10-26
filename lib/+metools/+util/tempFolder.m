function [folder, cleanup] = tempFolder()
    % TEMPFOLDER  Creates a new empty temporary folder; it is deleted with all its content
    % when the returned cleanup object is cleared (e.g. when the calling function ends).
    %
    %   [work, cleanup] = metools.util.tempFolder();
    folder = tempname;
    mkdir(folder);
    cleanup = onCleanup(@() removeFolder(folder));
end

function removeFolder(folder)
    if exist(folder, 'dir') == 7
        rmdir(folder, 's');
    end
end
