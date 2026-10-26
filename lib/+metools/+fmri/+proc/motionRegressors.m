function [R, names] = motionRegressors(rp, model)
    % MOTIONREGRESSORS  Motion regressors from the six realignment parameters.
    %
    %   [R, names] = metools.fmri.proc.motionRegressors('rp_bold.txt', 24)
    %   [R, names] = metools.fmri.proc.motionRegressors(rpMatrix, 12)
    %
    %   rp     scans x 6 (3 translations, 3 rotations) or the name of an SPM rp_*.txt file
    %   model  0   no regressors
    %          6   the parameters r
    %          12  [r, dr]                    dr = temporal difference, dr(1) = 0
    %          24  [r, dr, r.^2, dr.^2]       Friston 24-parameter model (default)
    %
    % names follow the fMRIPrep convention (trans_x, ..., rot_z_derivative1_power2).
    arguments
        rp
        model (1,1) double {mustBeMember(model, [0 6 12 24])} = 24
    end
    if ischar(rp) || isstring(rp)
        rp = spm_load(char(rp));
    end
    if size(rp, 2) ~= 6
        error('motionRegressors:BadSize', 'motionRegressors: expected 6 columns, got %d.', size(rp, 2));
    end
    base = {'trans_x', 'trans_y', 'trans_z', 'rot_x', 'rot_y', 'rot_z'};
    d = [zeros(1, 6); diff(rp)];
    der = strcat(base, '_derivative1');
    switch model
        case 0
            R = zeros(size(rp, 1), 0);
            names = {};
        case 6
            R = rp;
            names = base;
        case 12
            R = [rp d];
            names = [base der];
        case 24
            R = [rp d rp.^2 d.^2];
            names = [base der strcat(base, '_power2') strcat(der, '_power2')];
    end
end
