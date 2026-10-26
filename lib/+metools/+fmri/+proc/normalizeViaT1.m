function normalizeViaT1(t1File, meanFile, boldFile, t1CoregFile, options)
    % NORMALIZEVIAT1  Normalization of a BOLD series to MNI space through the subject's T1.
    %
    %   metools.fmri.proc.normalizeViaT1('anat/_t1.nii', 'rest/mean_echo_2.nii', ...
    %       'rest/bc_bold.nii', 'rest/r_t1.nii')
    %
    %   1. the T1 is skull-stripped (CAT12) so that it resembles the BOLD data
    %   2. the mean image is resliced to CoregResolution and the stripped T1 is coregistered
    %      to it; the full T1 follows and is written as t1CoregFile
    %   3. t1CoregFile is segmented (SPM12) and the deformation is applied to the mean
    %      image and to every volume of the BOLD series
    %
    % Outputs: w<name> next to meanFile and boldFile, t1CoregFile. All intermediate files
    % live in a temporary folder that is removed at the end.
    %
    %   VoxelSize        output voxel size in mm (default [2.5 2.5 2.5])
    %   CoregResolution  resolution of the resliced mean for coregistration (default [1 1 1])
    arguments
        t1File {mustBeTextScalar}
        meanFile {mustBeTextScalar}
        boldFile {mustBeTextScalar}
        t1CoregFile {mustBeTextScalar}
        options.VoxelSize (1,3) double {mustBePositive} = [2.5 2.5 2.5]
        options.CoregResolution (1,3) double {mustBePositive} = [1 1 1]
    end
    t1File = char(t1File);
    meanFile = char(meanFile);
    boldFile = char(boldFile);
    [work, cleanup] = metools.util.tempFolder(); %#ok<ASGLU>

    [~, t1Name, t1Ext] = fileparts(t1File);
    t1Copy = fullfile(work, [t1Name t1Ext]);          % coregistration changes its header
    copyfile(t1File, t1Copy);
    stripped = fullfile(work, ['strip' t1Name t1Ext]);
    metools.fmri.proc.skullStripCat12(t1File, stripped);

    [~, meanName, meanExt] = fileparts(meanFile);
    meanResliced = fullfile(work, ['rsl_' meanName meanExt]);
    metools.fmri.proc.resliceToResolution(meanFile, meanResliced, options.CoregResolution);

    resliced = metools.fmri.proc.coregister(meanResliced, stripped, {t1Copy});
    t1Coreg = resliced{2};                             % r<T1 name> in the work folder

    deformation = metools.fmri.proc.segmentDeformation(t1Coreg);
    files = [{meanFile}; metools.util.volumeList(boldFile)];
    metools.fmri.proc.applyDeformation(deformation, files, options.VoxelSize, Prefix = 'w');

    movefile(t1Coreg, char(t1CoregFile), 'f');
end
