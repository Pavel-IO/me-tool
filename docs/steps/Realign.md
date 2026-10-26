# Realign

Rigid-body motion correction of a (multi-echo) 4D series.

**Streams** reads `bold` (all echoes); writes `bold` (`r<name>` for every echo),
`bold_mean` (`mean<master>`), `rp` (`rp_<master>.txt`).
**Parameters** `Master` (index of the echo used for estimation, default 2), `Unwarp`
(`true` is not implemented).
**Function** `metools.fmri.proc.realign(masterFile, otherFiles)`.

## Method

Head motion between volumes is modelled as a rigid-body transformation with six
parameters: translations $t_x, t_y, t_z$ (mm) and rotations $\alpha$ (pitch),
$\beta$ (roll), $\gamma$ (yaw) (radians). For every volume $i$ of the master echo, SPM
(`spm_realign`) finds the parameters $q_i$ that minimise the sum of squared differences
between the volume and the reference (the first volume, `rtm = 0`):

$$\hat q_i = \arg\min_{q} \sum_{x} \big( f_i(M(q)\,x) - f_1(x) \big)^2 ,$$

using Gauss-Newton optimisation on images smoothed with a 5 mm Gaussian, sampled every
4 mm, keeping 90 % of the voxels with the highest contribution (`quality 0.9`), with
2nd-degree B-spline interpolation.

Estimation is done on the master echo only (by default the second echo, which has the
best compromise between signal and contrast). The volumes are then resliced into the
space of the first volume with 4th-degree B-spline interpolation; voxels that moved
outside the field of view in any volume are set to zero (`mask 1`). The mean of the
resliced master volumes is written as the mean image. The six parameters of every volume
are stored in `rp_<master>.txt` (columns: x, y, z in mm; pitch, roll, yaw in radians).

The other echoes are acquired at the same time as the master, so they should move with
it: the orientation matrix of every master volume is copied to the corresponding volume
of each other echo, which is then resliced in the same way.

## Outputs

* `r<name>.nii` for every echo
* `mean<master>.nii`
* `rp_<master>.txt`
* QC (with logging): plot of translations, rotations and framewise displacement
  (Power et al. 2012, rotations converted to mm on a 50 mm sphere), maximal translation
  and rotation, mean FD, number of volumes with FD > 0.5 mm.

The headers of the input files are not changed.

## Known issues

* The transformation file of the master is deleted *before* its matrices are copied to
  the other echoes, so the other echoes probably receive the original, not the
  realigned, orientation; see [TODO](../TODO.md). Kept for equivalence with the original
  code.

## References

Friston KJ, Ashburner J, Frith CD, et al. Spatial registration and normalization of
images. Hum Brain Mapp 1995;3:165-189.
