function combineEchoesTsnr(echoFiles, echoTimes, outFile)
    % COMBINEECHOESTSNR  tSNR-weighted combination of multi-echo 4D series into one series.
    %
    %   metools.fmri.proc.combineEchoesTsnr({'e1.nii','e2.nii','e3.nii'}, [15 36 58], 'c_bold.nii')
    %
    %   echoFiles   4D files, one per echo (same geometry and number of volumes)
    %   echoTimes   echo times in ms, one per file
    %   outFile     combined 4D file (header and data type of the first echo)
    %
    % For every voxel v and echo e the weight is w_e(v) = tSNR_e(v) * TE_e, where
    % tSNR_e(v) is the temporal mean divided by the temporal standard deviation of the
    % voxel's time course in echo e (NaNs ignored). The combined series is
    % S(v,t) = sum_e w_e(v) S_e(v,t) / sum_e w_e(v).
    %
    % Port of combineEchoes (lab library, tSNR variant) - results identical.
    arguments
        echoFiles {mustBeText}
        echoTimes (1,:) double {mustBePositive}
        outFile {mustBeTextScalar}
    end
    echoes = reshape(cellstr(echoFiles), 1, []);
    nEchoes = numel(echoes);
    if nEchoes ~= numel(echoTimes)
        error('combineEchoesTsnr:Mismatch', '%d echo files but %d echo times.', nEchoes, numel(echoTimes));
    end

    data = cell(1, nEchoes);
    for e = 1:nEchoes
        echoHead = spm_vol(echoes{e});
        data{e} = spm_read_vols(echoHead);
    end
    nscans = size(data{1}, 4);
    dim = echoHead(1).dim;
    nvox = dim(1)*dim(2)*dim(3);
    for e = 1:nEchoes
        data{e} = reshape(data{e}, [], nscans);
    end

    % voxels are processed in segments (one per slice) to limit memory
    nsegments = dim(3);
    segsize = ceil(nvox / nsegments);
    segments = cell(1, nsegments);
    for seg = 1:nsegments
        segments{seg} = ((seg-1)*segsize)+1:min((seg*segsize), nvox);
    end

    % tSNR of every echo and the sum of the weights
    tsnr = cell(1, nEchoes);
    sumWeights = zeros(nvox, 1);
    for e = 1:nEchoes
        for seg = 1:nsegments
            idx = segments{seg};
            tsnr{e}(idx, 1) = mean(data{e}(idx, :), 2, 'omitnan') ./ std(data{e}(idx, :), 0, 2, 'omitnan');
            sumWeights(idx, 1) = sumWeights(idx, 1) + (tsnr{e}(idx, 1)*echoTimes(e));
        end
    end

    % weighted mean
    combined = zeros(size(data{1}));
    for seg = 1:nsegments
        idx = segments{seg};
        for e = 1:nEchoes
            combined(idx, :) = combined(idx, :) + (data{e}(idx, :) .* repmat(tsnr{e}(idx, 1)*echoTimes(e), [1 nscans]));
        end
        combined(idx, :) = combined(idx, :) ./ repmat(sumWeights(idx, 1), [1 nscans]);
    end
    combined = reshape(combined, dim(1), dim(2), dim(3), nscans);
    metools.util.writeVol4d(spm_vol(echoes{1}), combined, outFile);
end
