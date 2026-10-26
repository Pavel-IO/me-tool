classdef FmriPipeline < metools.Pipeline
    % FMRIPIPELINE  Pipeline with the built-in fMRI preprocessing steps.
    %
    %   import metools.*  metools.fmri.*
    %   cfg = FmriConfig();  cfg.acq.TR = 0.851;  cfg.acq.TEs = [15 36 58];  ...
    %   pipe = FmriPipeline('rest', cfg, Input = {'_echo_1.nii', '_echo_2.nii', '_echo_3.nii'});
    %   pipe.Realign(Master = 2);
    %   pipe.Smooth(FWHM = 6);
    %   pipe.add(MyStep(), Param = 1);        % any other metools.Step works as well
    %
    % Every method below appends one built-in step; the name/value pairs set its
    % parameters, port overrides (e.g. In = 'bold_smooth') and Keep. See
    % docs/GETTING_STARTED.md for the streams each step reads and writes.

    methods
        function obj = FmriPipeline(name, cfg, options)
            arguments
                name (1,:) char = 'pipeline'
                cfg = []
                options.Input = []
            end
            obj@metools.Pipeline(name, cfg, 'Input', options.Input);
        end

        function info = environmentInfo(obj)
            % MATLAB, SPM and CAT12 versions (SPM/CAT only when they are on the path).
            info = environmentInfo@metools.Pipeline(obj);
            try
                if ~isempty(which('spm'))
                    info{end+1} = spm('Ver');
                end
                if ~isempty(which('cat_version'))
                    info{end+1} = ['CAT ' char(cat_version)];
                end
            catch
            end
        end

        function step = Realign(obj, varargin)
            step = obj.add(metools.fmri.StepRealign(), varargin{:});
        end

        function step = FieldMap(obj, varargin)
            step = obj.add(metools.fmri.StepFieldMap(), varargin{:});
        end

        function step = EchoCombination(obj, varargin)
            step = obj.add(metools.fmri.StepEchoCombination(), varargin{:});
        end

        function step = Retroicor(obj, varargin)
            step = obj.add(metools.fmri.StepRetroicor(), varargin{:});
        end

        function step = Normalize(obj, varargin)
            step = obj.add(metools.fmri.StepNormalize(), varargin{:});
        end

        function step = CreateMask(obj, varargin)
            step = obj.add(metools.fmri.StepCreateMask(), varargin{:});
        end

        function step = Smooth(obj, varargin)
            step = obj.add(metools.fmri.StepSmooth(), varargin{:});
        end

        function step = NuisanceSignalRegression(obj, varargin)
            step = obj.add(metools.fmri.StepNuisanceSignalRegression(), varargin{:});
        end

        function step = Parcellation(obj, varargin)
            step = obj.add(metools.fmri.StepParcellation(), varargin{:});
        end
    end
end
