# METools

A MATLAB framework for assembling fMRI preprocessing pipelines declaratively. Steps are
connected by named streams (`bold`, `bold_mean`, `rp`, ...), the whole pipeline is
validated statically (including all file names) before any data is touched, and it runs
for every subject with a per-subject report and optional HTML logs.

```matlab
import metools.*
import metools.fmri.*

pipe = FmriPipeline('rest', cfg, Input = {'_echo_1.nii', '_echo_2.nii', '_echo_3.nii'});
pipe.Realign(Master = 2);
pipe.FieldMap();
pipe.EchoCombination();
pipe.Retroicor();
pipe.Normalize();
pipe.CreateMask(Threshold = 0.8);
pipe.Smooth(FWHM = 6);
pipe.NuisanceSignalRegression(Target = 'bold_smooth');
pipe.Retain('bold', 'bold_smooth', 'bold_mean', 'rp', 'brain_mask');

pipe.describe();
pipe.dryRun(participants, Session = 'rest');
pipe.LogDir = 'logs';                       % optional HTML logs
pipe.runFor(participants, Session = 'rest');
```

* Start here: [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)
* Everything in detail: [docs/REFERENCE.md](docs/REFERENCE.md)
* Architecture: [docs/DESIGN.md](docs/DESIGN.md)
* What each step does: [docs/steps/](docs/steps/)
* Known issues and plans: [docs/TODO.md](docs/TODO.md)

Setup: run `setup_metools` (adds `lib` and the bundled third-party code to the path).
Requirements: MATLAB R2021a or newer (developed on R2023b), SPM12, CAT12 (Normalize).

## Tests

```matlab
cd W:\Scripts\METools
run_tests          % writes test_report.txt into this folder
```

The tests use fake steps from `tests/+fake` that only create empty files; no SPM or data
needed.
