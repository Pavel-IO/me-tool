function sig = maskSignal(fmriFile, refFile, maskFile, tr, options)
    % MASKSIGNAL  Mean detrended signal of a region (e.g. WM or CSF) in a 4D image.
    %
    %   sig = metools.fmri.proc.maskSignal('wbc_bold.nii', 'wmean.nii', 'masks/WM09.nii', 0.851)
    %
    % The mask is resampled to the grid of refFile (a 3D image in the space of fmriFile),
    % the voxel time courses are detrended (highpassDetrend, cut-off Cutoff s, default 128,
    % Inf = linear detrend only) and averaged.
    % Returns a column vector (one value per scan).
    arguments
        fmriFile {mustBeTextScalar}
        refFile {mustBeTextScalar}
        maskFile {mustBeTextScalar}
        tr (1,1) double {mustBePositive}
        options.Cutoff (1,1) double {mustBePositive} = 128
    end
    [work, cleanup] = metools.util.tempFolder(); %#ok<ASGLU>
    mask = fullfile(work, 'mask.nii');
    metools.fmri.proc.resampleLike(refFile, maskFile, mask);
    signal = metools.fmri.proc.readSignalByMask(fmriFile, mask);
    sig = mean(metools.fmri.proc.highpassDetrend(signal, tr, Cutoff = options.Cutoff), 2);
end
