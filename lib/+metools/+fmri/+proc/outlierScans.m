function out = outlierScans(fd, threshold, options)
    % OUTLIERSCANS  Scans to censor: framewise displacement above a threshold, optionally
    % together with neighbouring scans (Power et al. 2012 used 1 before and 2 after).
    %
    %   out = metools.fmri.proc.outlierScans(fd, 0.5, Before = 1, After = 2)
    %
    % Returns a logical column vector (true = censored scan).
    arguments
        fd (:,1) double
        threshold (1,1) double {mustBePositive}
        options.Before (1,1) double {mustBeInteger, mustBeNonnegative} = 0
        options.After (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    end
    bad = find(fd > threshold);
    out = false(numel(fd), 1);
    for i = bad'
        out(max(1, i - options.Before):min(numel(fd), i + options.After)) = true;
    end
end
