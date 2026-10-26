# METools - design notes

Architecture and the reasoning behind it. New users should start with
[GETTING_STARTED.md](GETTING_STARTED.md).

## 1. Goals

Assemble even an advanced fMRI preprocessing pipeline declaratively in about 50 lines,
without loops and per-project copy-and-paste. Correctness and flexibility come before
speed. Every run recomputes the selected steps; `StartStep`/`EndStep` are developer aids.
Fake steps for testing live only in `tests/`.

## 2. Components

Package `metools` is the generic core, independent of the modality; package
`metools.fmri` builds the fMRI pipeline on top of it (other modalities, e.g. diffusion,
would be sibling packages).

| Component | Role |
|---|---|
| `Pipeline` | ordered list of steps plus input streams. Compiles a *plan* symbolically, validates it, runs it for each subject. |
| `FmriPipeline` (`metools.fmri`) | `Pipeline` with shortcut methods for the built-in fMRI steps and the SPM/CAT versions in `environmentInfo`. |
| `Step` (abstract) | one processing step. Parameters = public properties with validators. Declares ports, predicts output names, executes by calling processing functions (`metools.fmri.proc`). |
| `Port` | declaration of one input or output of a step (stream, cardinality, optional, follows). |
| `StreamEnv` | the versions of all streams at one point of the walk through the pipeline. |
| `PlanFormatter` | text rendering of a plan for `describe`. |
| `Participants` | subjects, folder layout, per-unit context. |
| `Config` | base of typed study configurations: access by path, per-session overrides, deep copy. `FmriConfig` adds the sections `paths` and `acq`. |
| `RunLog` | HTML logs of a run: summary and per-unit details with captured console output and QC. |

## 3. Streams

A stream is a named category of files (`bold`, `bold_mean`, `bold_smooth`, `rp`,
`brain_mask`, `covars`, `design_matrix`, `t1_coreg`, `roi_timeseries`, `connectivity`,
`roi_info`). Every write creates an immutable
version; the name points to the latest version. A step reads the latest version of the
stream bound to each input port. The history exists only for provenance and for deciding
what can be deleted; it is never searched.

* Output ports may **follow** an input port: the step writes into the stream it read
  (`bold` advances through realign, retroicor, ...). A step may instead write to another
  stream (`Smooth` -> `bold_smooth`), which creates a branch.
* Streams are overridden by name: `In = 'bold_smooth'`, `Target = 'bold_smooth'`,
  `Out = 'bold_smooth_8'`.
* Naming convention: `bold_<what>` for images derived from bold.
* Version identity: every version carries a signature (producing step, parameters, input
  signatures). It is used to detect that two pipelines write the same file differently.

## 4. Step contract

Required: `ports()`, `predict(in, ctx)`, `execute(in, out, ctx)`.
Optional: `check(in, cfg)`, `externalFiles(ctx)`, `requiredFunctions()`,
`configBindings()`, `signature()`.

* `predict` names the outputs from the inputs. During static validation `ctx` is empty,
  so it must not depend on it.
* `execute` receives plain file names and calls processing functions; the step contains
  no stream logic and no algorithm.

Layers: the step (`metools.fmri.Step*`) is the interface - parameters, ports, names,
checks, QC. The computation lives in `metools.fmri.proc`: one function per named
operation, plain arguments (text, numbers, structs; no METools classes), validation in an
`arguments` block, intermediate files in a temporary folder removed at the end. Small
general helpers live in `metools.util`; third-party code in `lib/thirdparty`.
* `configBindings` maps a parameter to a config path; the value is used when the
  parameter is empty (`resolve(name, cfg)`).
* Base properties: `Keep` (streams of this step whose files `Retain` must not delete) and
  `Bindings` (port overrides).

## 5. Compilation (`Pipeline.compile`)

Symbolic walk through the steps for a given set of absolute inputs and a unit context.
For each step: resolve input streams, check cardinality, check config bindings, run
`check`, call `predict`, detect output-file collisions (pass-through is allowed, overwriting a
raw input is an error), validate `Keep`. A step that fails *poisons* its output streams, so
later steps are reported as skipped instead of producing cascades of errors.

Afterwards: consumers of every version, stale-branch warning, unused-output warning, and
the release plan (`DeleteAfter{k}`: files that may be deleted after step k;
`FreeAfter{k}`: versions released). Release is file-based: a file shared by several
versions (pass-through) is deleted after the last version that needs it. Raw inputs and
retained or `Keep`-protected versions are never deleted.

## 6. Execution

`runFor` iterates over units (subject x session). Each unit: compile with the real paths;
for every step verify inputs, delete stale outputs (not pass-through files), execute,
verify outputs, compare a directory snapshot before and after to warn about undeclared
files, delete the files scheduled for that step. Errors are caught per unit.

With logging, `execute` (and `qc`) run inside `evalc` through a wrapper that returns the
error instead of throwing it, so the captured console output survives a failure. The
captured text goes to a text file per step and into the unit's HTML log; `RunLog`
rewrites both HTML files after every step (write to a temporary file, then rename).

`dryRun` performs the static plan, the function availability check (`which`), raw input
existence and `externalFiles` for each unit, and prints `environmentInfo()` (MATLAB, SPM, CAT12).
`Pipeline.checkCollisions` compares version signatures across pipelines.

## 7. Configuration

Typed handle classes: a typo is an error, values are validated. Access by dotted path
(`getValue`, `setValue`) is used by config bindings and by session overrides
(`addOverride(session, path, value)`; `forSession` returns a deep copy with overrides
applied). Priority: explicit step parameter > session override > study value > class
default.

## 8. Scopes

Units are subject x session. There are no hard-coded assumptions about `rest` or `video`.
Steps that logically run once per subject (T1 segmentation) are computed per session.
Approaches to anatomy differ a lot between users (T1 segmentation, segmentation of the
mean image, external tools), so no subject-level scope is built in.

## 9. Known issues

The equivalence with the original Cosmic2 pipeline, the known issues of the ported
algorithms and the open design points are tracked in [TODO.md](TODO.md).

## 10. Prior art

nipype, afni_proc.py and SPM matlabbatch solve related problems. METools differs by
streams with a static plan of all file names, MATLAB-native steps that call plain
functions, and validation before any computation.
