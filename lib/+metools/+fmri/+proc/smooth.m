function smooth(inFile, outFile, fwhm)
    % SMOOTH  Gaussian smoothing of a 3D/4D image (SPM).
    %
    %   metools.fmri.proc.smooth('wbc_bold.nii', 'swbc_bold.nii', 6)
    %
    %   fwhm   FWHM in mm, scalar or [x y z]
    % outFile may equal inFile (smoothing in place).
    arguments
        inFile {mustBeTextScalar}
        outFile {mustBeTextScalar}
        fwhm (1,:) double {mustBePositive}
    end
    inFile = char(inFile);
    outFile = char(outFile);
    if isscalar(fwhm)
        fwhm = [fwhm fwhm fwhm];
    end
    % SPM writes <prefix><name> next to the input; a unique prefix avoids clashes
    [~, token] = fileparts(tempname);
    prefix = [token '_'];
    matlabbatch{1}.spm.spatial.smooth.data = metools.util.volumeList(inFile);
    matlabbatch{1}.spm.spatial.smooth.fwhm = fwhm;
    matlabbatch{1}.spm.spatial.smooth.dtype = 0;
    matlabbatch{1}.spm.spatial.smooth.im = 0;
    matlabbatch{1}.spm.spatial.smooth.prefix = prefix;
    metools.util.runSpmBatch(matlabbatch);
    movefile(metools.util.addPrefix(inFile, prefix), outFile, 'f');
end
