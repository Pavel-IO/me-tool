function R = motionRegressors24(rpFile)
    % MOTIONREGRESSORS24  Friston 24-parameter motion model from SPM realignment
    % parameters: [rp, diff(rp), rp.^2, diff(rp).^2] (scans x 24, first difference = 0).
    % Same as metools.fmri.proc.motionRegressors(rpFile, 24), which also returns the names.
    arguments
        rpFile {mustBeTextScalar}
    end
    R = metools.fmri.proc.motionRegressors(rpFile, 24);
end
