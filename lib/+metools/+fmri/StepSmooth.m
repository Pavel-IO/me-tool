classdef StepSmooth < metools.Step
    % STEPSMOOTH  Spatial smoothing of 4D images.
    %
    %   reads   In   (bold)
    %   writes  Out  (bold_smooth)   <Prefix><name> for every file
    %
    % The result goes to a separate stream, so the unsmoothed 'bold' stays available to
    % later steps (e.g. for signal extraction in NuisanceSignalRegression). To smooth in
    % place use Out="bold".
    %
    %   parameters  FWHM (mm, scalar or [x y z], default 6), Prefix (default 's')
    %   computation metools.fmri.proc.smooth

    properties
        FWHM (1,:) double {mustBePositive} = 6
        Prefix (1,:) char = 's'
    end

    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('bold_smooth');
        end

        function out = predict(obj, in, ~)
            out.Out = metools.Step.addPrefix(in.In, obj.Prefix);
        end

        function names = requiredFunctions(~)
            names = {'spm_jobman'};
        end

        function execute(obj, in, out, ~)
            for i = 1:numel(in.In)
                metools.fmri.proc.smooth(in.In{i}, out.Out{i}, obj.FWHM);
            end
        end
    end
end
