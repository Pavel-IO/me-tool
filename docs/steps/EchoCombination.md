# EchoCombination

Combination of the echoes of a multi-echo acquisition into one series.

**Streams** reads `bold` (all echoes); writes `bold` (`c_bold.nii`). With one input file
nothing is done (the file passes through).
**Parameters** `TEs` (echo times in ms, default `cfg.acq.TEs`).
**Function** `metools.fmri.proc.combineEchoesTsnr(echoFiles, echoTimes, outFile)`.

## Method

The BOLD contrast is $\partial S/\partial R_2^* \propto TE \cdot S(TE)$, so the optimal
echo time differs between regions (short $T_2^*$ near air-tissue boundaries, longer
elsewhere). Combining the echoes with voxel-wise weights recovers signal in regions of
dropout and improves the contrast-to-noise ratio (Poser et al. 2006, "PAID").

For every voxel $v$ and echo $e$ the temporal signal-to-noise ratio is

$$\mathrm{tSNR}_e(v) = \frac{\bar y_e(v)}{\sigma_e(v)},$$

the mean and standard deviation of the time course over all volumes (missing values
ignored). The weights and the combined series are

$$w_e(v) = \mathrm{tSNR}_e(v)\cdot TE_e,\qquad
S(v,t) = \frac{\sum_e w_e(v)\, y_e(v,t)}{\sum_e w_e(v)} .$$

The weights are constant in time and computed from the same data that are combined. The
output has the header and data type of the first echo.

## Known issues

* Voxels with zero temporal variance (e.g. masked background after reslicing) get
  infinite or undefined weights; their combined value can be NaN.
* The original implementation computed in-brain and out-of-brain masks (thresholds 0.25
  and 0.20 of the mean) that did not influence the result; the step no longer has these
  parameters.

## References

Poser BA, Versluis MJ, Hoogduin JM, Norris DG. BOLD contrast sensitivity enhancement and
artifact reduction with multiecho EPI: parallel-acquired inhomogeneity-desensitized fMRI.
Magn Reson Med 2006;55:1227-1235.
