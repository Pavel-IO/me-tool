# CreateMask

Brain mask of the functional data by an intensity threshold, in the way SPM defines the
analysis mask of a first-level model (`spm_spm`).

**Streams** reads `bold` (one file); writes `brain_mask` (`<name>_mask8.nii`).
**Parameters** `Threshold` (relative threshold, default 0.8), `Suffix` (`_mask8`).
**Function** `metools.fmri.proc.createBrainMask(inFile, outFile, threshold)`.

## Method

For every volume $i$ the global value $g_i$ is computed with `spm_global`: the mean of all
voxels above one eighth of the volume mean (a rough brain mean). The data are scaled to a
grand mean of 100,

$$\tilde y_i(v) = y_i(v)\cdot \frac{100}{\bar g},\qquad \bar g = \frac1N\sum_i g_i ,$$

and a voxel is included when its scaled value exceeds the threshold times the scaled
global value of the volume,

$$\tilde y_i(v) > \theta\, g_i \frac{100}{\bar g}\qquad (\theta = 0.8),$$

and its values are not constant over the tested volumes. The mask is written as uint8
(1 inside, 0 outside) with the geometry of the input.

## Known issues

* As in the original code, only the **first volume** of a 4D file is tested (the number
  of scans is taken from the number of file names), and the test for non-constant values
  then has nothing to compare, so the resulting mask is most likely **empty**. See
  [TODO](../TODO.md). The mask is not used by the other steps of the current pipeline.

## References

SPM12 manual, model estimation (`spm_spm`), explicit and implicit masking.
