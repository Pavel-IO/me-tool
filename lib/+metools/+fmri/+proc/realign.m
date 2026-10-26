function realign(masterFile, otherFiles, options)
    % REALIGN  Rigid-body motion correction of a 4D series (SPM), applied to further
    % series acquired simultaneously (e.g. the other echoes of a multi-echo acquisition).
    %
    %   metools.fmri.proc.realign(masterFile, otherFiles)
    %
    %   masterFile   4D file on which the motion is estimated (e.g. the second echo)
    %   otherFiles   further 4D files of the same acquisition
    %
    % Outputs (written by SPM next to the inputs): r<name> for every file,
    % mean<name of master>, rp_<name of master>.txt. The headers of the inputs are left
    % unchanged (the .mat files SPM writes for 4D images are deleted).
    %
    % Port of realignAndUnwarp from the lab library (results identical). Unwarp = true
    % (realign & unwarp) is not implemented, as in the original.
    %
    % NOTE (see docs/TODO.md): as in the original, the .mat file with the estimated
    % transformations of the master is deleted BEFORE the transformations are copied to
    % the other files, so the other files probably receive the original (not the
    % realigned) matrices.
    arguments
        masterFile {mustBeTextScalar}
        otherFiles {mustBeText} = {}
        options.Unwarp (1,1) logical = false
    end
    if options.Unwarp
        error('realign:Unwarp', 'Realign & unwarp is not implemented.');
    end
    masterFile = char(masterFile);
    others = cellstr(otherFiles);

    REW.data = {{masterFile}};
    REW.eoptions = struct('quality', 0.9, ...
                          'sep', 4, ...
                          'fwhm', 5, ...
                          'rtm', 0, ...
                          'interp', 2, ...
                          'wrap', [0 0 0], ...
                          'weight', '');
    REW.roptions = struct('which', [2 1], ...
                          'interp', 4, ...
                          'wrap', [0 0 0], ...
                          'mask', 1, ...
                          'prefix', 'r');
    matlabbatch{1}.spm.spatial.realign.estwrite = REW;
    metools.util.runSpmBatch(matlabbatch);

    delete(strrep(masterFile, '.nii', '.mat'));
    for s = 1:numel(others)
        resliceWithMasterMatrices(masterFile, others{s});
    end
end

function resliceWithMasterMatrices(masterFile, otherFile)
    % Copies the orientation of every volume of the master to the other file and
    % reslices it (prefix r).
    masterHead = spm_vol(masterFile);
    otherHead = spm_vol(otherFile);
    for scan = 1:size(otherHead, 1)
        spm_get_space([otherHead(scan).fname ',' num2str(otherHead(scan).n)], masterHead(scan).mat);
    end
    matlabbatch{1}.spm.spatial.realign.write.data = {otherFile};
    matlabbatch{1}.spm.spatial.realign.write.roptions.which = [2 0];
    matlabbatch{1}.spm.spatial.realign.write.roptions.interp = 4;
    matlabbatch{1}.spm.spatial.realign.write.roptions.wrap = [0 0 0];
    matlabbatch{1}.spm.spatial.realign.write.roptions.mask = 1;
    matlabbatch{1}.spm.spatial.realign.write.roptions.prefix = 'r';
    metools.util.runSpmBatch(matlabbatch);
    delete(strrep(otherFile, '.nii', '.mat'));
end
