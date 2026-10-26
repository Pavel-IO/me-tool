function resliceToResolution(inFile, outFile, voxelSize)
    % RESLICETORESOLUTION  Reslices an image to the given voxel size (mm), e.g. [1 1 1].
    % Uses reslice_nii from the NIfTI tools (lib/thirdparty/nifti_tools).
    arguments
        inFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        voxelSize (1,3) double {mustBePositive}
    end
    reslice_nii(char(inFile), char(outFile), voxelSize);
end
