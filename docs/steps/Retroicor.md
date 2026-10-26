# Retroicor

Removal of cardiac and respiratory fluctuations with RETROICOR (retrospective image-based
correction), slice by slice.

**Streams** reads and writes `bold` (`b<name>` for every file).
**Parameters** `TR` (s, default `cfg.acq.TR`).
**Files** `<session>/markers.csv` (physiological and scan markers), `<session>/acq_params.json`
(`SliceTiming`).
**Functions** `readMarkers`, `readSliceTiming`, `retroicor`, `retroicorModel`.

## Physiological phases

The marker file (BrainVision export) contains the R-peaks of the ECG (`R`), respiration
events (`Resp`, `B`, `O`) and the scan triggers (`R128`), with the sampling interval in
its header. All times are converted to seconds relative to the first scan trigger; the
number of scan triggers must equal the number of volumes. Events before the first and
after the last scan are extrapolated with the last interval so that every acquisition
time lies between two events.

For a time $t$ between two consecutive events $t_k \le t < t_{k+1}$ the phase is the
fraction of the interval that has elapsed,

$$\varphi(t) = \frac{t - t_k}{t_{k+1} - t_k} \in [0, 1),$$

computed separately for the cardiac events ($\varphi_c$) and the respiratory events
($\varphi_r$).

## Model

Every slice $z$ is acquired at its own time, $t_{i,z} = (i-1)\,TR + \tau_z$, where
$\tau_z$ is the slice time from `SliceTiming` (with multiband, slices with the same
$\tau_z$ share their regressors). The physiological regressors of slice $z$ are Fourier
terms of the phases at these times,

$$c_m(i) = \cos(\pi m\,\varphi(t_{i,z})),\quad s_m(i) = \sin(\pi m\,\varphi(t_{i,z})),\qquad m = 1,\dots,4,$$

for the cardiac and for the respiratory phase (16 regressors), each centred to zero mean
(the basis is evaluated on a grid of 1000 phase values). For every voxel of the slice the
time course is fitted by ordinary least squares together with the DCT high-pass basis
$X_0$:

$$y = X_0\beta_0 + R_c\beta_c + R_r\beta_r + \varepsilon ,\qquad
\hat\beta = (X^\top X)^{-1}X^\top y,\quad X = [X_0\ R_c\ R_r].$$

The corrected time course removes only the physiological part and keeps the slow drifts:

$$y_{\mathrm{corr}} = y - R_c\hat\beta_c - R_r\hat\beta_r .$$

## Control figure

For the control figure an F-test compares the full model with the model without the
cardiac (or respiratory) terms,

$$F = \frac{(\mathrm{SSR}_{\mathrm{reduced}} - \mathrm{SSR}_{\mathrm{full}})/8}{\mathrm{SSR}_{\mathrm{full}}/(N - n - 16)},$$

and the voxels with $p < 0.001$ are shown as $-\log_{10} p$ in red-yellow over the mean
image, one panel for the pulse and one for breathing
(`<outputs>/retroicor/retrocor_<session>_<subject>_echo<k>.png`; also in the log as QC).

## Known issues

* The Fourier terms use $\cos(\pi m\varphi)$, i.e. half-integer harmonics of the cycle
  for odd $m$; the original RETROICOR uses $\cos(2\pi m\varphi)$. See [TODO](../TODO.md).
* The respiratory phase is defined linearly between respiration markers, not from the
  amplitude histogram of the respiratory signal as in Glover et al. (2000).
* The step runs after realignment, i.e. on resliced data, where a voxel mixes signal
  acquired in neighbouring slices at different times.

## References

Glover GH, Li TQ, Ress D. Image-based method for retrospective correction of physiological
motion effects in fMRI: RETROICOR. Magn Reson Med 2000;44:162-167.
