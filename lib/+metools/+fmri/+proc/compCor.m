function [comps, explained] = compCor(fmriFile, refFile, maskFile, tr, k, options)
    % COMPCOR  Anatomical CompCor: principal components of the signals in a noise region
    % (white matter or CSF) of a 4D image (Behzadi et al. 2007).
    %
    %   [c, e] = metools.fmri.proc.compCor('wbc_bold.nii', 'wmean.nii', 'masks/WM09.nii', 0.851, 5)
    %
    % The mask is resampled to the grid of refFile (a 3D image in the space of fmriFile,
    % trilinear interpolation, threshold 0.5). Every voxel time course is linearly detrended
    % and high-pass filtered (highpassDetrend, Cutoff in s, Inf = no filter) and scaled to
    % unit variance; the first k left singular vectors of the scans x voxels matrix are
    % returned (scans x k, unit norm). explained: fraction of the variance of each component.
    arguments
        fmriFile {mustBeTextScalar}
        refFile {mustBeTextScalar}
        maskFile {mustBeTextScalar}
        tr (1,1) double {mustBePositive}
        k (1,1) double {mustBeInteger, mustBePositive}
        options.Cutoff (1,1) double {mustBePositive} = 128
    end
    [work, cleanup] = metools.util.tempFolder(); %#ok<ASGLU>
    mask = fullfile(work, 'mask.nii');
    metools.fmri.proc.resampleLike(refFile, maskFile, mask);
    Y = metools.fmri.proc.readSignalByMask(fmriFile, mask);
    Y = metools.fmri.proc.highpassDetrend(Y, tr, Cutoff = options.Cutoff);
    s = std(Y, 0, 1);
    keep = isfinite(s) & s > 0;
    if ~any(keep)
        error('compCor:EmptyMask', 'compCor: no voxel with a varying signal in the mask %s.', char(maskFile));
    end
    Y = Y(:, keep) ./ s(keep);
    [U, S, ~] = svd(Y, 'econ');
    k = min(k, size(U, 2));
    comps = U(:, 1:k);
    sv = diag(S).^2;
    explained = sv(1:k) / sum(sv);
end
