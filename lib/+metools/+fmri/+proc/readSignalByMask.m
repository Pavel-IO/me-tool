function Y = readSignalByMask(fmriFile, maskFile)
    % READSIGNALBYMASK  Time courses of the voxels inside a mask (mask value > 0.5).
    % Returns a matrix scans x voxels. The mask must be in the grid of the 4D image.
    arguments
        fmriFile {mustBeTextScalar}
        maskFile {mustBeTextScalar}
    end
    V = spm_read_vols(spm_vol(char(fmriFile)));
    [nx, ny, nz, nscans] = size(V);
    mask = spm_read_vols(spm_vol(char(maskFile)));
    [cx, cy, cz] = ind2sub([nx ny nz], find(mask(:) > 0.5));
    Y = zeros([nscans numel(cx)]);
    for i = 1:numel(cx)
        Y(:, i) = V(cx(i), cy(i), cz(i), :);
    end
end
