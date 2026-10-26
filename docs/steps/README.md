# Built-in fMRI steps

One page per step: what the step does scientifically, the model and its parameters, the
files it reads and writes, and known limitations. The pages describe the processing
functions in `metools.fmri.proc` that the steps call, so they also apply when the
functions are used on their own.

| Step | Page | Processing functions |
|---|---|---|
| Realign | [Realign.md](Realign.md) | `realign` |
| FieldMap | [FieldMap.md](FieldMap.md) | `fieldmapCorrect` |
| EchoCombination | [EchoCombination.md](EchoCombination.md) | `combineEchoesTsnr` |
| Retroicor | [Retroicor.md](Retroicor.md) | `readMarkers`, `readSliceTiming`, `retroicor`, `retroicorModel` |
| Normalize | [Normalize.md](Normalize.md) | `normalizeViaT1`, `skullStripCat12`, `resliceToResolution`, `coregister`, `segmentDeformation`, `applyDeformation` |
| CreateMask | [CreateMask.md](CreateMask.md) | `createBrainMask` |
| Smooth | [Smooth.md](Smooth.md) | `smooth` |
| NuisanceSignalRegression | [NuisanceSignalRegression.md](NuisanceSignalRegression.md) | `motionRegressors`, `framewiseDisplacement`, `maskSignal`, `compCor`, `resampleLike`, `readSignalByMask`, `highpassDetrend`, `outlierScans`, `dctFilterBasis`, `nuisanceDesign`, `regressOut` |
| Parcellation | [Parcellation.md](Parcellation.md) | `parcellate`, `resampleLike`, `connectivityMatrix` |

Notation: a 4D series has $N$ volumes acquired every $TR$ seconds; $y_v(t)$ is the time
course of voxel $v$. "DCT high-pass filter" means the SPM convention: the discrete cosine
basis $X_0$ = `spm_dctmtx(N, n)` with $n = \lfloor 2 N TR / 128 + 1 \rfloor$ columns
(cut-off period 128 s), whose first column is the constant term. Known issues are
collected in [../TODO.md](../TODO.md). Tables written by the steps are tab-separated text
with a header line and `n/a` for missing values (`metools.util.writeTsv`/`readTsv`).
