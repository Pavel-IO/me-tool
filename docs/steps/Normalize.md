# Normalize

Spatial normalisation of the functional data to MNI space through the subject's T1.

**Streams** reads `bold` (one file) and `bold_mean`; writes `bold` (`w<name>`),
`bold_mean` (`w<mean>`), `t1_coreg` (`r_t1.nii`, the T1 coregistered to the mean EPI).
**Parameters** `VoxelSize` ([2.5 2.5 2.5] mm), `CoregResolution` ([1 1 1] mm).
**Files** `<subject>/anat/_t1.nii`.
**Function** `metools.fmri.proc.normalizeViaT1(...)`; all intermediate files are in a
temporary folder.

## Method

**1. Brain extraction of the T1** (`skullStripCat12`). CAT12 segments the T1 (affine
registration to MNI, bias correction, adaptive maximum a posteriori segmentation with
partial volume estimation, skull stripping with graph cut, shooting registration). The
result used here is the native-space label image `p0`: the partial-volume tissue label of
every voxel (CSF = 1, GM = 2, WM = 3) with all non-brain tissue removed. It resembles the
EPI image (brain only) more than the full T1 does.

**2. Reslicing of the mean EPI** (`resliceToResolution`). The mean functional image is
resampled to 1 mm isotropic voxels in RAS orientation (trilinear interpolation, NIfTI
tools), giving the reference grid for coregistration.

**3. Coregistration** (`coregister`). A rigid-body transformation (6 parameters) that
aligns the brain label image to the resliced mean EPI is found by maximising the
normalised mutual information

$$\mathrm{NMI}(A,B) = \frac{H(A) + H(B)}{H(A,B)}$$

of the joint intensity histogram, optimised from coarse to fine sampling (8, 4, 2, 1 mm)
on images smoothed with a 5 mm histogram kernel. The same transformation is applied to the
full T1, which is resliced into the reference grid with 4th-degree B-splines: `r_t1.nii`,
the T1 in the space of the functional data.

**4. Segmentation and deformation** (`segmentDeformation`). SPM12 unified segmentation
(Ashburner & Friston 2005) of `r_t1.nii`: a generative model combining a mixture of
Gaussians (1, 1, 2, 3, 4, 2 Gaussians for GM, WM, CSF, bone, soft tissue, air), bias field
correction (regularisation 0.001, FWHM 60 mm) and a nonlinear registration of the tissue
probability maps (warping regularisation [0 0.001 0.5 0.05 0.2], MRF cleanup, sampling
3 mm). Only the forward deformation field $y$ (functional space → MNI) is kept.

**5. Writing** (`applyDeformation`). The deformation is applied to the mean image and to
every volume of the functional series, resampled with 4th-degree B-splines into a
bounding box of [-78 -112 -70; 78 76 85] mm with 2.5 mm voxels.

Because the T1 was first brought into the space of the EPI, a single deformation maps the
functional data directly to MNI; no separate EPI-to-T1 transformation has to be combined.

## Known issues

* The T1 processing (CAT12 and segmentation) is repeated for every session of a subject.
* The coregistration uses the CAT12 label image, not a skull-stripped T1 intensity image.
* The mean image is the realigned mean of the master echo before field-map correction
  (see [FieldMap](FieldMap.md)).

## References

Ashburner J, Friston KJ. Unified segmentation. NeuroImage 2005;26:839-851.
Studholme C, Hill DLG, Hawkes DJ. An overlap invariant entropy measure of 3D medical
image alignment. Pattern Recognit 1999;32:71-86.
Gaser C, Dahnke R, Thompson PM, et al. CAT: a computational anatomy toolbox for the
analysis of structural MRI data. GigaScience 2024;13:giae049.
