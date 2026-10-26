function results = run_tests()
    % RUN_TESTS  Runs all tests in the folder tests and writes the result to test_report.txt.
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, 'lib'));
    addpath(fullfile(here, 'lib', 'thirdparty', 'nifti_tools'));
    addpath(fullfile(here, 'tests'));

    reportFile = fullfile(here, 'test_report.txt');
    if exist(reportFile, 'file')
        delete(reportFile);
    end
    diary(reportFile);
    cleanup = onCleanup(@() diary('off')); %#ok<NASGU>

    fprintf('METools tests, %s, MATLAB %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), version);
    suite = matlab.unittest.TestSuite.fromFolder(fullfile(here, 'tests'));
    results = run(suite);
    disp(table(results));
    fprintf('Total: %d, passed: %d, failed: %d, incomplete: %d\n', ...
        numel(results), nnz([results.Passed]), nnz([results.Failed]), nnz([results.Incomplete]));
end
