# Smooth

Spatial smoothing with an isotropic Gaussian kernel.

**Streams** reads `bold`; writes `bold_smooth` (`s<name>`), a separate stream, so the
unsmoothed data stay available.
**Parameters** `FWHM` (mm, scalar or [x y z], default 6), `Prefix` (`s`).
**Function** `metools.fmri.proc.smooth(inFile, outFile, fwhm)`.

## Method

Every volume is convolved with a 3D Gaussian kernel whose width is given as full width at
half maximum; $\sigma = \mathrm{FWHM} / (2\sqrt{2\ln 2}) \approx \mathrm{FWHM}/2.355$
(for 6 mm, $\sigma \approx 2.55$ mm). SPM (`spm_smooth`) performs the convolution
separably along x, y and z, taking the voxel size into account. Smoothing increases the
signal-to-noise ratio, compensates residual anatomical differences between subjects and
makes the data closer to the assumptions of Gaussian random field theory. The output keeps
the data type of the input.

## References

Friston KJ, Ashburner J, Kiebel SJ, Nichols TE, Penny WD (eds). Statistical Parametric
Mapping. Academic Press 2007, ch. 2.
