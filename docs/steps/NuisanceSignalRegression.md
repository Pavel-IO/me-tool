# NuisanceSignalRegression

Removal of motion-related and physiological fluctuations by regression of nuisance
signals from every voxel, together with a temporal band-pass filter and optional
censoring of high-motion scans. Everything that enters the regression is chosen by a
parameter, and the complete design matrix is saved with named columns, so the cleaning
can always be inspected and reproduced.

**Streams** reads `Signal` (`bold`, the normalised unsmoothed data), `Target` (`bold`; the
image that is cleaned, e.g. `bold_smooth`), `Mean` (`bold_mean`), `Rp` (`rp`); writes
`Out` (`q<target>`, into the stream of `Target` unless redirected, e.g.
`Out = 'bold_clean'`), `covars` (`q<target>_covars.tsv`), `design_matrix`
(`q<target>_design.tsv`).
**Functions** `motionRegressors`, `framewiseDisplacement`, `maskSignal`, `compCor`,
`outlierScans`, `dctFilterBasis`, `nuisanceDesign`, `regressOut`.

## Parameters

| Parameter | Values (default) | Meaning |
|---|---|---|
| `MotionModel` | 0, 6, 12, 24 (**24**) | motion regressors, see [Motion](#motion-regressors) |
| `FdMethod` | `'power'`, `'legacy'` (**power**) | how framewise displacement is computed |
| `FdRegressor` | true/false (**false**) | FD as one more regressor |
| `TissueSignals` | `'mean'`, `'acompcor'`, `'none'` (**acompcor**) | WM and CSF signals |
| `CompCorComponents` | integer (**5**) | components per mask for `acompcor` |
| `Band` | [low high] Hz (**[1/128 Inf]**) | pass band of the temporal filter |
| `ScrubFd` | mm or `[]` (**[]**) | FD threshold for censoring; `[]` = none |
| `ScrubNeighbors` | [before after] (**[0 0]**) | scans censored around each outlier |
| `CensorInterp` | `'pchip'`, `'linear'`, `'spline'` (**pchip**) | interpolation of censored scans before the low-pass |
| `MasksDir` | folder (cfg `paths.masks`) | folder of the tissue masks |
| `WmMask`, `CsfMask` | files (`WM09.nii`, `CSFmaskVENTlat.nii`) | tissue masks in MNI space |
| `TR` | s (cfg `acq.TR`) | repetition time |
| `Prefix` | (`q`) | prefix of the cleaned image |
| `CovarsName`, `DesignName` | (`''` = `<out>_covars.tsv`, `<out>_design.tsv`) | names of the TSV files |

The default is a middle ground between the original Cosmic2 regression and a typical
connectivity denoising: the Friston 24-parameter model with aCompCor, SPM's high-pass
filter, no low-pass and no censoring. Two complete settings:

| | original Cosmic2 | connectivity (approx. CONN default) |
|---|---|---|
| `MotionModel` | 24 | 12 |
| `FdMethod` | `'legacy'` | `'power'` |
| `FdRegressor` | true | false |
| `TissueSignals` | `'mean'` | `'acompcor'`, 5 components |
| `Band` | `[1/128 Inf]` | `[0.008 0.09]` |
| `ScrubFd` | `[]` | 0.5 |

The original setting gives the same result as the regression of METools 0.1 (`clearFmriData`
of the lab library), up to floating-point rounding.

## Model

For every voxel time course $y$ of the `Target` image (without censoring)

$$\hat\beta = X^{+} y,\qquad y_{\mathrm{clean}} = y - X\hat\beta + x_c\hat\beta_c ,$$

with the design matrix

$$X = [\,\tilde M,\ \widetilde{\mathrm{FD}},\ \tilde T,\ X_0\,]$$

where $\tilde M$ are the motion regressors, $\widetilde{\mathrm{FD}}$ the framewise
displacement (only with `FdRegressor`), $\tilde T$ the tissue signals and $X_0$ the
filter basis; $x_c$ is its constant column, so the voxel mean is kept. With censoring
the same model is fitted in three stages, see [Censoring](#censoring). The tilde means that the regressor was filtered by the same band
as the data (projection of $X_0$: $\tilde x = x - X_0 (X_0^\top X_0)^{+} X_0^\top x$), so
that data and regressors contain the same frequencies (Hallquist et al. 2013). Because the
filter is part of the same regression, filtering and nuisance removal happen in one step
and the filter does not reintroduce removed signal (Lindquist et al. 2019).

### Temporal filter

The DCT basis (`spm_dctmtx`) of $N$ scans has columns $\cos$ with frequencies
$f_j = (j-1)/(2N\,TR)$. $X_0$ contains the constant, the cosines below `Band(1)` (SPM
convention: the first $\lfloor 2N\,TR\cdot\mathrm{Band}(1) + 1\rfloor$ columns, so
`Band(1) = 1/128` is SPM's 128 s high-pass), and the cosines above `Band(2)`. `Band(1) = 0`
means no high-pass, `Band(2) = Inf` no low-pass. A low-pass adds many columns
(e.g. 0.09 Hz with TR 0.851 s removes about 85 % of the frequencies); the log reports the
degrees of freedom that are left.

### Motion regressors

From the six realignment parameters $r(t)$ (`MotionModel`):

| Model | Regressors |
|---|---|
| 0 | none |
| 6 | $r$ |
| 12 | $[\,r,\ \dot r\,]$ |
| 24 | $[\,r,\ \dot r,\ r^2,\ \dot r^2\,]$ (Friston 1996) |

with $\dot r(t) = r(t) - r(t-1)$, $\dot r(1) = 0$. Column names follow fMRIPrep
(`trans_x`, `rot_z_derivative1_power2`, ...).

### Framewise displacement

$$\mathrm{FD}(t) = \sum_{j=1}^{6} |\Delta r_j(t)|$$

* `'power'` (Power et al. 2012): raw parameters, rotations converted to mm on a sphere of
  50 mm radius. This is the usual definition and the one the threshold `ScrubFd` refers to.
* `'legacy'` (original Cosmic2, from `bramila_framewiseDisplacement`): the parameters are
  first filtered by the band (as the other regressors) and linearly detrended, and the
  rotations are used in radians without conversion, so they contribute very little.

FD is always written to `covars`; it enters the regression only with `FdRegressor`.

### Tissue signals

The white-matter and CSF (lateral ventricles) masks in MNI space are resampled to the grid
of the mean image (`resampleLike`, the `spm_imcalc` default interpolation) and thresholded
at 0.5. The voxel time courses are taken from the `Signal` image (unsmoothed, so smoothing
does not mix grey matter into them), linearly detrended and high-pass filtered (SPM filter
with cut-off $1/\mathrm{Band}(1)$ s).

* `'mean'`: the average of the voxels of each mask, $s_{\mathrm{WM}}$, $s_{\mathrm{CSF}}$.
* `'acompcor'` (Behzadi et al. 2007): every voxel time course is scaled to unit variance,
  and the first `CompCorComponents` left singular vectors of the scans x voxels matrix of
  each mask are used. The log reports the explained variance.
* `'none'`: no tissue signals.

### Censoring

With `ScrubFd`, scans with $\mathrm{FD} > $ `ScrubFd` (and `ScrubNeighbors` scans before
and after) are censored. Let $u$ be the uncensored scans and $X = [A,\ L]$, where $L$ are
the low-pass columns of the filter (cosines above `Band(2)`) and $A$ all other columns
(regressors, constant, high-pass). Then (Power et al. 2014):

1. $\hat\beta = (A_u^\top A_u)^{+} A_u^\top y_u$, i.e. the betas are estimated from the
   uncensored scans only, and $r = y - A\hat\beta + x_c\hat\beta_c$ for all scans;
2. $r$ at the censored scans is replaced by interpolation in time from the uncensored
   scans (`CensorInterp`, default piecewise cubic Hermite `pchip`, which does not
   overshoot; censored scans at the start or end take the nearest uncensored value);
3. the low-pass is applied to the gap-free series: $y_{\mathrm{clean}} = r - L(L^\top L)^{+}L^\top r$.

Without a low-pass the uncensored scans get exactly the values of a regression with one
spike regressor per censored scan. With a low-pass this order matters: a joint regression
with spike regressors would force the filtered signal to the mean at every censored scan
and pull the pass-band signal towards the mean around it. The cleaned values of censored
scans are interpolated, not measured; the `outlier` column of `covars` marks them, so later
steps (e.g. [Parcellation](Parcellation.md) with `ExcludeOutliers`) can leave them out.
Without censoring the three stages are identical to the joint regression above.

## Outputs

* `Out`: the cleaned 4D image.
* `covars` (`q<target>_covars.tsv`): one row per scan, columns `framewise_displacement`,
  `outlier` (0/1) and the tissue signals (`white_matter`, `csf` or `wm_comp_cor_01`, ...,
  `csf_comp_cor_01`, ...).
* `design_matrix` (`q<target>_design.tsv`): the whole $X$ with named columns: motion,
  `framewise_displacement`, tissue, `dct_constant`, `dct_hp01`, ..., `dct_lp001`, ...
  (censored scans are in `covars`, column `outlier`).

Both are tab-separated text with a header line (missing values `n/a`), readable by
`metools.util.readTsv` or `pandas.read_csv(f, sep='\t')`.

**QC** (with logging): number of scans, regressors, censored scans, filter columns,
degrees of freedom left (approximately), mean FD and the list of regressors.

Two cleanings in one pipeline (e.g. smoothed data for voxel-wise analyses, unsmoothed for
connectivity) are two steps with different `Target`/`Out`; their files do not collide
because the names are derived from the output.

## Known issues

* The interpolated value of a censored scan is only an estimate; fast fluctuations
  (above the pass band) at a censored scan cannot be recovered, so a small part of the
  interpolation error remains in the pass band around it.

* The masks are resampled to the mean image, which must be in the same space as the
  `Signal` image (normalised data).
* The interpolation used for the masks is the `spm_imcalc` default; this page earlier
  described it as trilinear - to be verified (see [TODO](../TODO.md)).

## References

Friston KJ, Williams S, Howard R, Frackowiak RS, Turner R. Movement-related effects in
fMRI time-series. Magn Reson Med 1996;35:346-355.
Behzadi Y, Restom K, Liau J, Liu TT. A component based noise correction method (CompCor)
for BOLD and perfusion based fMRI. NeuroImage 2007;37:90-101.
Power JD, Barnes KA, Snyder AZ, Schlaggar BL, Petersen SE. Spurious but systematic
correlations in functional connectivity MRI networks arise from subject motion.
NeuroImage 2012;59:2142-2154.
Hallquist MN, Hwang K, Luna B. The nuisance of nuisance regression: spectral misspecification
in a common approach to resting-state fMRI preprocessing reintroduces noise and obscures
functional connectivity. NeuroImage 2013;82:208-225.
Power JD, Mitra A, Laumann TO, Snyder AZ, Schlaggar BL, Petersen SE. Methods to detect,
characterize, and remove motion artifact in resting state fMRI. NeuroImage 2014;84:320-341.
Lindquist MA, Geuter S, Wager TD, Caffo BS. Modular preprocessing pipelines can
reintroduce artifacts into fMRI data. Hum Brain Mapp 2019;40:2358-2376.
Whitfield-Gabrieli S, Nieto-Castanon A. Conn: a functional connectivity toolbox for
correlated and anticorrelated brain networks. Brain Connect 2012;2:125-141.
