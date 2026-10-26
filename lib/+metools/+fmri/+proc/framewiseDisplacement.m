function fd = framewiseDisplacement(motion, options)
    % FRAMEWISEDISPLACEMENT  Framewise displacement (Power et al. 2012).
    %
    %   fd = metools.fmri.proc.framewiseDisplacement(rp)          % SPM rp (rotations in rad)
    %
    %   motion          scans x 6: 3 translations (mm), 3 rotations
    %   RotationUnits   'radians' (SPM, default), 'degrees' (FSL) or 'none' (rotations
    %                   used as they are, without conversion to mm)
    %   Radius          head radius for the conversion of rotations (default 50 mm)
    %   Detrend         true: linear detrend of the parameters first (as in bramila)
    %
    % Returns a column vector, the first value is 0.
    arguments
        motion (:,6) double
        options.RotationUnits {mustBeMember(options.RotationUnits, {'radians', 'degrees', 'none'})} = 'radians'
        options.Radius (1,1) double {mustBePositive} = 50
        options.Detrend (1,1) logical = false
    end
    ts = motion;
    if options.Detrend
        ts = detrend(ts);
    end
    switch options.RotationUnits
        case 'radians'
            ts(:, 4:6) = options.Radius * ts(:, 4:6);
        case 'degrees'
            ts(:, 4:6) = (2*options.Radius*pi/360) * ts(:, 4:6);
    end
    dts = [zeros(1, 6); diff(ts)];
    fd = sum(abs(dts), 2);
end
