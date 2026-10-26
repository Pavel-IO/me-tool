function M = connectivityMatrix(ts, options)
    % CONNECTIVITYMATRIX  Functional connectivity (Pearson correlation) between the columns
    % of a time-course matrix.
    %
    %   M = metools.fmri.proc.connectivityMatrix(ts)                      % r
    %   M = metools.fmri.proc.connectivityMatrix(ts, Measure = 'fisherz') % atanh(r)
    %
    % ts: scans x ROIs. Columns that are not finite or constant give NaN rows and columns;
    % the diagonal is NaN. Returns ROIs x ROIs.
    arguments
        ts double
        options.Measure {mustBeMember(options.Measure, {'pearsonr', 'fisherz'})} = 'pearsonr'
    end
    n = size(ts, 2);
    M = NaN(n);
    ok = all(isfinite(ts), 1) & std(ts, 0, 1) > 0;
    if size(ts, 1) < 3 || ~any(ok)
        return
    end
    X = ts(:, ok);
    X = (X - mean(X, 1)) ./ std(X, 0, 1);
    C = (X' * X) / (size(X, 1) - 1);
    M(ok, ok) = max(min(C, 1), -1);
    M(1:n+1:end) = NaN;
    if strcmp(options.Measure, 'fisherz')
        M = atanh(M);
    end
end
