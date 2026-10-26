classdef Cosmic2RegressionTest < matlab.unittest.TestCase
    % Static check that the 8-step Cosmic2 pipeline, assembled with METools, predicts the
    % same files and releases the same intermediate files as the original run_pipeline.

    methods (Access = private)
        function pipe = cosmic2(~)
            cfg = metools.fmri.FmriConfig();
            cfg.paths.project = 'g:/Data/Cosmic2';
            cfg.paths.masks = 'g:/Data/Cosmic/masks/CSF_WM';
            cfg.acq.TR = 0.851;
            cfg.acq.TEs = [15 36 58];
            pipe = metools.fmri.FmriPipeline('rest', cfg, Input = {'_echo_1.nii', '_echo_2.nii', '_echo_3.nii'});
            % Keep: the original pipeline never deleted the mean image written by Realign
            pipe.Realign(Master = 2, Unwarp = false, Keep = 'bold_mean');
            pipe.FieldMap();
            pipe.EchoCombination();
            pipe.Retroicor();
            pipe.Normalize();
            pipe.CreateMask(Threshold = 0.8);
            pipe.Smooth(FWHM = 6);
            % the original regression (see docs/steps/NuisanceSignalRegression.md)
            pipe.NuisanceSignalRegression(Target = 'bold_smooth', MotionModel = 24, ...
                FdMethod = 'legacy', FdRegressor = true, TissueSignals = 'mean', ...
                Band = [1/128 Inf], ScrubFd = []);
            pipe.Retain('bold', 'bold_smooth', 'bold_mean', 'rp', 'brain_mask', ...
                'covars', 'design_matrix', 't1_coreg');
        end
    end

    methods (Test)
        function planIsValidWithoutWarnings(tc)
            plan = tc.cosmic2().compile();
            tc.verifyTrue(plan.Ok, strjoin(plan.Errors, newline));
            tc.verifyEmpty(plan.Warnings);
        end

        function finalFileNames(tc)
            plan = tc.cosmic2().compile();
            tc.verifyEqual(plan.Env.current('bold').files, {'wbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('bold_smooth').files, {'qswbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('brain_mask').files, {'wbc_bold_mask8.nii'});
            tc.verifyEqual(plan.Env.current('t1_coreg').files, {'r_t1.nii'});
            tc.verifyEqual(plan.Env.current('covars').files, {'qswbc_bold_covars.tsv'});
            tc.verifyEqual(plan.Env.current('design_matrix').files, {'qswbc_bold_design.tsv'});
        end

        function connectivityBranch(tc)
            % The Cosmic2 run_rest: a second cleaning of the unsmoothed data and two
            % parcellations next to the original pipeline.
            pipe = tc.cosmic2();
            pipe.NuisanceSignalRegression(Target = 'bold', Out = 'bold_clean', MotionModel = 12, ...
                TissueSignals = 'acompcor', Band = [0.008 0.09], ScrubFd = 0.5);
            pipe.Parcellation(In = 'bold_clean', Atlas = 'g:/atlases/bna.nii', AtlasName = 'bna', ...
                UseMask = false, ExcludeOutliers = true);
            pipe.Parcellation(In = 'bold_clean', Atlas = 'g:/atlases/brain_6mm.nii', ...
                AtlasType = 'voxels', AtlasName = 'grid6mm', UseMask = false, ExcludeOutliers = true, ...
                SaveTimeseries = false);
            pipe.Retain('all');
            plan = pipe.compile();
            tc.verifyTrue(plan.Ok, strjoin(plan.Errors, newline));
            tc.verifyEqual(plan.Env.current('bold_clean').files, {'qwbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('bold').files, {'wbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('bold_smooth').files, {'qswbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('covars').files, {'qwbc_bold_covars.tsv'});
            tc.verifyEqual(plan.Env.current('connectivity').files, ...
                {'qwbc_bold_atlas-grid6mm_meas-pearsonr_relmat.tsv'});
            tc.verifyEqual(plan.Env.current('roi_timeseries').files, {'qwbc_bold_atlas-bna_timeseries.tsv'});
            tc.verifyEqual(plan.Env.current('roi_info').files, ...
                {'qwbc_bold_atlas-grid6mm_rois.tsv', 'qwbc_bold_atlas-grid6mm_parcellation.json'});
        end

        function intermediateFilesAreReleasedLikeInCosmic2(tc)
            plan = tc.cosmic2().compile();
            d = plan.DeleteAfter;
            tc.verifyEmpty(d{1});
            tc.verifyEqual(sort(d{2}), {'r_echo_1.nii', 'r_echo_2.nii', 'r_echo_3.nii'});
            tc.verifyEqual(sort(d{3}), {'ur_echo_1.nii', 'ur_echo_2.nii', 'ur_echo_3.nii'});
            tc.verifyEqual(d{4}, {'c_bold.nii'});
            tc.verifyEqual(d{5}, {'bc_bold.nii'});
            tc.verifyEmpty(d{6});
            tc.verifyEmpty(d{7});
            tc.verifyEqual(d{8}, {'swbc_bold.nii'});
        end
    end
end
