classdef StepsTest < matlab.unittest.TestCase
    % Static tests of the built-in fMRI steps (ports, predicted names, checks); no SPM
    % and no data needed.

    methods (Access = private)
        function pipe = base(~)
            cfg = metools.fmri.FmriConfig();
            cfg.paths.masks = 'masks';
            cfg.acq.TR = 0.851;
            in = struct('bold', 'wbc_bold.nii', 'bold_mean', 'wmean.nii', 'rp', 'rp_bold.txt', ...
                'brain_mask', 'mask.nii');
            pipe = metools.fmri.FmriPipeline('t', cfg, Input = in);
        end
    end

    methods (Test)
        function nuisanceNamesDerivedFromOutput(tc)
            p = tc.base();
            p.NuisanceSignalRegression();
            plan = p.compile();
            tc.verifyTrue(plan.Ok, strjoin(plan.Errors, newline));
            tc.verifyEqual(plan.Env.current('bold').files, {'qwbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('covars').files, {'qwbc_bold_covars.tsv'});
            tc.verifyEqual(plan.Env.current('design_matrix').files, {'qwbc_bold_design.tsv'});
        end

        function nuisanceTwoVariantsDoNotCollide(tc)
            p = tc.base();
            p.Smooth();
            p.NuisanceSignalRegression(Target = 'bold_smooth', TissueSignals = 'mean');
            p.NuisanceSignalRegression(Target = 'bold', Out = 'bold_clean', Band = [0.008 0.09]);
            plan = p.compile();
            tc.verifyTrue(plan.Ok, strjoin(plan.Errors, newline));
            tc.verifyEqual(plan.Env.current('bold_clean').files, {'qwbc_bold.nii'});
            tc.verifyEqual(plan.Env.current('bold_smooth').files, {'qswbc_bold.nii'});
        end

        function nuisanceParameterChecks(tc)
            s = metools.fmri.StepNuisanceSignalRegression();
            tc.verifyEqual(s.MotionModel, 24);
            tc.verifyEqual(s.TissueSignals, 'acompcor');
            tc.verifyEqual(s.Band, [1/128 Inf]);
            tc.verifyError(@() metools.fmri.FmriPipeline().NuisanceSignalRegression(MotionModel = 18), 'Step:BadValue');
            tc.verifyError(@() metools.fmri.FmriPipeline().NuisanceSignalRegression(TissueSignals = 'pca'), 'Step:BadValue');

            p = tc.base();
            p.NuisanceSignalRegression(Band = [0.1 0.01]);
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'lower frequency');

            p = tc.base();
            p.NuisanceSignalRegression(Band = [0.008 0.7]);     % Nyquist for TR 0.851 is 0.588 Hz
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'Nyquist');

            p = tc.base();
            p.NuisanceSignalRegression(DesignName = 'design.mat');
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, '.tsv');
        end

        function parcellationOutputs(tc)
            p = tc.base();
            p.Parcellation(Atlas = 'atlases/BN_Atlas_246_2mm.nii');
            plan = p.compile();
            tc.verifyTrue(plan.Ok, strjoin(plan.Errors, newline));
            tc.verifyEqual(plan.Env.current('roi_timeseries').files, {'wbc_bold_atlas-BNAtlas2462mm_timeseries.tsv'});
            tc.verifyEqual(plan.Env.current('connectivity').files, ...
                {'wbc_bold_atlas-BNAtlas2462mm_meas-pearsonr_relmat.tsv'});
            tc.verifyEqual(plan.Env.current('roi_info').files, ...
                {'wbc_bold_atlas-BNAtlas2462mm_rois.tsv', 'wbc_bold_atlas-BNAtlas2462mm_parcellation.json'});

            p = tc.base();
            p.Parcellation(Atlas = 'a.nii', AtlasName = 'grid', SaveTimeseries = false, Measure = 'fisherz');
            plan = p.compile();
            tc.verifyTrue(plan.Ok, strjoin(plan.Errors, newline));
            tc.verifyFalse(plan.Env.has('roi_timeseries'));
            tc.verifyEqual(plan.Env.current('connectivity').files, {'wbc_bold_atlas-grid_meas-fisherz_relmat.tsv'});
        end

        function parcellationChecks(tc)
            p = tc.base();
            p.Parcellation();                                   % no atlas
            tc.verifyFalse(p.compile().Ok);

            p = tc.base();
            p.Parcellation(Atlas = 'a.nii', SaveTimeseries = false, SaveConnectivity = false);
            tc.verifyFalse(p.compile().Ok);

            p = tc.base();
            p.Parcellation(Atlas = 'a.nii', ExcludeOutliers = true);   % no covars stream
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'covars');

            cfg = metools.fmri.FmriConfig();
            p = metools.fmri.FmriPipeline('t', cfg, Input = 'wbc_bold.nii');
            p.Parcellation(Atlas = 'a.nii');                    % UseMask, but no brain_mask
            plan = p.compile();
            tc.verifyFalse(plan.Ok);
            tc.verifySubstring(plan.Errors{1}, 'brain_mask');
            p.Steps{1}.UseMask = false;
            tc.verifyTrue(p.compile().Ok);

            p = tc.base();
            p.Parcellation(Atlas = 'a.nii', AtlasName = 'my-atlas');
            tc.verifyFalse(p.compile().Ok);
        end
    end
end
