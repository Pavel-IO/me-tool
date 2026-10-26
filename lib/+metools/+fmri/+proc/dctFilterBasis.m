function [X0, names] = dctFilterBasis(nScans, tr, band)
    % DCTFILTERBASIS  Discrete cosine basis of a temporal band-pass filter.
    %
    %   [X0, names] = metools.fmri.proc.dctFilterBasis(600, 0.851, [0.008 0.09])
    %
    % Column j of the DCT basis (spm_dctmtx) is a cosine with frequency (j-1)/(2*N*TR).
    % X0 contains
    %   - the constant term (always, first column, name 'dct_constant'),
    %   - the slow cosines below band(1) (high-pass part, SPM convention: the first
    %     fix(2*N*TR*band(1) + 1) columns; band(1) = 1/128 Hz is SPM's 128 s cut-off),
    %     names dct_hp01, ...,
    %   - the fast cosines above band(2) (low-pass part), names dct_lp001, ...
    % Regressing X0 out of a signal (keeping the constant) is band-pass filtering.
    % band(1) = 0: no high-pass; band(2) = Inf (or >= Nyquist): no low-pass.
    arguments
        nScans (1,1) double {mustBeInteger, mustBePositive}
        tr (1,1) double {mustBePositive}
        band (1,2) double {mustBeNonnegative} = [1/128 Inf]
    end
    if band(1) >= band(2)
        error('dctFilterBasis:BadBand', 'dctFilterBasis: band(1) must be lower than band(2).');
    end
    nHp = min(nScans, max(1, fix(2*(nScans*tr)*band(1) + 1)));
    first = Inf;
    if isfinite(band(2))
        first = floor(2*(nScans*tr)*band(2)) + 2;   % first column with frequency > band(2)
    end
    if first > nScans
        X0 = spm_dctmtx(nScans, nHp);
        lp = [];
    else
        X0 = spm_dctmtx(nScans, nScans);
        lp = max(first, nHp + 1):nScans;
        X0 = X0(:, [1:nHp, lp]);
    end
    names = [{'dct_constant'}, ...
        arrayfun(@(i) sprintf('dct_hp%02d', i), 1:nHp-1, 'UniformOutput', false), ...
        arrayfun(@(i) sprintf('dct_lp%03d', i), 1:numel(lp), 'UniformOutput', false)];
end
