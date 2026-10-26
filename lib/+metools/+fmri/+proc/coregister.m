function resliced = coregister(refFile, sourceFile, otherFiles, options)
    % COREGISTER  Rigid coregistration of sourceFile to refFile (SPM, normalised mutual
    % information), applied also to otherFiles; writes resliced copies.
    %
    %   resliced = metools.fmri.proc.coregister(refFile, sourceFile, otherFiles)
    %
    % SPM also stores the estimated transformation in the headers of sourceFile and
    % otherFiles. The resliced copies are <Prefix><name> next to them (Prefix 'r');
    % resliced lists them: {source, others...}.
    arguments
        refFile {mustBeTextScalar}
        sourceFile {mustBeTextScalar}
        otherFiles {mustBeText} = {}
        options.Prefix {mustBeTextScalar} = 'r'
    end
    others = reshape(cellstr(otherFiles), [], 1);
    spec.ref = {char(refFile)};
    spec.source = {char(sourceFile)};
    if isempty(others)
        spec.other = {''};
    else
        spec.other = others;
    end
    spec.eoptions.cost_fun = 'nmi';
    spec.eoptions.sep = [8 4 2 1];
    spec.eoptions.tol = [0.02 0.02 0.02 0.001 0.001 0.001 0.01 0.01 0.01 0.001 0.001 0.001];
    spec.eoptions.fwhm = [5 5];
    spec.roptions.interp = 4;
    spec.roptions.wrap = [0 0 0];
    spec.roptions.mask = 0;
    spec.roptions.prefix = char(options.Prefix);
    matlabbatch{1}.spm.spatial.coreg.estwrite = spec;
    metools.util.runSpmBatch(matlabbatch);
    resliced = metools.util.addPrefix([{char(sourceFile)}; others], char(options.Prefix));
end
