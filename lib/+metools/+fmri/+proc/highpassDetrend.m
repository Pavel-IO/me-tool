function y = highpassDetrend(signal, tr, options)
    % HIGHPASSDETREND  Removes the mean and slow drifts: linear detrend + SPM high-pass
    % filter (DCT, cut-off 128 s). signal: scans x columns.
    arguments
        signal {mustBeNumeric}
        tr (1,1) double {mustBePositive}
        options.Cutoff (1,1) double {mustBePositive} = 128
    end
    K.RT = tr;
    K.row = 1:size(signal, 1);
    K.HParam = options.Cutoff;
    K = spm_filter(K);
    y = spm_detrend(signal, 1);
    y = spm_filter(K, y);
end
