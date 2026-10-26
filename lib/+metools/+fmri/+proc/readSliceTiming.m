function sliceTiming = readSliceTiming(jsonFile)
    % READSLICETIMING  Slice acquisition times (s) from a BIDS-like JSON sidecar
    % (field SliceTiming), e.g. acq_params.json.
    arguments
        jsonFile {mustBeTextScalar}
    end
    data = jsondecode(fileread(char(jsonFile)));
    if ~isfield(data, 'SliceTiming')
        error('readSliceTiming:Missing', 'The file %s has no field SliceTiming.', char(jsonFile));
    end
    sliceTiming = data.SliceTiming;
end
