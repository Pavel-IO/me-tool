function applyDeformation(deformationFile, files, voxelSize, options)
    % APPLYDEFORMATION  Writes images normalized with an SPM deformation field (y_*.nii).
    %
    %   metools.fmri.proc.applyDeformation('y_r_t1.nii', {'mean.nii'; 'bold.nii,1'; ...}, [2.5 2.5 2.5])
    %
    %   files        volumes to write (SPM notation 'file.nii,k' for 4D volumes; see
    %                metools.util.volumeList)
    %   voxelSize    output voxel size in mm
    %   Prefix       output prefix (default 'w'); outputs are written next to the inputs
    %   BoundingBox  default [-78 -112 -70; 78 76 85]
    %   Interp       interpolation (default 4 = 4th degree B-spline)
    arguments
        deformationFile {mustBeTextScalar}
        files {mustBeText}
        voxelSize (1,3) double {mustBePositive}
        options.Prefix {mustBeTextScalar} = 'w'
        options.BoundingBox (2,3) double = [-78 -112 -70; 78 76 85]
        options.Interp (1,1) double {mustBeInteger, mustBeNonnegative} = 4
    end
    spec.subj.def = {char(deformationFile)};
    spec.subj.resample = reshape(cellstr(files), [], 1);
    spec.woptions.bb = options.BoundingBox;
    spec.woptions.vox = voxelSize;
    spec.woptions.interp = options.Interp;
    spec.woptions.prefix = char(options.Prefix);
    matlabbatch{1}.spm.spatial.normalise.write = spec;
    metools.util.runSpmBatch(matlabbatch);
end
