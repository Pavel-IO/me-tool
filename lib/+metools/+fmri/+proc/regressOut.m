function regressOut(fmriFile, outFile, X, options)
    % REGRESSOUT  Removes the fit of a design matrix from every voxel of a 4D image,
    % optionally with censored scans.
    %
    %   metools.fmri.proc.regressOut('wbc_bold.nii', 'qwbc_bold.nii', X, Keep = c)
    %   metools.fmri.proc.regressOut('wbc_bold.nii', 'qwbc_bold.nii', X, Keep = c, ...
    %       Censored = outliers, LowPass = lp)
    %
    % Without censored scans, for every voxel time course y (least squares, pseudo-inverse):
    %   beta = pinv(X'*X)*X'*y,   y_clean = y - X*beta + X(:,Keep)*beta(Keep)
    % Keep lists the columns whose fit stays in the data (normally the constant column
    % from nuisanceDesign, so that the voxel means are preserved).
    %
    % With censored scans (Censored: logical, one value per scan):
    %   1. A = X without the LowPass columns; beta is estimated from the uncensored scans
    %      only, and y - A*beta + A(:,Keep)*beta(Keep) is computed for all scans,
    %   2. the values of the censored scans are replaced by interpolation in time from
    %      the uncensored ones (Interp: 'pchip' (default), 'linear', 'spline'; censored
    %      scans at the start/end take the nearest uncensored value),
    %   3. the LowPass columns (fast cosines of the filter) are projected out of the whole,
    %      now gap-free series.
    % Without LowPass columns the uncensored scans get exactly the values of a regression
    % with one spike regressor per censored scan; with them, the censored scans do not
    % distort the filtered signal around them (Power et al. 2014).
    %
    % The output has the header (geometry, data type) of the input. The voxels are
    % processed in blocks of ChunkSize.
    arguments
        fmriFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        X double
        options.Keep (1,:) double {mustBeInteger, mustBePositive} = []
        options.Censored logical = false(0, 1)
        options.LowPass (1,:) double {mustBeInteger, mustBePositive} = []
        options.Interp {mustBeMember(options.Interp, {'pchip', 'linear', 'spline'})} = 'pchip'
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
    if any([options.Keep options.LowPass] > size(X, 2))
        error('regressOut:BadColumns', 'regressOut: Keep or LowPass refers to a column outside the design.');
    end
    if any(ismember(options.Keep, options.LowPass))
        error('regressOut:BadColumns', 'regressOut: a column cannot be in Keep and in LowPass.');
    end
    censored = options.Censored(:);
    if isempty(censored)
        censored = false(k, 1);
    elseif numel(censored) ~= k
        error('regressOut:BadCensored', 'regressOut: Censored has %d values, the image %d volumes.', numel(censored), k);
    end

    D = reshape(vol, [], k);
    clear vol
    if any(censored)
        fn = censoredFit(X, options.Keep, censored, options.LowPass, options.Interp);
    else
        fn = plainFit(X, options.Keep);
    end
    for r = 1:options.ChunkSize:size(D, 1)
        rows = r:min(r + options.ChunkSize - 1, size(D, 1));
        D(rows, :) = fn(D(rows, :)')';
    end
    metools.util.writeVol4d(header, reshape(D, dims), outFile);
end

function fn = plainFit(X, keep)
    % Joint regression of all columns on all scans (METools 0.1 behaviour).
    invX = pinv(X'*X)*X';
    fn = @apply;
    function Yc = apply(Y)
        B = invX*Y;
        Yc = Y - X*B;
        if ~isempty(keep)
            Yc = Yc + X(:, keep)*B(keep, :);
        end
    end
end

function fn = censoredFit(X, keep, censored, lowPass, interp)
    % Fit on the uncensored scans, interpolate the censored ones, then the low-pass.
    cols = setdiff(1:size(X, 2), lowPass);
    A = X(:, cols);
    [~, keepA] = ismember(keep, cols);
    u = ~censored;
    if nnz(u) <= rank(A(u, :))
        error('regressOut:TooFewScans', ...
            'regressOut: %d uncensored scans are not enough for %d regressors.', nnz(u), size(A, 2));
    end
    Au = A(u, :);
    invA = pinv(Au'*Au)*Au';
    t = (1:size(X, 1))';
    tu = t(u);
    tc = t(censored);
    inside = tc > tu(1) & tc < tu(end);
    before = tc < tu(1);
    after = tc > tu(end);
    L = X(:, lowPass);
    if ~isempty(L)
        invL = pinv(L'*L)*L';
    end
    fn = @apply;
    function Yc = apply(Y)
        B = invA*Y(u, :);
        Yc = Y - A*B;
        if ~isempty(keepA)
            Yc = Yc + A(:, keepA)*B(keepA, :);
        end
        Yu = Yc(u, :);
        if any(inside)
            Yc(tc(inside), :) = interp1(tu, Yu, tc(inside), interp);
        end
        Yc(tc(before), :) = repmat(Yu(1, :), nnz(before), 1);
        Yc(tc(after), :) = repmat(Yu(end, :), nnz(after), 1);
        if ~isempty(L)
            Yc = Yc - L*(invL*Yc);
        end
    end
end
