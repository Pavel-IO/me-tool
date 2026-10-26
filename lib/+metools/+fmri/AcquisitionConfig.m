classdef AcquisitionConfig < matlab.mixin.Copyable
    % ACQUISITIONCONFIG  Acquisition parameters shared by the steps of a study.
    %
    %   TR    repetition time in seconds (scalar)
    %   TEs   echo times in milliseconds (row vector, one value per echo)
    %
    % Typed properties: a typo (cfg.acq.Tr) or an invalid value is an error.

    properties
        TR  double {mustBeScalarOrEmpty, mustBePositive} = []
        TEs double {mustBePositive} = []
    end
end
