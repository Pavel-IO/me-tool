classdef FmriConfig < metools.Config
    % FMRICONFIG  Study configuration of fMRI pipelines.
    %
    %   cfg = metools.fmri.FmriConfig();
    %   cfg.paths.project = 'g:/Data/Cosmic2';
    %   cfg.paths.masks   = 'g:/Data/Cosmic/masks/CSF_WM';
    %   cfg.acq.TR  = 0.851;
    %   cfg.acq.TEs = [15 36 58];
    %
    % Sections: paths (metools.fmri.PathsConfig), acq (metools.fmri.AcquisitionConfig).
    % Access by path, session overrides and deep copy come from metools.Config.

    properties
        paths    % metools.fmri.PathsConfig
        acq      % metools.fmri.AcquisitionConfig
    end

    methods
        function obj = FmriConfig()
            obj.paths = metools.fmri.PathsConfig();
            obj.acq = metools.fmri.AcquisitionConfig();
        end
    end
end
