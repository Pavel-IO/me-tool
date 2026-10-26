function X = nuisanceRegression(fmriFile, outFile, motion, signals, tr, options)
    % NUISANCEREGRESSION  The nuisance regression of the original Cosmic2 pipeline: motion,
    % framewise displacement and region signals are regressed out of every voxel of a 4D
    % image; the mean of every voxel is kept.
    %
    %   R = metools.fmri.proc.motionRegressors24('rp_bold.txt');
    %   X = metools.fmri.proc.nuisanceRegression('swbc_bold.nii', 'qswbc_bold.nii', R, [wm csf], 0.851)
    %
    %   motion    scans x k motion regressors (first 6 columns = realignment parameters)
    %   signals   scans x m region signals (e.g. WM, CSF)
    %   outFile   cleaned 4D image (header of fmriFile)
    %   X         design matrix: [motion, FD, signals, DCT basis]; all regressors are
    %             high-pass filtered (DCT, cut-off 128 s) first
    %
    % FD is computed from the filtered first 6 motion columns after a linear detrend and
    % WITHOUT converting rotations to mm (as bramila_framewiseDisplacement does for SPM).
    % Port of clearFmriData from the lab library. Since METools 0.2 it is composed of
    % dctFilterBasis, framewiseDisplacement, nuisanceDesign and regressOut; the step
    % NuisanceSignalRegression reproduces it with MotionModel=24, FdMethod='legacy',
    % FdRegressor=true, TissueSignals='mean', Band=[1/128 Inf], ScrubFd=[].
    arguments
        fmriFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        motion {mustBeNumeric}
        signals {mustBeNumeric}
        tr (1,1) double {mustBePositive}
        options.Cutoff (1,1) double {mustBePositive} = 128
    end
    k = metools.util.scanCount(fmriFile);
    band = [1/options.Cutoff Inf];
    motion = motion(1:k, :);
    signals = signals(1:k, :);

    X0 = metools.fmri.proc.dctFilterBasis(k, tr, band);
    mf = motion - X0*(pinv(X0'*X0)*X0'*motion);
    fd = metools.fmri.proc.framewiseDisplacement(mf(:, 1:6), RotationUnits = 'none', Detrend = true);

    [X, ~, c] = metools.fmri.proc.nuisanceDesign([motion fd signals], {}, tr, Band = band);
    metools.fmri.proc.regressOut(fmriFile, outFile, X, Keep = c);
end
