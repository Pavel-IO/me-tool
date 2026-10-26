function regressOut(fmriFile, outFile, X, options)
    % REGRESSOUT  Removes the fit of a design matrix from every voxel of a 4D image.
    %
    %   metools.fmri.proc.regressOut('wbc_bold.nii', 'qwbc_bold.nii', X, Keep = c)
    %
    % For every voxel time course y (least squares, pseudo-inverse):
    %   beta = pinv(X'*X)*X'*y,   y_clean = y - X*beta + X(:,Keep)*beta(Keep)
    % Keep lists the columns whose fit stays in the data (normally the constant column
    % from nuisanceDesign, so that the voxel means are preserved). The output has the
    % header (geometry, data type) of the input. The voxels are processed in blocks
    % of ChunkSize.
    arguments
        fmriFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        X double
        options.Keep (1,:) double {mustBeInteger, mustBePositive} = []
        options.ChunkSize (1,1) double {mustBeInteger, mustBePositive} = 20000
    end
    header = spm_vol(char(fmriFile));
    vol = spm_read_vols(header);
    dims = size(vol);
    if numel(dims) < 4
        dims(4) = 1;
    end
    k = dims(4);
    if size(X, 1) ~= k
        error('regressOut:BadSize', 'regressOut: the design has %d rows, the image %d volumes.', size(X, 1), k);
    end
    if any(options.Keep > size(X, 2))
        error('regressOut:BadKeep', 'regressOut: Keep refers to a column outside the design.');
    end
    invX = pinv(X'*X)*X';
    D = reshape(vol, [], k);
    clear vol
    keep = options.Keep;
    for r = 1:options.ChunkSize:size(D, 1)
        rows = r:min(r + options.ChunkSize - 1, size(D, 1));
        Y = D(rows, :)';
        B = invX*Y;
        Yc = Y - X*B;
        if ~isempty(keep)
            Yc = Yc + X(:, keep)*B(keep, :);
        end
        D(rows, :) = Yc';
    end
    metools.util.writeVol4d(header, reshape(D, dims), outFile);
end
