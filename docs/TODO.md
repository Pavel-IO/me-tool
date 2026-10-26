# TODO

Open points of METools: issues found in the ported processing code, decisions to make and
planned work. Most issues were kept on purpose so that the results stay identical to the
original Cosmic2 pipeline; each fix will change the results and needs a new comparison.

## Processing - possible errors (decide and fix)

- [ ] **Realign: the other echoes are probably not motion-corrected.** In `proc.realign`
  (port of `realignAndUnwarp`) the `.mat` file with the estimated transformations of the
  master echo is deleted *before* the matrices of the master are read and copied to the
  other echoes. The other echoes then receive the original orientation of the master
  (identical for all volumes) and are only resliced. Check: compare the voxel-wise motion
  of `r_echo_1.nii` and `r_echo_2.nii`, or read the matrices of the master before and
  after the deletion. Fix: read the master headers before deleting the `.mat` file.
- [ ] **CreateMask produces an (almost certainly) empty mask.** `proc.createBrainMask`
  (port of `create_mask_Explorer`) tests only the first volume of a 4D file and then the
  "values not constant" test has no data, so no voxel passes. Check `wbc_bold_mask8.nii`.
  Fix: use all volumes (the number of scans = number of volumes).
- [x] **FD in the nuisance regression ignores rotations.** Resolved by the parameter
  `FdMethod` of NuisanceSignalRegression: `'power'` (default, rotations x 50 mm) or
  `'legacy'` (the original computation, kept for equivalence).
- [ ] **Interpolation of the tissue masks.** `resampleLike` calls `spm_imcalc` with its
  default interpolation (in SPM12 most likely nearest neighbour, not trilinear as the
  documentation of METools 0.1 said). Verify in `spm_imcalc.m`; decide whether the masks
  should be resampled trilinearly (`Interp = 1`, then thresholded at 0.5). Changing it
  changes the results.
- [ ] **RETROICOR basis.** The Fourier terms are $\cos(\pi m \varphi)$, $m = 1..4$, i.e.
  half-integer harmonics for odd $m$ (not periodic over the cardiac/respiratory cycle).
  The original RETROICOR uses $\cos(2\pi m \varphi)$ (Glover 2000: $m = 1, 2$). Verify the
  intention.
- [ ] **RETROICOR respiratory phase** is linear between respiration markers, not
  amplitude-based (histogram equalisation, Glover 2000). Decide whether that is intended.
- [ ] **FieldMap does not update the mean image.** Normalize coregisters the T1 to the
  mean of the realigned, *not unwarped* master echo, while the data are unwarped. Options:
  apply the VDM to the mean as well (FieldMap writes `bold_mean`), or compute the mean
  after FieldMap.
- [ ] **EchoCombination: voxels with zero variance** (background) get infinite/undefined
  tSNR weights and NaN values. Decide on a mask or a fallback.

## Processing - parameters and design

- [ ] FieldMap acquisition parameters are fixed defaults of the step (field-map echo times
  5.29/7.75 ms, total readout time 20.8 ms, phase encoding y, blip direction 1). Move them
  to `FmriConfig` (`acq`) or read them from the JSON sidecars (`EchoTime1/2`,
  `TotalReadoutTime`, `PhaseEncodingDirection`).
- [ ] Realign with unwarping (`Unwarp = true`) is not implemented (the original code had it
  commented out); the step reports it in the static check.
- [ ] Normalize: the coregistration uses the CAT12 label image `p0` as the "stripped T1";
  consider a brain-masked T1 intensity image. The T1 processing is repeated in every
  session of a subject.
- [ ] EchoCombination: the original code computed in/out-of-brain masks (thresholds 0.25,
  0.20) without using them; the parameters were removed. Decide whether a mask was
  intended.
- [ ] Order of Retroicor and Realign: RETROICOR runs on resliced data; consider running it
  before realignment (per-slice timing is then exact).
- [x] NuisanceSignalRegression: the output names were fixed (`covar-csf-wm-sigs.mat`,
  `q_design_matrix.mat`). Now TSV files named after the output (`<out>_covars.tsv`,
  `<out>_design.tsv`), so several regressions in one pipeline do not collide.
- [ ] NuisanceSignalRegression: the tissue signals are computed again by every instance
  of the step (two cleanings = two extractions); cheap, but could be shared.
- [ ] **NuisanceSignalRegression: censoring + low-pass.** With spike regressors and a
  finite `Band(2)` the pass-band signal is pulled towards the mean around every censored
  scan (shown by `ProcTest/bandPassRegression`). Option: estimate the betas on the
  uncensored scans, interpolate the censored scans of the residuals, then apply the
  low-pass (Power et al. 2014, XCP-D). Changes the results of the connectivity variant.
- [ ] NuisanceSignalRegression: global signal regression and DVARS-based censoring are
  not implemented.
- [ ] Parcellation: nothing checks that the atlas and the data are in the same space.
  `UseMask = true` needs a working brain mask (see CreateMask above).
- [ ] Parcellation: verify the voxel template (`AtlasType = 'voxels'`) against the
  `5kvoxel` matrices of the original kD analysis (same template, numbering, coverage).
- [ ] Default of the `Target` port of NuisanceSignalRegression (now set explicitly to
  `bold_smooth` in the pipeline).

## Verification

- [ ] Run the refactored pipeline (all processing in `metools.fmri.proc`) and compare the
  outputs with the previous run: they should be identical (NuisanceSignalRegression with
  the original setting, see its page, up to floating-point rounding). Expected differences: no files
  left by CAT12 in `anat`, no VDM and field-map intermediates in `fields`.
- [ ] Integration tests of the processing functions on a small real data set (SPM needed).

## Library and publishing

- [ ] Licence of METools (currently none, i.e. all rights reserved). Check the code
  origins before publishing: `createBrainMask` is derived from SPM's `spm_spm` (GPL);
  `retroicorModel` from the lab RETROICOR code (author attribution); NIfTI tools are BSD
  (licence included in `lib/thirdparty/nifti_tools`).
- [ ] Clarify ownership (MU / CEITEC technology transfer).
- [ ] Put METools under git; `metools.version()` then appears with the commit in the logs.
- [ ] Delete the folder `external` (no longer used).

## Ideas (not planned)

- Attributes of the files in a stream (echo, TE, space) so that ports can require e.g.
  `space = MNI` and wrong orderings are found statically.
- Parallel processing of subjects.
- Subject-level steps (e.g. one T1 processing for all sessions).
