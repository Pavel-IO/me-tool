function n = scanCount(file)
    % SCANCOUNT  Number of volumes in a (3D or 4D) NIfTI file. Needs SPM.
    arguments
        file {mustBeTextScalar}
    end
    n = size(spm_vol(char(file)), 1);
end
