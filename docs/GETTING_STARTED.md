# Getting Started with METools

METools is a MATLAB framework for assembling fMRI preprocessing pipelines declaratively.
A complete multi-step pipeline fits in about 50 lines: you list the steps, the framework
connects them, validates the whole thing before touching any data, and then runs it for
every subject. Requires MATLAB R2021a or newer (developed on R2023b), SPM12, and CAT12
for the Normalize step.

This document explains the idea and the everyday usage. Every option of every class is
described in the [Reference](REFERENCE.md); what each step does scientifically (model,
parameters, files, limitations) is described on its own page in [steps/](steps/README.md).
The internals are described in [DESIGN.md](DESIGN.md), open issues in [TODO.md](TODO.md).

## 1. The idea in one minute

Classic preprocessing scripts hard-code file names: step 3 reads `ur_echo_1.nii` because
step 2 happens to write it. Change the order or drop a step and everything breaks.

In METools a step never mentions another step or a file name. Instead:

* Data flows through named **streams** (`bold`, `bold_mean`, `rp`, ...). A stream is a
  category of files, not a single file.
* Every step declares which streams it **reads** and which it **writes**.
* Every write creates a new, immutable **version** of a stream. A step always reads the
  **latest version** of the stream it is connected to.
* The step can **predict** the names of its outputs from its inputs (`bold` becomes
  `bold` with prefix `r`). So the whole pipeline, including all file names, can be
  worked out *without running anything*. That is what makes static validation and
  `dryRun` possible.

The result: you add, remove or reorder steps in one line, and the framework tells you
immediately (not after a six hour run) whether the pipeline makes sense.

Three things are deliberately separate:

| Object | Responsibility |
|---|---|
| `FmriPipeline` | the assembly of steps and the flow of streams. Knows no subjects and no paths. |
| `Participants` | subjects, folder layout, per-subject context. |
| `FmriConfig` | study-wide values: TR, echo times, masks folder. |

The classes live in the package `metools` (generic core) and `metools.fmri` (the fMRI
pipeline, its configuration and steps). Scripts start with `import metools.*` and
`import metools.fmri.*` so that the short names can be used.

## 2. A first pipeline

```matlab
setup_metools                                  % adds METools to the MATLAB path (once)
import metools.*
import metools.fmri.*

cfg = FmriConfig();
cfg.paths.project = 'g:/Data/Cosmic2';
cfg.paths.masks   = 'g:/Data/Cosmic/masks/CSF_WM';
cfg.acq.TR  = 0.851;
cfg.acq.TEs = [15 36 58];

participants = Participants(cfg.paths.project, {'sub-907C', 'sub-925C'});

pipe = FmriPipeline('rest', cfg, Input = {'_echo_1.nii', '_echo_2.nii', '_echo_3.nii'});
pipe.Realign(Master = 2, Unwarp = false, Keep = 'bold_mean');
pipe.FieldMap();
pipe.EchoCombination();
pipe.Retroicor();
pipe.Normalize();
pipe.CreateMask(Threshold = 0.8);
pipe.Smooth(FWHM = 6);
pipe.NuisanceSignalRegression(Target = 'bold_smooth');
pipe.Retain('bold', 'bold_smooth', 'bold_mean', 'rp', 'brain_mask', ...
            'covars', 'design_matrix', 't1_coreg');

pipe.describe();                                       % the plan; nothing is computed
pipe.dryRun(participants, Session = 'rest');           % checks against the real data
pipe.LogDir = 'logs';                                  % HTML logs (optional)
report = pipe.runFor(participants, Session = 'rest');  % runs it
```

Reading it top to bottom:

* `Input` names the raw files (a cell array = stream `bold`). Relative names are
  resolved against the session folder of each subject.
* Each `pipe.<Step>(...)` line appends a step. Name=value pairs set the parameters of the
  step. A parameter left out takes its default, or the value from `FmriConfig` when the
  step has a config binding (TR, TEs, masks folder).
* Your own step (any subclass of `metools.Step`) is added with
  `pipe.add(MyStep(), Param = value)`; built-in steps are just shortcuts for `add`.
* `Retain` says which streams are results. Everything else is deleted as soon as no later
  step needs it (see section 6).

## 3. Streams and what each step reads and writes

The steps shipped with METools, in the order of the example above:

| # | Step | Reads (port: stream) | Writes (port: stream) | Output file names |
|---|---|---|---|---|
| 1 | `Realign` | `In`: bold | `Out`: bold (same stream), `Mean`: bold_mean, `Rp`: rp | `r<name>`, `mean<name of master>`, `rp_<master>.txt` |
| 2 | `FieldMap` | `In`: bold | `Out`: bold | `u<name>` |
| 3 | `EchoCombination` | `In`: bold (all echoes) | `Out`: bold (one file) | `c_bold.nii` |
| 4 | `Retroicor` | `In`: bold | `Out`: bold | `b<name>` |
| 5 | `Normalize` | `In`: bold (one file), `Mean`: bold_mean (one file) | `Out`: bold, `MeanOut`: bold_mean, `T1Reg`: t1_coreg | `w<name>`, `w<mean>`, `r_t1.nii` |
| 6 | `CreateMask` | `In`: bold (one file) | `Mask`: brain_mask | `<name>_mask8.nii` |
| 7 | `Smooth` | `In`: bold | `Out`: bold_smooth | `s<name>` |
| 8 | `NuisanceSignalRegression` | `Signal`: bold, `Target`: bold (override: bold_smooth), `Mean`: bold_mean, `Rp`: rp | `Out`: Target stream, `Covars`: covars, `Design`: design_matrix | `q<name>`, `q<name>_covars.tsv`, `q<name>_design.tsv` |
| 9 | `Parcellation` | `In`: bold (override: e.g. bold_clean), optional `Mask`: brain_mask, `Covars`: covars | `Timeseries`: roi_timeseries, `Connectivity`: connectivity, `Rois`: roi_info | `<name>_atlas-<AtlasName>_timeseries.tsv`, `..._meas-pearsonr_relmat.tsv`, `..._rois.tsv`, `..._parcellation.json` |

"Same stream" means the step *follows* its input: it writes a new version into the stream
it just read. After `Realign`, `bold` points to `r_echo_*.nii`; after `Retroicor` it points
to `bc_bold.nii`, and so on. A step that writes to a *different* stream (`Smooth` writes
`bold_smooth`) leaves `bold` alone, so later steps can still use the unsmoothed data.

What the stream `bold` contains at each point of the example:

| After step | `bold` | `bold_mean` | other streams |
|---|---|---|---|
| input | `_echo_1..3.nii` | | |
| 1 Realign | `r_echo_1..3.nii` | `mean_echo_2.nii` | `rp` |
| 2 FieldMap | `ur_echo_1..3.nii` | | |
| 3 EchoCombination | `c_bold.nii` | | |
| 4 Retroicor | `bc_bold.nii` | | |
| 5 Normalize | `wbc_bold.nii` | `wmean_echo_2.nii` | `t1_coreg` |
| 6 CreateMask | | | `brain_mask` |
| 7 Smooth | | | `bold_smooth` = `swbc_bold.nii` |
| 8 Nuisance | | | `bold_smooth` = `qswbc_bold.nii`, `covars`, `design_matrix` |

(The names assume the inputs of the example; `describe()` shows the real ones.)

What the nuisance regression contains (motion model, aCompCor or mean signals, band-pass,
censoring) is set by its parameters; the defaults and the setting that reproduces the
original Cosmic2 regression are on its page [steps/NuisanceSignalRegression.md](steps/NuisanceSignalRegression.md).
Step tables (confounds, design matrix, ROI time courses, connectivity) are tab-separated
text files, readable from MATLAB and Python.

### Redirecting a step to another stream

Every port can be redirected by name. This is how branching works:

```matlab
pipe.NuisanceSignalRegression(Target = 'bold_smooth');   % clean the smoothed data
pipe.Smooth(In = 'bold', Out = 'bold_smooth_8', FWHM = 8);  % a second smoothing variant
```

A connectivity branch next to the voxel-wise one: clean the unsmoothed data into a new
stream and parcellate it.

```matlab
pipe.NuisanceSignalRegression(Target = 'bold', Out = 'bold_clean', ...
    MotionModel = 12, TissueSignals = 'acompcor', Band = [0.008 0.09], ScrubFd = 0.5);
pipe.Parcellation(In = 'bold_clean', Atlas = 'atlases/BN_Atlas_246_2mm.nii', AtlasName = 'bna', ...
    ExcludeOutliers = true);
```

A step that reads a stream nobody has produced, or that is given the wrong number of
files, is an error found at assembly time.

## 4. Looking at the plan: `describe`

`pipe.describe()` prints one row per step with what it reads, what it writes, which files
are freed after the step, the parameters, and the validation result:

```
Pipeline 'rest'   steps: 8   inputs: bold
 #  step             reads            writes                       freed after step
 1  Realign          bold <- input    bold -> r_echo_1.nii (x3)    -
                                      bold_mean -> mean_echo_2.nii
                                      rp -> rp__echo_2.txt
 ...
Retain: bold, bold_smooth, bold_mean, rp, brain_mask, covars, design_matrix, t1_coreg
Validation: OK, errors: 0, warnings: 0
```

(The layout is illustrative; the exact columns come from `PlanFormatter`.) Errors and
warnings are listed under the table. `pipe.validate()` does the same check and throws
`Pipeline:Invalid` when there is an error, which is useful at the top of a script.

## 5. Validation: three levels

1. **Static** (`describe`, `validate`; no data needed). Missing streams, wrong number of
   files for a port, a step-specific check (e.g. number of `TEs` vs. number of echoes),
   a parameter bound to the config that is not set, two steps that would write the same
   file, a step that would overwrite a raw input, unknown stream in `Retain` or `Keep`.
   Warnings: an output that nobody uses and is not retained, a *stale branch* (a stream
   derived from a version of `bold` that a later step has since replaced).
2. **`dryRun`** (needs `Participants`). Everything above for every subject with the real
   paths, plus: do the raw input files exist, do the external files of each step exist
   (fieldmaps, `markers.csv`, T1), are the MATLAB functions the steps call on the path.
   It also prints the SPM and CAT12 versions. Nothing is computed.
3. **At run time.** Before a step: its inputs exist, and stale outputs of an earlier run
   are removed. After a step: every declared output exists, and files created but not
   declared are reported as a warning (SPM likes to create files implicitly).

Comparing pipelines that run on the same data:

```matlab
problems = metools.Pipeline.checkCollisions([pipeA pipeB], participants, Session = 'rest');
```

reports two pipelines that write the same file from different steps or parameters (for
example two smoothing variants with the same prefix). Identical copies are fine.

## 6. Running, logs and deleting intermediate files

`report = pipe.runFor(participants, Session = 'rest')` runs the pipeline for every subject.
Each subject runs in its own `try/catch`: a failure is recorded and the next subject goes
on (`ContinueOnError = false` stops at the first failure). The result is a table with the
columns Subject, Session, Step, Name, Status (`ok`, `failed`, `skipped`), Seconds, Message.
`StartStep = k` and `EndStep = m` run only a part of the pipeline, which is handy while
developing or after fixing a failed subject (the outputs of the skipped steps must exist).

With `pipe.LogDir = 'logs'` the run writes HTML logs that open in any browser: a summary
of the whole run in `LogDir` (a relative folder is placed in the project folder, an
absolute one is used as it is) and a detailed log for every subject in
`<subject>/logs/`. The detailed log holds the console output of each step (including
everything SPM prints, also saved as text files) and the quality-control figures of the
steps that provide them. The console then shows only the progress
(`pipe.LogConsole = 'full'` prints the captured output as well).

By default nothing is deleted. `Retain` turns on cleanup:

* `pipe.Retain('bold', 'bold_smooth', ...)` keeps the **latest version** of the listed
  streams. Every other file is deleted right after the last step that needs it.
* Raw inputs are never deleted. A pass-through file (a step that outputs its input
  unchanged, e.g. `EchoCombination` on one echo) is never deleted while still needed.
* `Keep = 'bold_mean'` on a step protects the output of *that* step. In the example the
  mean image written by `Realign` survives although `Normalize` later produces a new
  `bold_mean`.
* `pipe.Retain('all')` goes back to deleting nothing.

## 7. Variants of a pipeline

```matlab
pipe8 = pipe.copy('rest_smooth8');       % deep copy
pipe8.Steps{7}.FWHM = 8;                 % parameters can be changed after adding
```

Parameters are validated on assignment. Before running variants on the same data, call
`metools.Pipeline.checkCollisions` or give the variants different `Prefix` values.

## 8. Configuration and sessions

`FmriConfig` has typed, validated properties: `cfg.paths.project`, `cfg.paths.masks`,
`cfg.acq.TR`, `cfg.acq.TEs`. A typo (`cfg.acq.Tr`) or an invalid value is an error, not a
silently created field. Steps take unset parameters from the config; an explicit
parameter always wins.

A different session may need different values:

```matlab
cfg.addOverride('video', 'acq.TR', 2.0);   % applies only when Session = 'video'
```

## 9. Participants and folder layout

```
<project>/
    data/
        <subject>/
            anat/_t1.nii                    T1 (used by Normalize)
            fields/                         fieldmaps (FieldMap)
            logs/                           detailed run logs (when LogDir is set)
            <session>/                      one folder per session, e.g. rest
                _echo_1.nii ...  markers.csv  acq_params.json
    outputs/                                figures and other results shared by subjects
```

`Participants(projectDir, subjects)` implements this layout (`data`, `fields`, `logs`,
`outputs` are properties and can be changed). `participants.add(...)` adds subjects later.

## 10. Library and project

METools is the library; your study is a separate project folder:

```
METools/                      library (put on the path with setup_metools)
    lib/+metools/             generic core: Pipeline, Step, Port, Participants, Config, ...
    lib/+metools/+fmri/       FmriPipeline, FmriConfig and the built-in fMRI steps
    lib/+metools/+fmri/+proc/ the processing functions behind the steps (usable on their own)
    lib/+metools/+util/       small helpers
    lib/thirdparty/           bundled third-party code
    docs/  tests/
MyStudy/                      project
    run_rest.m                pipeline definition and run
    SubjectsDefinition.m      subject lists
```


## 11. Writing your own step

A step is a small class: public properties with validators are its parameters; the
methods describe its ports and outputs. Keep it in your project folder while you develop
it; nothing in METools has to change.

```matlab
classdef StepScale < metools.Step
    properties
        Factor (1,1) double {mustBePositive} = 2
    end
    methods
        function p = ports(~)
            p.In  = metools.Port.input('bold');
            p.Out = metools.Port.output('', 'Follows', 'In');   % write back into the stream read
        end
        function out = predict(~, in, ~)
            out.Out = metools.Step.addPrefix(in.In, 'k');       % names of the outputs
        end
        function names = requiredFunctions(~)
            names = {'myScaleFunction'};                        % checked by dryRun
        end
        function execute(obj, in, ~, ~)
            for i = 1:numel(in.In)
                myScaleFunction(in.In{i}, obj.Factor, 'k');
            end
        end
    end
end
```

Use it with `pipe.add(StepScale(), Factor = 3)`. Optional hooks: `check(in, cfg)` for
step-specific static checks, `externalFiles(ctx)` for files that are not streams,
`configBindings()` to take a parameter from the config, `qc(in, out, ctx)` for
quality-control items in the log. `predict` must give the names of all output files
without computing anything and must cope with `ctx` being empty (static validation). The
computation itself should call an ordinary function with plain file names; the step is
the glue: put the computation into a function with plain arguments (like the functions
in `metools.fmri.proc`) and call it from `execute`. The
[Reference](REFERENCE.md#writing-steps) describes the full contract.

## 12. Running the tests

```matlab
cd W:\Scripts\METools
run_tests          % writes test_report.txt in the same folder
```

The tests use fake steps (`tests/+fake`) that only create empty files, so they run
without SPM and without data.
