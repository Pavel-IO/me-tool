function vols = volumeList(file)
    % VOLUMELIST  SPM-style list of all volumes of a 4D file: {'f.nii,1'; 'f.nii,2'; ...}.
    % Returns a column cell array (as SPM batches expect). Needs SPM.
    arguments
        file {mustBeTextScalar}
    end
    file = char(file);
    n = metools.util.scanCount(file);
    vols = cell(n, 1);
    for i = 1:n
        vols{i} = [file ',' num2str(i)];
    end
end
