function [X, names, constantColumn, lowPassColumns] = nuisanceDesign(regressors, regressorNames, tr, options)
    % NUISANCEDESIGN  Design matrix of a nuisance regression with a band-pass filter.
    %
    %   [X, names, c, lp] = metools.fmri.proc.nuisanceDesign(R, names, 0.851, Band = [0.008 0.09])
    %
    %   regressors      scans x k nuisance regressors (motion, FD, tissue signals, ...)
    %   regressorNames  their names (cellstr, k names; empty = reg01, reg02, ...)
    %   Band            pass band in Hz (see dctFilterBasis), default [1/128 Inf]
    %
    %   X = [ R~, X0 ]
    %     R~  the regressors filtered by the same band-pass (X0 projected out), so that the
    %         data and the regressors contain the same frequencies (Hallquist et al. 2013)
    %     X0  the DCT filter basis (dctFilterBasis): constant, high-pass and low-pass columns
    %   constantColumn  index of the constant column in X (its fit is kept by regressOut)
    %   lowPassColumns  indices of the low-pass columns in X (regressOut applies them after
    %                   the interpolation of censored scans)
    arguments
        regressors double
        regressorNames = {}
        tr (1,1) double {mustBePositive} = 1
        options.Band (1,2) double {mustBeNonnegative} = [1/128 Inf]
    end
    n = size(regressors, 1);
    k = size(regressors, 2);
    regressorNames = cellstr(regressorNames);
    if isempty(regressorNames)
        regressorNames = arrayfun(@(i) sprintf('reg%02d', i), 1:k, 'UniformOutput', false);
    end
    if numel(regressorNames) ~= k
        error('nuisanceDesign:BadNames', 'nuisanceDesign: %d regressors, but %d names.', k, numel(regressorNames));
    end

    [X0, filterNames] = metools.fmri.proc.dctFilterBasis(n, tr, options.Band);
    P = pinv(X0'*X0)*X0';
    F = regressors - X0*(P*regressors);

    X = [F X0];
    names = [regressorNames(:)' filterNames];
    constantColumn = k + 1;
    lowPassColumns = k + find(startsWith(filterNames, 'dct_lp'));
end
