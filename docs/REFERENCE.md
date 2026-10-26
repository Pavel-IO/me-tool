# METools Reference

The complete description of what METools offers. For the idea and a first pipeline see
[GETTING_STARTED.md](GETTING_STARTED.md); for the internals see [DESIGN.md](DESIGN.md).

Contents: [Installation and layout](#installation-and-layout) ·
[Pipeline](#pipeline) · [FmriPipeline](#fmripipeline) · [Adding steps](#adding-steps) ·
[Streams and retention](#streams-and-retention) · [Validation](#validation) ·
[Running](#running) · [Logs and QC](#logs-and-qc) · [Participants](#participants) ·
[Configuration](#configuration) · [Built-in fMRI steps](#built-in-fmri-steps) ·
[Processing functions](#processing-functions) · [Writing steps](#writing-steps) · [Plan structure](#plan-structure) ·
[Error identifiers](#error-identifiers) · [Tests](#tests)

## Installation and layout

```
METools/
    setup_metools.m           adds lib/ and lib/thirdparty/nifti_tools to the path
    run_tests.m               runs the framework tests, writes test_report.txt
    lib/+metools/             generic core (package metools)
    lib/+metools/+util/       small general helpers (package metools.util)
    lib/+metools/+fmri/       fMRI pipeline, configuration and steps (package metools.fmri)
    lib/+metools/+fmri/+proc/ processing functions used by the steps (metools.fmri.proc)
    lib/thirdparty/           bundled third-party code (NIfTI tools, BSD license)
    docs/  tests/
```

`metools.version()` returns the version of METools (also printed by `runFor` and written
to the logs, together with the git commit when METools is a git repository).

Requirements: MATLAB R2021a or newer (name=value syntax; developed on R2023b), SPM12,
CAT12 for Normalize. In scripts:

```matlab
import metools.*        % Pipeline, Step, Port, Participants, Config, ...
import metools.fmri.*   % FmriPipeline, FmriConfig, StepRealign, ...
```

| Package | Classes |
|---|---|
| `metools` | `Pipeline`, `Step`, `Port`, `StreamEnv`, `Participants`, `Config`, `PlanFormatter`, `RunLog` |
| `metools.fmri` | `FmriPipeline`, `FmriConfig`, `PathsConfig`, `AcquisitionConfig`, `StepRealign`, `StepFieldMap`, `StepEchoCombination`, `StepRetroicor`, `StepNormalize`, `StepCreateMask`, `StepSmooth`, `StepNuisanceSignalRegression`, `StepParcellation` |
| `metools.fmri.proc` | processing functions, see [Processing functions](#processing-functions) |
| `metools.util` | helpers, see [Processing functions](#processing-functions) |

## Pipeline

`metools.Pipeline` is the generic core; domain pipelines (`FmriPipeline`) derive from it.

### Constructor

```matlab
pipe = FmriPipeline(name, cfg, Input = files)
```

| Argument | Meaning |
|---|---|
| `name` | name of the pipeline, used in messages and log file names (default `'pipeline'`) |
| `cfg` | configuration object (`FmriConfig`), may be `[]`; shared by reference, not copied |
| `Input` | raw input files. A cellstr, string or char is the stream `bold`; a struct gives several streams, e.g. `struct('bold', {{'a.nii'}}, 'rp', 'rp.txt')`. Relative names are resolved against the session folder of each subject; absolute names are used as they are. |

`pipe.setInput(files)` replaces the inputs later.

### Properties

| Property | Access | Meaning |
|---|---|---|
| `Name` | read/write | name of the pipeline |
| `Config` | read/write | configuration object |
| `Steps` | read | cell array of the steps; `pipe.Steps{3}.FWHM = 8` changes a parameter |
| `Inputs` | read | input streams (struct: stream -> cellstr) |
| `RetainAll`, `RetainList` | read | the retention setting (see `Retain`) |
| `LogDir` | read/write | folder of the summary log; `''` (default) = no logs. Relative = inside the project folder of the participants. See [Logs and QC](#logs-and-qc). |
| `LogConsole` | read/write | with logs: `'quiet'` (default) shows only the progress in the console, `'full'` also prints the captured output after every step |

### Methods

| Method | Meaning |
|---|---|
| `step = pipe.add(step, name, value, ...)` | appends a step (any `metools.Step`); see [Adding steps](#adding-steps) |
| `n = pipe.numSteps()` | number of steps |
| `pipe.Retain(stream, ...)` | streams whose latest version is kept; everything else is deleted after its last use. `pipe.Retain('all')` deletes nothing (the default). Accepts several names or a cell array. |
| `cp = pipe.copy(newName)` | deep copy: the steps are copied, the configuration is shared; keeps the class (`FmriPipeline` stays `FmriPipeline`) |
| `pipe.describe()` | prints the plan and the validation result; `plan = pipe.describe()` also returns the plan |
| `plan = pipe.validate()` | prints warnings, throws `Pipeline:Invalid` when there are errors |
| `plan = pipe.compile(inputs, ctx)` | the symbolic plan (see [Plan structure](#plan-structure)); both arguments optional |
| `[ok, problems] = pipe.dryRun(P, Session = s)` | checks the pipeline against the data without computing, see [Validation](#validation) |
| `report = pipe.runFor(P, Session = s, ...)` | runs the pipeline, see [Running](#running) |
| `info = pipe.environmentInfo()` | software versions printed and logged (MATLAB; `FmriPipeline` adds SPM and CAT12) |
| `problems = metools.Pipeline.checkCollisions(pipes, P, Session = s)` | static: pipelines (array or cell) that would write the same file from different steps or parameters |

## FmriPipeline

`metools.fmri.FmriPipeline` adds one method per built-in step. Each call is a shortcut for
`pipe.add(StepXxx(), ...)` and returns the added step:

`Realign`, `FieldMap`, `EchoCombination`, `Retroicor`, `Normalize`, `CreateMask`,
`Smooth`, `NuisanceSignalRegression`, `Parcellation`.

## Adding steps

```matlab
pipe.Smooth(FWHM = 8, Prefix = 's8', Out = 'bold_smooth8', Keep = 'bold_smooth8');
pipe.add(MyStep(), 'Lambda', 0.5);               % own step, positional pairs work too
```

The name/value pairs of `add` (and of the shortcuts) can be:

* **parameters** - the public properties of the step; validated on assignment
  (`Step:BadValue`). An unknown name is `Step:UnknownOption`, and the message lists the
  valid names.
* **port overrides** - the name of a port and a stream name: `In = 'bold_smooth'` makes
  the port read (or write) that stream instead of its default.
* **`Keep`** - a stream name or a list of them; the files this step writes to those
  streams are never deleted by `Retain`. It must name a stream the step writes.

Parameters can also be changed after adding: `s = pipe.Smooth(); s.FWHM = 4;`.

## Streams and retention

A stream is a named category of files. Every step that writes to a stream creates a new
version; a step reading a stream always gets its latest version. Names must be valid
MATLAB identifiers. Names used by the built-in steps:

| Stream | Content |
|---|---|
| `bold` | the functional data being processed (one file per echo, or one combined file) |
| `bold_mean` | mean image of the functional data |
| `bold_smooth` | smoothed functional data (and its cleaned version after NuisanceSignalRegression) |
| `bold_clean` | not written by default; the usual name for cleaned unsmoothed data (`NuisanceSignalRegression(Target = 'bold', Out = 'bold_clean')`) |
| `rp` | realignment parameters |
| `brain_mask` | brain mask |
| `t1_coreg` | T1 coregistered to the mean image |
| `covars` | per-scan confounds of NuisanceSignalRegression: FD, outlier flag, tissue signals (TSV) |
| `design_matrix` | design matrix of the nuisance regression, named columns (TSV) |
| `roi_timeseries` | ROI time courses (Parcellation, TSV) |
| `connectivity` | ROI x ROI connectivity matrix (Parcellation, TSV) |
| `roi_info` | ROI table (TSV) and settings (JSON) of Parcellation |

Retention rules: without `Retain` nothing is deleted. With `Retain`, the latest version of
each listed stream is kept, as are the files of `Keep` streams and all raw inputs; every
other file is deleted right after the last step that reads it (a file passed through
unchanged by a step counts as needed by both versions). A step output that nobody reads
and that is not retained is deleted right after the step, with a warning at validation.
With `EndStep`, files still needed by the skipped later steps are kept.

## Validation

**Static** (`describe`, `validate`, also before every run; no data needed):

| Check | Result |
|---|---|
| a port reads a stream that nobody produces and that is not an input | error |
| number of files does not match the port (`one`: exactly 1, `many`: at least 2) | error |
| a parameter bound to the configuration is empty in both places | error |
| step-specific check fails (e.g. number of `TEs` vs. echoes, `Master` > number of files) | error |
| `predict` fails or returns an invalid structure | error |
| two steps (or two outputs) write the same file; a step would overwrite a raw input | error |
| `Retain` names an unknown stream; `Keep` names a stream the step does not write | error |
| a step changes stream S while another stream derived from S becomes stale | warning |
| an output is never read and not retained | warning |

After an error, the outputs of the failing step are marked unavailable and dependent
steps are reported as skipped instead of producing further errors.

**`dryRun(P, Session = s)`** prints the SPM/CAT versions, then for the static plan and
every subject: the per-subject plan with absolute paths, existence of the raw inputs,
existence of the external files of every step (`externalFiles`, e.g. field maps,
`markers.csv`, T1), and whether the functions listed by `requiredFunctions` are on the
path. It returns `ok` and the list of problems and prints them.

**At run time**, for every step: all input files exist; outputs left from an earlier run
are deleted before the step; after the step every declared output exists; files that
appeared in the input/output folders but were not declared are reported as a warning.

**Between pipelines**: `metools.Pipeline.checkCollisions([a b], P, Session = 'rest')`.

## Running

```matlab
report = pipe.runFor(P, Session = 'rest', StartStep = 1, EndStep = Inf, ContinueOnError = true);
```

| Option | Default | Meaning |
|---|---|---|
| `Session` | required | session to process, e.g. `'rest'` (folder name under each subject) |
| `StartStep` | 1 | steps before it are skipped; their outputs must exist |
| `EndStep` | last step | steps after it are skipped |
| `ContinueOnError` | `true` | a failed subject is reported and the next one runs; `false` throws `Pipeline:RunFailed` |

Every run computes the selected steps again. The `report` table has one row per subject
and step: `Subject`, `Session`, `Step` (index), `Name`, `Status` (`ok`, `failed`,
`skipped`), `Seconds`, `Message` (error message or warnings). A plan that is invalid for a
subject gives one row with `Step = 0` and `Name = 'plan'`. A summary of the failures is
printed at the end. Logging is a setting of the pipeline (`LogDir`, `LogConsole`), so it
is copied with `copy` and does not have to be repeated at every call.

## Logs and QC

```matlab
pipe.LogDir = 'logs';          % g:/Data/MyStudy/logs for a project in g:/Data/MyStudy
pipe.LogConsole = 'quiet';     % default
```

With `LogDir` set, `runFor` writes:

| File | Content |
|---|---|
| `<LogDir>/<pipeline>_<session>_<time>.html` | summary: start and end, software versions, the calling script (with its source and git version when available), status matrix subjects x steps with links, failures, plan, configuration |
| `<subject>/logs/<pipeline>_<session>_<time>/log.html` | detailed log of one subject: every step with its parameters, input and output files, warnings, the error with stack trace, QC items, and the console output |
| `.../NN_<Step>.txt` | the complete console output of step NN (everything SPM/CAT print), also kept for successful steps |
| `.../qc/` | folder for QC figures written by the steps |

The files are rewritten after every step, so a crash or Ctrl+C leaves a valid log. The
console output is captured with `evalc`; graphics windows opened by SPM are not affected.

**QC**: after a successful step, when logging is on, the framework calls the step's
`qc(in, out, ctx)`. It returns a struct array (or a cell of structs) with a `Title` and
one of `Image` (path to a figure, typically in `ctx.QcDir`), `Value` (number or text, shown
in a table) or `Text` (shown as a block). An error inside `qc` is only a warning. Built-in
QC: `Realign` (motion plot, maximal translation and rotation, mean framewise
displacement, number of volumes with FD > 0.5 mm) and `Retroicor` (its control figures).

## Participants

```matlab
P = metools.Participants(projectDir, subjects);
P.add({'sub-03', 'sub-04'});
```

| Member | Meaning |
|---|---|
| `ProjectDir`, `Subjects` | read only |
| `DataFolder` (`'data'`), `FieldsFolder` (`'fields'`), `LogsFolder` (`'logs'`), `OutputsFolder` (`'outputs'`) | folder names, can be changed |
| `subjectDir(s)`, `sessionDir(s, session)`, `fieldsDir(s)`, `logsDir(s)`, `outputsDir()` | folders |
| `units(session)` | the units (subject x session) processed by `runFor` |
| `ctx = context(s, session, cfg)` | the context passed to the steps |

The context `ctx` has the fields `Subject`, `Session`, `ProjectDir`, `SubjectDir`,
`SessionDir`, `FieldsDir`, `OutputsDir`, `Cfg` (configuration with the session overrides
applied), `LogDir` and `QcDir` (empty when logging is off).

## Configuration

`metools.Config` is the base class; `metools.fmri.FmriConfig` adds the sections:

| Path | Type | Used by |
|---|---|---|
| `paths.project` | text | `Participants` (by the user script) |
| `paths.masks` | text | NuisanceSignalRegression (`MasksDir`) |
| `acq.TR` | positive scalar, s | Retroicor, NuisanceSignalRegression |
| `acq.TEs` | positive vector, ms | EchoCombination |

| Method | Meaning |
|---|---|
| `v = cfg.getValue('acq.TR')`, `cfg.setValue('acq.TR', 0.8)` | access by path (`Config:BadPath` for an unknown path) |
| `cfg.addOverride(session, path, value)` | the value used for that session only; validated immediately |
| `c = cfg.forSession(session)` | copy with the session overrides applied (done automatically for every unit) |
| `lines = cfg.describe()` | all values as text (used by the logs) |
| `c = copy(cfg)` | deep copy |

Precedence for a step parameter: explicit value > session override > study value > the
default of the step.

## Built-in fMRI steps

Shortcuts on `FmriPipeline`; class names `metools.fmri.Step<Name>`. "follows" means the
output is a new version of the stream read by the given port. The scientific description
of every step is in [steps/](steps/README.md).

| Step | Ports (default stream) | Parameters (default) |
|---|---|---|
| `Realign` | in `In` (bold); out `Out` follows In, `Mean` (bold_mean), `Rp` (rp) | `Master` (2) index of the reference file, `Unwarp` (false; `true` is not implemented) |
| `FieldMap` | in `In` (bold); out `Out` follows In | `Master` (2), `FieldmapTEs` ([5.29 7.75] ms), `TotalReadoutTime` (20.8 ms), `BlipDirection` (1), `PhaseEncodingDir` (2 = y) |
| `EchoCombination` | in `In` (bold); out `Out` follows In (`c_bold.nii`; one input file is passed through) | `TEs` (cfg `acq.TEs`) |
| `Retroicor` | in `In` (bold); out `Out` follows In | `TR` (cfg `acq.TR`) |
| `Normalize` | in `In` (bold, 1 file), `Mean` (bold_mean, 1 file); out `Out` follows In, `MeanOut` follows Mean, `T1Reg` (t1_coreg) | `VoxelSize` ([2.5 2.5 2.5]), `CoregResolution` ([1 1 1]) |
| `CreateMask` | in `In` (bold, 1 file); out `Mask` (brain_mask) | `Threshold` (0.8), `Suffix` ('_mask8') |
| `Smooth` | in `In` (bold); out `Out` (bold_smooth) | `FWHM` (6), `Prefix` ('s') |
| `NuisanceSignalRegression` | in `Signal` (bold), `Target` (bold), `Mean` (bold_mean), `Rp` (rp), each 1 file; out `Out` follows Target, `Covars` (covars, `<out>_covars.tsv`), `Design` (design_matrix, `<out>_design.tsv`) | `MotionModel` (24; 0/6/12/24), `FdMethod` ('power'; 'legacy'), `FdRegressor` (false), `TissueSignals` ('acompcor'; 'mean', 'none'), `CompCorComponents` (5), `Band` ([1/128 Inf] Hz), `ScrubFd` ([] mm), `ScrubNeighbors` ([0 0]), `CensorInterp` ('pchip'), `MasksDir` (cfg `paths.masks`), `TR` (cfg `acq.TR`), `CsfMask` ('CSFmaskVENTlat.nii'), `WmMask` ('WM09.nii'), `Prefix` ('q'), `CovarsName`, `DesignName` ('' = derived) |
| `Parcellation` | in `In` (bold, 1 file), optional `Mask` (brain_mask), `Covars` (covars); out `Timeseries` (roi_timeseries, optional), `Connectivity` (connectivity, optional), `Rois` (roi_info: `_rois.tsv` + `_parcellation.json`) | `Atlas` (required), `AtlasType` ('labels'; 'voxels'), `Labels` (''), `AtlasName` ('' = atlas file name), `Summary` ('mean'; 'eigen'), `Measure` ('pearsonr'; 'fisherz'), `MinCoverage` (0), `UseMask` (true), `ExcludeOutliers` (false), `SaveTimeseries` (true), `SaveConnectivity` (true) |

External files checked by `dryRun`: FieldMap `<subject>/fields/_phasediff.nii` and
`_magnitude1.nii`; Retroicor `<session>/markers.csv` and `acq_params.json`; Normalize
`<subject>/anat/_t1.nii`; NuisanceSignalRegression the two masks in `MasksDir` (unless
`TissueSignals = 'none'`); Parcellation the atlas and the labels file.

Notes: Normalize works in a temporary folder and writes nothing to `anat`; FieldMap
processes the field map in a temporary folder as well. The scientific description of every
step is in [steps/](steps/README.md); known issues are in [TODO.md](TODO.md).
`Unwarp = true` in Realign is not implemented. FieldMap does not update `bold_mean`.

## Processing functions

The steps only connect streams to plain functions that do the work. These functions take
file names (char or string), numbers and structs, so they can be used in any script
without the pipeline. Intermediate files are written to a temporary folder that is
removed when the function ends. Options are name=value pairs.

**`metools.fmri.proc`**

| Function | Purpose |
|---|---|
| `realign(master, others)` | SPM realignment of the master, other series resliced with its matrices; writes `r*`, `mean*`, `rp_*.txt` |
| `fieldmapCorrect(phaseDiff, magnitude, master, others, EchoTimes=[5.29 7.75], TotalReadoutTime=20.8, BlipDirection=1, PhaseEncodingDir=2)` | field map distortion correction (SPM FieldMap); writes `u*` |
| `combineEchoesTsnr(echoes, TEs, outFile)` | tSNR x TE weighted echo combination |
| `markers = readMarkers(file, Verbose=false)` | ECG, respiration and scan markers (s) from a BrainVision marker export |
| `st = readSliceTiming(jsonFile)` | `SliceTiming` from a JSON sidecar |
| `retroicor(bold, outFile, markers, sliceTiming, TR, FigureFile='')` | RETROICOR correction of a 4D file, optional control figure |
| `[corr, pEcg, pResp] = retroicorModel(data, TR, markers, sliceTiming, ComputeStats=false)` | the same on a 4D array in memory |
| `skullStripCat12(t1, outFile)` | brain-only T1 from CAT12 (runs on a copy in a temporary folder) |
| `resliced = coregister(ref, source, others, Prefix='r')` | SPM coregistration (NMI) with reslicing |
| `resliceToResolution(inFile, outFile, voxelSize)` | reslicing to a voxel size (`reslice_nii`) |
| `[y, iy] = segmentDeformation(image, Inverse=false)` | SPM12 segmentation, returns the deformation field |
| `applyDeformation(y, files, voxelSize, Prefix='w', BoundingBox=..., Interp=4)` | normalization with a deformation field |
| `normalizeViaT1(t1, mean, bold, t1CoregFile, VoxelSize=[2.5 2.5 2.5], CoregResolution=[1 1 1])` | the whole normalization of the Normalize step |
| `createBrainMask(inFile, outFile, threshold)` | intensity mask as in SPM's `spm_spm` |
| `smooth(inFile, outFile, fwhm)` | Gaussian smoothing; `outFile` may equal `inFile` |
| `resampleLike(ref, src, outFile, Interp=[], DataType='')` | resampling of `src` to the grid of `ref` (`[]`/`''` = spm_imcalc defaults; `Interp = 0` nearest neighbour for labels) |
| `Y = readSignalByMask(fmri, mask)` | voxel time courses inside a mask (scans x voxels) |
| `y = highpassDetrend(signal, TR, Cutoff=128)` | linear detrend + DCT high-pass filter |
| `sig = maskSignal(fmri, ref, mask, TR, Cutoff=128)` | mean detrended signal of a region |
| `[c, explained] = compCor(fmri, ref, mask, TR, k, Cutoff=128)` | aCompCor: first k principal components of a region |
| `[R, names] = motionRegressors(rp, model)` | motion regressors, model 0/6/12/24; `rp` matrix or file |
| `R = motionRegressors24(rpFile)` | Friston 24-parameter motion model (= `motionRegressors(rp, 24)`) |
| `fd = framewiseDisplacement(rp, RotationUnits='radians', Radius=50, Detrend=false)` | framewise displacement (Power 2012) |
| `out = outlierScans(fd, threshold, Before=0, After=0)` | censored scans (logical) |
| `[X0, names] = dctFilterBasis(N, TR, band)` | DCT basis of a band-pass filter (constant, high-pass and low-pass cosines) |
| `[X, names, c, lp] = nuisanceDesign(R, names, TR, Band=[1/128 Inf])` | design matrix: filtered regressors and filter basis; `c` constant column, `lp` low-pass columns |
| `regressOut(fmri, outFile, X, Keep=[], Censored=[], LowPass=[], Interp='pchip')` | removes the fit of X from every voxel (keeps the fit of the `Keep` columns); with censored scans: fit on the uncensored scans, interpolation, then the `LowPass` columns |
| `X = nuisanceRegression(fmri, outFile, motion, signals, TR, Cutoff=128)` | the original Cosmic2 regression (motion, FD, region signals, high-pass) |
| `res = parcellate(fmri, atlas, AtlasType='labels', Labels='', Mask='', Summary='mean', MinCoverage=0)` | ROI time courses, coverage and names |
| `M = connectivityMatrix(ts, Measure='pearsonr')` | correlation matrix of ROI time courses (`'fisherz'` = atanh) |

**`metools.util`**: `addPrefix(files, prefix, suffix='')`, `scanCount(file)`,
`writeTsv(file, header, data, Precision=8)`, `[data, header] = readTsv(file)` (tab-separated
tables, `n/a` = NaN),
`volumeList(file)` (`{'f.nii,1'; ...}`), `writeVol4d(header, data, file)`,
`runSpmBatch(matlabbatch)`, `[folder, cleanup] = tempFolder()`, `ensureFolder(folder)`.

Every function has a help text (`help metools.fmri.proc.retroicor`).

## Writing steps

A step is a subclass of `metools.Step`. It can live anywhere on the path (e.g. in the
project folder) and is added with `pipe.add(MyStep(), ...)`.

| Member | Required | Meaning |
|---|---|---|
| public properties | - | the parameters; use validators and defaults |
| `p = ports(obj)` | yes | struct of ports: `metools.Port.input(stream, 'Cardinality', 'any'/'one'/'many', 'Optional', tf)`, `metools.Port.output(stream)` or `metools.Port.output('', 'Follows', 'InPortName')` |
| `out = predict(obj, in, ctx)` | yes | struct with one field per output port: the file names. `in` has one field per input port (cellstr; empty for a missing optional port). `ctx` is empty during static validation. |
| `execute(obj, in, out, ctx)` | yes | does the work; must create every file named in `out` |
| `msgs = check(obj, in, cfg)` | no | step-specific static checks; returns a cellstr of problems |
| `files = externalFiles(obj, ctx)` | no | files outside the streams that must exist (checked by `dryRun`) |
| `names = requiredFunctions(obj)` | no | functions that must be on the path (checked by `dryRun`) |
| `b = configBindings(obj)` | no | struct: parameter -> configuration path; `obj.resolve('TR', cfg)` returns the explicit value or the configured one |
| `items = qc(obj, in, out, ctx)` | no | QC items, see [Logs and QC](#logs-and-qc) |
| `s = signature(obj)` | no | identity used by `checkCollisions` (default: class and parameters) |

Helpers: `metools.Step.addPrefix(files, prefix)`; `step.Name` is the class name without
package and without the `Step` prefix.

## Plan structure

`plan = pipe.compile()` returns a struct: `Name`, `Inputs`, `Steps` (per step: `index`,
`name`, `params`, `status` (`ok`/`error`/`skipped`), `reads`, `writes`, `in`, `out`),
`Versions` (every stream version: `id`, `stream`, `port`, `step`, `files`, `parents`,
`ancestors`, `sig`), `Env` (the stream environment after the last step), `RetainAll`,
`RetainList`, `DeleteAfter` (files deleted after each step), `FreeAfter` (versions released
after each step), `Errors`, `Warnings`, `Ok`.

## Error identifiers

| Identifier | When |
|---|---|
| `Pipeline:Invalid` | `validate` found errors |
| `Pipeline:BadStep` | `add` got something that is not a `metools.Step` |
| `Pipeline:BadRetain` | `Retain` without names or with a non-text name |
| `Pipeline:NoSession` | `dryRun`/`runFor` without `Session` |
| `Pipeline:BadRange` | invalid `StartStep`/`EndStep` |
| `Pipeline:RunFailed` | a unit failed with `ContinueOnError = false` |
| `Pipeline:MissingInput`, `Pipeline:MissingOutput`, `Pipeline:StaleOutput` | run-time file checks (reported in the `report`) |
| `Step:BadArguments`, `Step:BadValue`, `Step:UnknownOption`, `Step:BadBinding`, `Step:BadKeep`, `Step:BadPorts` | options of `add` and port declarations |
| `Port:BadStream`, `Port:BadFollows`, `Port:BadOptions`, `Port:BadArgument` | port declarations |
| `StreamEnv:BadFiles`, `StreamEnv:BadStream`, `StreamEnv:Missing` | invalid inputs or streams |
| `Config:BadPath`, `Config:BadSession`, `PathsConfig:BadValue` | configuration |
| `Participants:BadSubject`, `Participants:BadPath` | participants |

## Tests

`run_tests` runs every test in `tests/` and writes `test_report.txt`. The steps in
`tests/+fake` only create empty files, so the tests need neither SPM nor data. A new
framework feature should come with a test there.
