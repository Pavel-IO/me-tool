function [X, names, constantColumn] = nuisanceDesign(regressors, regressorNames, tr, options)
    % NUISANCEDESIGN  Design matrix of a nuisance regression with a band-pass filter.
    %
    %   [X, names, c] = metools.fmri.proc.nuisanceDesign(R, names, 0.851, ...
    %       Band = [0.008 0.09], Spikes = outliers)
    %
    %   regressors      scans x k nuisance regressors (motion, FD, tissue signals, ...)
    %   regressorNames  their names (cellstr, k names; empty = reg01, reg02, ...)
    %   Band            pass band in Hz (see dctFilterBasis), default [1/128 Inf]
    %   Spikes          logical scans x 1, true = censored scan (one spike regressor each)
    %
    %   X = [ R~, S, X0 ]
    %     R~  the regressors filtered by the same band-pass (X0 projected out), so that the
    %         data and the regressors contain the same frequencies (Hallquist et al. 2013)
    %     S   one column per censored scan: 1 in that scan, 0 elsewhere (not filtered);
    %         names motion_outlier01, ...
    %     X0  the DCT filter basis (dctFilterBasis); its first column is the constant
    %   constantColumn  index of the constant column in X (its fit is kept by regressOut)
    arguments
        regressors double
        regressorNames = {}
        tr (1,1) double {mustBePositive} = 1
        options.Band (1,2) double {mustBeNonnegative} = [1/128 Inf]
        options.Spikes (:,1) logical = false(0, 1)
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
    spikes = options.Spikes;
    if isempty(spikes)
        spikes = false(n, 1);
    elseif numel(spikes) ~= n
        error('nuisanceDesign:BadSpikes', 'nuisanceDesign: Spikes has %d values, the regressors %d scans.', ...
            numel(spikes), n);
    end

    [X0, filterNames] = metools.fmri.proc.dctFilterBasis(n, tr, options.Band);
    P = pinv(X0'*X0)*X0';
    F = regressors - X0*(P*regressors);

    idx = find(spikes);
    S = zeros(n, numel(idx));
    S(sub2ind(size(S), idx(:)', 1:numel(idx))) = 1;
    spikeNames = arrayfun(@(i) sprintf('motion_outlier%02d', i), 1:numel(idx), 'UniformOutput', false);

    X = [F S X0];
    names = [regressorNames(:)' spikeNames filterNames];
    constantColumn = k + numel(idx) + 1;
end
