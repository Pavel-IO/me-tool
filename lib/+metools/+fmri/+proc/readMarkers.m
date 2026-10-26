function markers = readMarkers(file, options)
    % READMARKERS  Physiological markers (BrainVision marker export) for RETROICOR.
    %
    %   markers = metools.fmri.proc.readMarkers('markers.csv')
    %
    % Returns a struct with times in seconds relative to the first scan (R128) marker:
    %   ECG    R-peaks of the ECG       resp   respiration markers (Resp, B, O)
    %   r128   scan markers             debug_ECG_lines   line numbers of the used R-peaks
    % ECG and respiration markers are limited to [0, last scan + 5 s).
    % Verbose = true prints the number of markers.
    arguments
        file {mustBeTextScalar}
        options.Verbose (1,1) logical = false
    end
    file = char(file);
    if ~exist(file, 'file')
        error('readMarkers:NotFound', 'Markers file was not found in "%s"', file);
    end

    fileID = fopen(file);
    lines = textscan(fileID, '%[^\n]');
    fclose(fileID);

    ecg = [];
    ecgLines = [];
    resp = [];
    r128 = [];

    % sampling interval from the header line, e.g. "... Sampling interval: 2ms"
    samplingComment = strjoin(lines{1}(1));
    samplingWords = strsplit(samplingComment);
    samplingWord = samplingWords{5};
    assert(contains(samplingWord, 'ms'));
    sampling = str2num(strrep(samplingWord, 'ms', '')) / 1000; %#ok<ST2NM>

    for i = 3:numel(lines{1})
        line = strjoin(lines{1}(i));
        parts = strsplit(line, ', ');
        marker = strjoin(parts(2));
        time = str2num(strjoin(parts(3))); %#ok<ST2NM>
        switch marker
            case 'R'
                ecg = [ecg time]; %#ok<AGROW>
                ecgLines = [ecgLines i]; %#ok<AGROW>
            case {'Resp', 'B', 'O'}
                resp = [resp time]; %#ok<AGROW>
            case 'R128'
                r128 = [r128 time]; %#ok<AGROW>
            case {'Sync On', 'TSTART', 'TPEAK', 'TEND'}
                % ignored
            otherwise
                error('readMarkers:UnknownMarker', 'Unknown marker "%s".', marker);
        end
    end

    ecg = ecg - r128(1);
    resp = resp - r128(1);
    r128 = r128 - r128(1);

    ecg = ecg * sampling;       % seconds
    resp = resp * sampling;
    r128 = r128 * sampling;

    ecgRaw = ecg;
    ecg = ecg(ecg >= 0 & ecg < (r128(end) + 5));      % between the scans
    resp = resp(resp >= 0 & resp < (r128(end) + 5));

    skipped = ecgRaw(ecgRaw < 0);
    nn = numel(skipped);
    ecgLines = ecgLines(nn+1:nn+numel(ecg));

    if options.Verbose
        disp(['Elfyz: ' file]);
        disp(['EKG count: ' num2str(numel(ecg))]);
        disp(['Resp count: ' num2str(numel(resp))]);
        disp(['R128 count: ' num2str(numel(r128))]);
    end

    markers = struct();
    markers.ECG = ecg;
    markers.resp = resp;
    markers.r128 = r128;
    markers.debug_ECG_lines = ecgLines;
end
