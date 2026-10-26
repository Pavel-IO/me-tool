# FieldMap

Correction of geometric distortions caused by inhomogeneities of the static field $B_0$.

**Streams** reads and writes `bold` (`u<name>` for every echo).
**Parameters** `Master` (2), `FieldmapTEs` ([5.29 7.75] ms), `TotalReadoutTime`
(20.8 ms), `BlipDirection` (1), `PhaseEncodingDir` (2 = y).
**Files** `<subject>/fields/_phasediff.nii`, `_magnitude1.nii`.
**Function** `metools.fmri.proc.fieldmapCorrect(...)` (SPM FieldMap toolbox).

## Method

Echo-planar images are distorted along the phase-encoding direction where $B_0$ deviates
from its nominal value. The field map is a gradient-echo acquisition at two echo times;
the phase difference $\Delta\varphi$ between them gives the field offset

$$\Delta B_0(x) = \frac{\Delta\varphi(x)}{2\pi\,\Delta TE}\quad[\mathrm{Hz}],\qquad \Delta TE = TE_2 - TE_1 = 2.46\ \mathrm{ms}.$$

The phase is unwrapped (3D region-growing method `Mark3D`), masked to the brain using the
magnitude image, extrapolated and smoothed (FWHM 10 mm). The voxel displacement map
(VDM) is the shift, in voxels along the phase-encoding direction, caused by the offset
during the EPI readout:

$$d(x) = s \cdot \Delta B_0(x)\cdot T_{\mathrm{read}},$$

with the total readout time $T_\mathrm{read} = 20.8$ ms and the sign $s$ given by the
blip direction. The VDM is then matched (coregistered) to the master EPI series via the
forward-warped magnitude image, so that it is in the same space as the data.

Every echo (the master and the others) is unwarped by resampling each volume along the
phase-encoding axis ($y$) at the displaced positions, with 4th-degree B-spline
interpolation, wrap-around along $y$, and masking of voxels that fall outside the field
of view. The same VDM is used for all volumes and echoes (no motion-by-susceptibility
interaction is modelled).

All intermediate files (scaled phase, unwrapped field map, VDM, brain mask, matched
magnitude, mean of the unwarped series) are created in a temporary folder or deleted, so
only `u<name>.nii` remain.

## Known issues

* The acquisition parameters (field-map echo times, readout time, phase-encoding
  direction) are fixed defaults of the step; they should come from the configuration or
  the JSON sidecars.
* The step does not update `bold_mean`: later steps that use the mean image (Normalize,
  NuisanceSignalRegression) see the mean of the realigned but not unwarped master echo.
  See [TODO](../TODO.md).

## References

Jezzard P, Balaban RS. Correction for geometric distortion in echo planar images from B0
field variations. Magn Reson Med 1995;34:65-73.
Hutton C, Bork A, Josephs O, et al. Image distortion correction in fMRI: a quantitative
evaluation. NeuroImage 2002;16:217-240.
