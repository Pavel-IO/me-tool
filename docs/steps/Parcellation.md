# Parcellation

Region (ROI) time courses defined by an atlas or by a coarse voxel template, and the
functional connectivity matrix between the regions. The results are tab-separated text
files, readable in MATLAB (`metools.util.readTsv`, `readtable`) and Python
(`pandas.read_csv(f, sep='\t')`).

**Streams** reads `In` (`bold`, one file; normally bound to the cleaned unsmoothed data,
e.g. `In = 'bold_clean'`), optionally `Mask` (`brain_mask`) and `Covars` (`covars`);
writes `roi_timeseries`, `connectivity`, `roi_info` (see [Outputs](#outputs)).
**Functions** `parcellate`, `connectivityMatrix`, `resampleLike`; `metools.util.writeTsv`.

```matlab
pipe.Parcellation(In = 'bold_clean', Atlas = 'atlases/BN_Atlas_246_2mm.nii', ...
    Labels = 'atlases/BN_Atlas_246_LUT.txt', AtlasName = 'bna', ExcludeOutliers = true);
pipe.Parcellation(In = 'bold_clean', Atlas = 'atlases/brain_6mm.nii', AtlasType = 'voxels', ...
    AtlasName = 'grid6mm', SaveTimeseries = false);
```

## Parameters

| Parameter | Values (default) | Meaning |
|---|---|---|
| `Atlas` | NIfTI file (required) | atlas or template, any grid in the space of the data (MNI) |
| `AtlasType` | `'labels'`, `'voxels'` (**labels**) | integer labels, or every voxel > 0 is a ROI |
| `Labels` | text file (`''`) | ROI names, see [Names](#names) |
| `AtlasName` | letters/digits (`''` = atlas file name) | used in the file names |
| `Summary` | `'mean'`, `'eigen'` (**mean**) | ROI signal from its voxels |
| `Measure` | `'pearsonr'`, `'fisherz'` (**pearsonr**) | value in the connectivity matrix |
| `MinCoverage` | 0..1 (**0**) | ROIs with smaller coverage get `n/a` |
| `UseMask` | (**true**) | use only voxels in the brain mask (needs stream `brain_mask`) |
| `ExcludeOutliers` | (**false**) | leave censored scans out of the correlation (needs `covars`) |
| `SaveTimeseries` | (**true**) | write the time courses |
| `SaveConnectivity` | (**true**) | write the connectivity matrix |

The optional ports `Mask` and `Covars` are connected whenever their streams exist, but
their files are used only when `UseMask` / `ExcludeOutliers` say so. `UseMask = true`
without a `brain_mask` stream (or `ExcludeOutliers = true` without `covars`) is a static
error.

## Method

**Resampling direction.** The atlas is brought to the grid of the data, never the data to
the atlas: the label image is resampled with nearest-neighbour interpolation
(`resampleLike`, `Interp = 0`, float32, so labels are never mixed). Every data voxel gets
the label of the atlas voxel in which its centre lies. For an atlas coarser than the data
(a 6 mm template and 2.5 mm data, the sizes need not be multiples) a ROI then consists of
the 10-15 data voxels inside one template voxel, and its signal is their average, i.e.
the data are effectively averaged down to the template; no data value is interpolated.

**Voxel template** (`AtlasType = 'voxels'`): every voxel of the template with a value > 0
becomes a ROI, numbered in MATLAB (column-major) order; its name is its MNI coordinate
`x_y_z` (mm, rounded).

**Valid voxels.** A data voxel is used when it lies in the brain mask (`UseMask`) and its
time course is finite and not constant (this removes the area outside the field of view).

**Coverage** of a ROI = volume of its valid data voxels / volume of the ROI in the atlas
(capped at 1). ROIs with no valid voxel, or with coverage below `MinCoverage`, get `n/a`.
The default 0 keeps every ROI that has data; the coverage is written to the ROI table, so
a group-wide decision (e.g. drop ROIs covered < 50 % in any subject) can be made later.

**ROI signal** (`Summary`): `'mean'` = average of the valid voxels; `'eigen'` = first
principal component of the centred voxel time courses (as CONN's PCA option), sign chosen
to correlate positively with the mean, scaled to the RMS of the voxels (zero mean).

**Connectivity**: Pearson correlation between the ROI time courses over the used scans
(all scans, or without the scans marked `outlier` in `covars` when `ExcludeOutliers`);
`'fisherz'` gives $z = \operatorname{atanh}(r)$. The diagonal and the rows/columns of
excluded ROIs are `n/a`. For a proportional threshold the ranking of $r$ and $z$ is the
same.

## Names

`Labels` may be

* a BIDS `dseg.tsv` (tab-separated, columns `index` and `name`),
* lines `<label> <name>` (space, tab, comma or semicolon; trailing colour columns of a
  lookup table such as `1 A8m_L 255 0 0 0` are ignored),
* one name per line, line $i$ = label $i$.

Lines starting with `#` are skipped. Labels without a name are called `roi_<label>`.

## Outputs

`<in>` is the name of the input without `.nii`, e.g. `qwbc_bold`.

| Port (stream) | File | Content |
|---|---|---|
| `Timeseries` (`roi_timeseries`) | `<in>_atlas-<AtlasName>_timeseries.tsv` | scans x ROIs, header = ROI names; only with `SaveTimeseries` |
| `Connectivity` (`connectivity`) | `<in>_atlas-<AtlasName>_meas-<Measure>_relmat.tsv` | ROIs x ROIs, header = ROI names; only with `SaveConnectivity` |
| `Rois` (`roi_info`) | `<in>_atlas-<AtlasName>_rois.tsv` | per ROI: `index` (column in the other files), `label`, `name`, `atlas_voxels`, `grid_voxels` (data voxels with the label), `valid_voxels`, `coverage`, `x`, `y`, `z` (centroid, mm), `included` |
| | `<in>_atlas-<AtlasName>_parcellation.json` | the settings, input and mask files, number of scans, used scans, indices of the censored scans, METools version |

The naming follows the BIDS derivatives convention for time series and relation matrices
(`_timeseries.tsv`, `_relmat.tsv`). Missing values are `n/a`; numbers have 8 significant
digits. A 5000 x 5000 matrix is about 250 MB of text; set `SaveTimeseries = false` when
only the matrix is needed (or the reverse).

```python
import pandas as pd
r = pd.read_csv('qwbc_bold_atlas-bna_meas-pearsonr_relmat.tsv', sep='\t')
rois = pd.read_csv('qwbc_bold_atlas-bna_rois.tsv', sep='\t')
```

```matlab
[r, names] = metools.util.readTsv('qwbc_bold_atlas-bna_meas-pearsonr_relmat.tsv');
```

**QC** (with logging): number of ROIs, ROIs with data, median coverage.

## Known issues

* Atlas and data must be in the same space (MNI after Normalize); nothing checks it.
* The brain mask from [CreateMask](CreateMask.md) is at present most likely empty (see
  [TODO](../TODO.md)); the step then stops with an error. Use `UseMask = false` until it
  is fixed.

## References

Whitfield-Gabrieli S, Nieto-Castanon A. Conn: a functional connectivity toolbox for
correlated and anticorrelated brain networks. Brain Connect 2012;2:125-141.
BIDS Extension Proposal 17 (BEP017): Generic BIDS connectivity data schema.
