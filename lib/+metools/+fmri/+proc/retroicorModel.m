function [corrected, pEcg, pResp] = retroicorModel(data, tr, markers, sliceTiming, options)
    % RETROICORMODEL  RETROICOR correction of cardiac and respiratory noise (in memory).
    %
    %   corrected = metools.fmri.proc.retroicorModel(data, tr, markers, sliceTiming)
    %   [corrected, pEcg, pResp] = ...(..., ComputeStats = true)
    %
    %   data         4D array (x, y, slice, time)
    %   tr           repetition time in s
    %   markers      struct with ECG, resp and r128 times in s (see readMarkers)
    %   sliceTiming  acquisition time of every slice in s (multiband: repeated values)
    %
    % Every slice gets its own regressors: 4 cosine and 4 sine terms of the cardiac and of
    % the respiratory phase at the acquisition time of the slice. They are fitted together
    % with a DCT high-pass basis (cut-off 128 s) and the physiological part is subtracted;
    % the low-frequency part is kept in the data. With ComputeStats the voxelwise
    % p-values of the cardiac and respiratory terms (F-test) are returned as well.
    %
    % Port of RETROICOR_V11MB (multiband version) from the lab library; the results are
    % identical.
    arguments
        data {mustBeNumeric}
        tr (1,1) double {mustBePositive}
        markers struct
        sliceTiming {mustBeNumeric, mustBeVector}
        options.ComputeStats (1,1) logical = false
    end

    tR_EKG = markers.ECG(:);
    tP_breath = markers.resp(:);
    R128 = markers.r128(:);

    % extend the cardiac and respiratory events to cover the whole acquisition
    while R128(1) < tR_EKG(1)
        tR_EKG = [2*tR_EKG(1)-tR_EKG(2); tR_EKG];
    end
    while (R128(end)+tr) > tR_EKG(end)
        tR_EKG = [tR_EKG; 2*tR_EKG(end)-tR_EKG(end-1)]; %#ok<AGROW>
    end
    while R128(1) < tP_breath(1)
        tP_breath = [2*tP_breath(1)-tP_breath(2); tP_breath];
    end
    while (R128(end)+tr) > tP_breath(end)
        tP_breath = [tP_breath; 2*tP_breath(end)-tP_breath(end-1)]; %#ok<AGROW>
    end

    % times relative to the first scan
    tR_EKG = tR_EKG - R128(1);
    tP_breath = tP_breath - R128(1);
    R128 = R128 - R128(1); %#ok<NASGU>

    dTR_EKG = diff(tR_EKG);
    dTP_breath = diff(tP_breath);

    % Fourier basis of the phase (cos and sin, 4 harmonics), sampled at 1000 points
    bazi = 4;
    zset = zeros(1000, bazi*2);
    for i = 1:bazi
        zset(:, i) = cos(2*pi*0.5*i*(0:999)/1000) - mean(cos(2*pi*0.5*i*(0:999)/1000));
        zset(:, i+bazi) = sin(2*pi*0.5*i*(0:999)/1000) - mean(sin(2*pi*0.5*i*(0:999)/1000));
    end

    [y, x, z, t] = size(data);
    reg = zeros(t, bazi*2*2, z);

    ind = 1;
    ind2 = 1;
    tsl = sort(unique(sliceTiming));
    zs = cell(1, length(tsl));
    for ii = 1:length(tsl)
        zs{ii} = find(sliceTiming == tsl(ii));
    end

    for i = 1:t
        for ii = 1:length(tsl)
            time = (i-1)*tr + tsl(ii);
            while tR_EKG(ind+1) <= time
                ind = ind + 1;
            end
            while tP_breath(ind2+1) <= time
                ind2 = ind2 + 1;
            end
            for izi = 1:length(zs{ii})
                zi = zs{ii}(izi);
                reg(i, 1:bazi*2, zi) = zset(floor((time-tR_EKG(ind))/dTR_EKG(ind)*1000+1), :);
                reg(i, (bazi*2+1):bazi*2*2, zi) = zset(floor((time-tP_breath(ind2))/dTP_breath(ind2)*1000+1), :);
            end
        end
    end

    % drift model (DCT, cut-off 128 s)
    HParam = 128;
    k = t;
    n = fix(2*(k*tr)/HParam + 1);
    X0 = spm_dctmtx(k, n);

    for zi = 1:z
        for r = 1:2*2*bazi
            reg(:, r, zi) = reg(:, r, zi) - mean(reg(:, r, zi), 1);
        end
    end

    dfB = t - n - bazi*2;
    dfF = t - n - bazi*2*2;
    F_EKG = zeros(y, x, z);
    F_breath = zeros(y, x, z);

    corrected = zeros(y, x, z, t);
    physio = (n+1):(bazi*4+n);
    for zi = 1:z
        X = [X0, reg(:, :, zi)];
        invXTetc = inv(X'*X)*X'; %#ok<MINV>
        lX = size(X, 2);
        for yi = 1:y
            for xi = 1:x
                yy = squeeze(data(yi, xi, zi, :));
                betas = invXTetc*yy;
                % only the physiological terms are removed (low frequencies are kept)
                corrected(yi, xi, zi, :) = yy - X(:, physio)*betas(physio);

                if options.ComputeStats
                    keepB = [1:n n+(2*bazi+1):lX];
                    ssrB_EKGonly = sum((yy - X(:, keepB)*betas(keepB)).^2);
                    keepR = [1:n n+(1:2*bazi)];
                    ssrB_breathonly = sum((yy - X(:, keepR)*betas(keepR)).^2);
                    ssrF = sum((yy - X*betas).^2);
                    F_EKG(yi, xi, zi) = ((ssrB_EKGonly-ssrF)/(dfB-dfF))/(ssrF/dfF);
                    F_breath(yi, xi, zi) = ((ssrB_breathonly-ssrF)/(dfB-dfF))/(ssrF/dfF);
                end
            end
        end
    end

    pEcg = [];
    pResp = [];
    if options.ComputeStats
        F_EKG(isnan(F_EKG)) = 0;
        F_EKG(F_EKG < 0) = 0;
        F_breath(isnan(F_breath)) = 0;
        F_breath(F_breath < 0) = 0;
        pEcg = 1 - fcdf3(F_EKG, dfB-dfF, dfF);
        pResp = 1 - fcdf3(F_breath, dfB-dfF, dfF);
    end
end
