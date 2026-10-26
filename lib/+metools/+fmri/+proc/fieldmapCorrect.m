function fieldmapCorrect(phaseDiffFile, magnitudeFile, masterFile, otherFiles, options)
    % FIELDMAPCORRECT  Correction of susceptibility distortions with a phase-difference
    % field map (SPM FieldMap toolbox).
    %
    %   metools.fmri.proc.fieldmapCorrect(phaseDiffFile, magnitudeFile, masterFile, otherFiles)
    %
    %   phaseDiffFile, magnitudeFile   field map: phase difference and first magnitude image
    %   masterFile                     4D series the voxel displacement map is matched to
    %   otherFiles                     further series corrected with the same map
    %   EchoTimes          short and long echo time of the field map in ms ([5.29 7.75])
    %   TotalReadoutTime   total EPI readout time in ms (20.8)
    %   BlipDirection      k-space traversal direction (1)
    %   PhaseEncodingDir   phase-encoding axis of the EPI: 1 = x, 2 = y, 3 = z (2)
    %
    % Outputs: u<name> next to every series. The voxel displacement map and all other
    % intermediate files are created in a temporary folder and removed.
    %
    % Port of fieldmapCorrection from the lab library (results identical).
    arguments
        phaseDiffFile {mustBeTextScalar}
        magnitudeFile {mustBeTextScalar}
        masterFile {mustBeTextScalar}
        otherFiles {mustBeText} = {}
        options.EchoTimes (1,2) double {mustBePositive} = [5.29 7.75]
        options.TotalReadoutTime (1,1) double {mustBePositive} = 20.8
        options.BlipDirection (1,1) double {mustBeMember(options.BlipDirection, [-1 1])} = 1
        options.PhaseEncodingDir (1,1) double {mustBeMember(options.PhaseEncodingDir, [1 2 3])} = 2
    end
    phaseDiffFile = char(phaseDiffFile);
    magnitudeFile = char(magnitudeFile);
    masterFile = char(masterFile);
    for f = {phaseDiffFile, magnitudeFile}
        if exist(f{1}, 'file') ~= 2
            error('fieldmapCorrect:MissingFile', 'File "%s" was not found.', f{1});
        end
    end

    % the field map is processed on copies: all its derived files stay in the work folder
    [work, cleanup] = metools.util.tempFolder(); %#ok<ASGLU>
    phase = fullfile(work, basenameOf(phaseDiffFile));
    magnitude = fullfile(work, basenameOf(magnitudeFile));
    copyfile(phaseDiffFile, phase);
    copyfile(magnitudeFile, magnitude);

    vdm = calculateVdm(phase, magnitude, masterFile, options);
    series = [reshape(cellstr(otherFiles), 1, []), {masterFile}];
    for e = 1:numel(series)
        applyVdm(vdm, series{e}, options.PhaseEncodingDir);
    end
end

function vdm = calculateVdm(phase, magnitude, masterFile, options)
    s.data.presubphasemag.phase = {phase};
    s.data.presubphasemag.magnitude = {magnitude};
    d.et = options.EchoTimes;
    d.maskbrain = 1;
    d.blipdir = options.BlipDirection;
    d.tert = options.TotalReadoutTime;
    d.epifm = 0;
    d.ajm = 0;
    d.uflags.method = 'Mark3D';
    d.uflags.fwhm = 10;
    d.uflags.pad = 0;
    d.uflags.ws = 1;
    d.mflags.template = {fullfile(spm('dir'), 'toolbox/FieldMap/T1.nii')};
    d.mflags.fwhm = 5;
    d.mflags.nerode = 2;
    d.mflags.ndilate = 4;
    d.mflags.thresh = 0.5;
    d.mflags.reg = 0.02;
    s.defaults.defaultsval = d;
    s.session.epi = {masterFile};
    s.matchvdm = 1;
    s.sessname = 'session';
    s.writeunwarped = 0;
    s.anat = '';
    s.matchanat = 0;
    matlabbatch{1}.spm.tools.fieldmap.calculatevdm.subj = s;
    metools.util.runSpmBatch(matlabbatch);

    % the magnitude image matched to the EPI is written next to the EPI
    wfmag = metools.util.addPrefix(masterFile, 'wfmag_');
    if exist(wfmag, 'file') == 2
        delete(wfmag);
    end
    vdm = metools.util.addPrefix(phase, 'vdm5_sc');
    assert(exist(vdm, 'file') == 2, 'fieldmapCorrect: the voxel displacement map was not created.');
end

function applyVdm(vdm, scansFile, pedir)
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.data.scans = {scansFile};
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.data.vdmfile = {vdm};
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.pedir = pedir;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.which = [2 1];
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.rinterp = 4;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.wrap = [0 1 0];
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.mask = 1;
    matlabbatch{1}.spm.tools.fieldmap.applyvdm.roptions.prefix = 'u';
    metools.util.runSpmBatch(matlabbatch);
    delete(metools.util.addPrefix(scansFile, 'meanu'));
end

function n = basenameOf(file)
    [~, name, ext] = fileparts(file);
    n = [name ext];
end
