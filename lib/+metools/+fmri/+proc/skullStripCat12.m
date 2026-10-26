function skullStripCat12(t1File, outFile)
    % SKULLSTRIPCAT12  Brain-only image of a T1 (CAT12 segmentation, label image p0).
    %
    %   metools.fmri.proc.skullStripCat12('anat/_t1.nii', 'strip_t1.nii')
    %
    % CAT12 runs on a copy of the T1 in a temporary folder, so nothing is written next to
    % the original T1; the temporary folder is removed afterwards. Needs SPM12 + CAT12.
    arguments
        t1File {mustBeTextScalar}
        outFile {mustBeTextScalar}
    end
    t1File = char(t1File);
    [work, cleanup] = metools.util.tempFolder(); %#ok<ASGLU>
    [~, name, ext] = fileparts(t1File);
    src = fullfile(work, [name ext]);
    copyfile(t1File, src);

    spec.data = {src};
    spec.data_wmh = {''};
    spec.nproc = 0;
    spec.useprior = '';
    spec.opts.tpm = {fullfile(spm('dir'), 'tpm/TPM.nii')};
    spec.opts.affreg = 'mni';
    spec.opts.biasstr = 0.5;
    spec.extopts.restypes.optimal = [1 0.3];
    spec.extopts.setCOM = 1;
    spec.extopts.APP = 1070;
    spec.extopts.affmod = 0;
    spec.extopts.LASstr = 0.5;
    spec.extopts.LASmyostr = 0;
    spec.extopts.gcutstr = 2;
    spec.extopts.WMHC = 2;
    spec.extopts.registration.shooting.shootingtpm = ...
        {fullfile(spm('dir'), 'toolbox/CAT/templates_MNI152NLin2009cAsym/Template_0_GS.nii')};
    spec.extopts.registration.shooting.regstr = 0.5;
    spec.extopts.vox = 1.5;
    spec.extopts.bb = 12;
    spec.extopts.SRP = 42;
    spec.extopts.ignoreErrors = 1;
    spec.output.BIDS.BIDSno = 1;
    spec.output.surface = 0;
    spec.output.ROImenu.noROI = struct([]);
    spec.output.GM.native = 0;
    spec.output.GM.mod = 1;
    spec.output.GM.dartel = 0;
    spec.output.WM.native = 0;
    spec.output.WM.mod = 0;
    spec.output.WM.dartel = 0;
    spec.output.labelnative = 1;
    spec.output.biaswarped = 1;
    spec.output.jacobianwarped = 0;
    spec.output.warps = [0 0];
    matlabbatch{1}.spm.tools.cat.estwrite = spec;
    metools.util.runSpmBatch(matlabbatch);

    copyfile(fullfile(work, 'mri', ['p0' name ext]), char(outFile));
end
