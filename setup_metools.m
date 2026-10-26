function setup_metools()
    % SETUP_METOOLS  Adds METools to the MATLAB path: the library (lib) and the bundled
    % third-party tools (lib/thirdparty).
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, 'lib'));
    addpath(fullfile(here, 'lib', 'thirdparty', 'nifti_tools'));
end
