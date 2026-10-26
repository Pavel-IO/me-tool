function retroicor(boldFile, outFile, markers, sliceTiming, tr, options)
    % RETROICOR  RETROICOR correction of a 4D file (see retroicorModel).
    %
    %   markers = metools.fmri.proc.readMarkers('markers.csv');
    %   st = metools.fmri.proc.readSliceTiming('acq_params.json');
    %   metools.fmri.proc.retroicor('bold.nii', 'bbold.nii', markers, st, 0.851)
    %   metools.fmri.proc.retroicor(..., FigureFile = 'retroicor.png')   % control figure
    %
    % The number of scan markers (r128) must equal the number of volumes.
    arguments
        boldFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        markers struct
        sliceTiming {mustBeNumeric, mustBeVector}
        tr (1,1) double {mustBePositive}
        options.FigureFile {mustBeTextScalar} = ''
    end
    header = spm_vol(char(boldFile));
    data = spm_read_vols(header);
    if numel(markers.r128) ~= size(header, 1)
        error('retroicor:MarkerCount', ['%s: the number of r128 markers (%d) does not match ' ...
            'the number of scans (%d).'], char(boldFile), numel(markers.r128), size(header, 1));
    end
    withFigure = strlength(options.FigureFile) > 0;
    [corrected, pEcg, pResp] = metools.fmri.proc.retroicorModel(data, tr, markers, sliceTiming, ...
        ComputeStats = withFigure);
    if withFigure
        metools.util.ensureFolder(fileparts(char(options.FigureFile)));
        retroicorFigure(data, pEcg, pResp, char(options.FigureFile));
    end
    metools.util.writeVol4d(header, corrected, outFile);
end
