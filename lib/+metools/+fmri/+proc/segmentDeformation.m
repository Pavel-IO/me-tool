function [deformation, inverse] = segmentDeformation(imageFile, options)
    % SEGMENTDEFORMATION  SPM12 unified segmentation; returns the deformation field to MNI.
    %
    %   y = metools.fmri.proc.segmentDeformation('r_t1.nii')
    %   [y, iy] = metools.fmri.proc.segmentDeformation('r_t1.nii', Inverse = true)
    %
    % Writes y_<name> (and with Inverse also iy_<name>) next to the image; tissue maps are
    % not written. The segmentation parameters (<name>_seg8.mat) are deleted.
    arguments
        imageFile {mustBeTextScalar}
        options.Inverse (1,1) logical = false
    end
    imageFile = char(imageFile);
    ngaus = [1 1 2 3 4 2];
    spec.channel(1).vols = {imageFile};
    spec.channel(1).biasreg = 0.001;
    spec.channel(1).biasfwhm = 60;
    spec.channel(1).write = [0 0];
    for t = 1:6
        spec.tissue(t).tpm = {fullfile(spm('dir'), sprintf('tpm/TPM.nii,%d', t))};
        spec.tissue(t).ngaus = ngaus(t);
        spec.tissue(t).native = [0 0];
        spec.tissue(t).warped = [0 0];
    end
    spec.warp.mrf = 1;
    spec.warp.cleanup = 1;
    spec.warp.reg = [0 0.001 0.5 0.05 0.2];
    spec.warp.affreg = 'mni';
    spec.warp.fwhm = 0;
    spec.warp.samp = 3;
    spec.warp.write = [double(options.Inverse) 1];
    matlabbatch{1}.spm.spatial.preproc = spec;
    metools.util.runSpmBatch(matlabbatch);
    delete(strrep(imageFile, '.nii', '_seg8.mat'));
    deformation = metools.util.addPrefix(imageFile, 'y_');
    inverse = '';
    if options.Inverse
        inverse = metools.util.addPrefix(imageFile, 'iy_');
    end
end
