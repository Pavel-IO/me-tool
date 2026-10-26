function resampleLike(refFile, srcFile, outFile, options)
    % RESAMPLELIKE  Resamples srcFile into the space (grid) of refFile (SPM imcalc).
    % refFile must be a single 3D volume (a volume of a 4D file can be given as 'f.nii,1').
    %
    %   metools.fmri.proc.resampleLike('wmean.nii', 'WM09.nii', 'mask.nii')
    %   metools.fmri.proc.resampleLike('bold.nii,1', 'atlas.nii', 'labels.nii', ...
    %       Interp = 0, DataType = 'float32')                % labels: nearest neighbour
    %
    %   Interp    interpolation of spm_imcalc: 0 nearest neighbour (label images),
    %             1 trilinear, n > 1 n-th degree sinc; [] (default) = the spm_imcalc
    %             default (as in METools 0.1, so existing results do not change)
    %   DataType  data type of the output, an spm_type name; '' (default) = the spm_imcalc
    %             default (int16, values are scaled). Use 'float32' for exact label values.
    arguments
        refFile {mustBeTextScalar}
        srcFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        options.Interp double {mustBeScalarOrEmpty, mustBeInteger} = []
        options.DataType {mustBeTextScalar} = ''
    end
    refFile = char(refFile);
    assert(metools.util.scanCount(refFile) == 1, 'resampleLike: the reference must be a 3D image.');
    metools.util.ensureFolder(fileparts(char(outFile)));
    Pi = char(refFile, char(srcFile)); %#ok<NASGU>
    rn = char(outFile); %#ok<NASGU>
    if isempty(options.Interp) && strlength(options.DataType) == 0
        evalc('spm_imcalc(Pi, rn, ''i2'')');
        return
    end
    dtype = [];
    if strlength(options.DataType) > 0
        dtype = spm_type(char(options.DataType));
    end
    flags = {[], [], options.Interp, dtype}; %#ok<NASGU>
    evalc('spm_imcalc(Pi, rn, ''i2'', flags)');
end
