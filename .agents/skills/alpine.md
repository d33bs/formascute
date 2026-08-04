# Alpine Skill

Use this note before testing formascute on CURC Alpine.

## Connection

From the local machine, use the `ssh-alpine` zsh alias:

```bash
zsh -lic 'ssh-alpine "hostname; pwd"'
```

The alias should be defined in the user's shell configuration as an SSH command
to `login.rc.colorado.edu` using that user's Alpine SSH key.

`Persistence1` is not directly resolvable from the local machine. It is reachable
from the Alpine login node:

```bash
zsh -lic 'ssh-alpine "ssh Persistence1 hostname"'
```

## Module Behavior

The regular Alpine login node did not expose a usable Nextflow module during
validation. `Persistence1` did expose Nextflow modules:

- `nextflow/22.10.6`
- `nextflow/23.04`
- `nextflow/24.04.4`
- `nextflow/25.10.2`

The validated module is:

```bash
module load nextflow/25.10.2
nextflow -version
```

On `Persistence1`, `/usr/bin/apptainer` and `/usr/bin/singularity` were both
available and reported Apptainer 1.4.5.

## Slurm Defaults

Use these defaults for small synthetic CPU tests:

- account: project allocation supplied by the user
- partition: `acpu`
- QoS: `cpu-normal`
- submit host: `Persistence1`

Slurm accepted `acpu` and `cpu-normal` and mapped them to the current CPU
partition backing the older `amilan`/`normal` names.

`Persistence1` is the selected submission location for this project. Treat it as
known, not as an open question.

## Validated Submission Path

From a clone on Alpine shared scratch:

```bash
make check
make preflight ACCOUNT=<allocation>
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
```

The successful validation run used:

```bash
make submit EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1 RUN_ID=remote-smoke-persistence
```

Observed result:

- coordinator Slurm job completed
- `completion_status.txt` reported `nextflow_exit_status: 0`
- `validation.json` reported `"valid": true`
- `trace.tsv` contained native Slurm job IDs
- `slurm.tsv` was collected

## Synthetic Experiment Findings

Small synthetic runs completed successfully through `Persistence1`.

Useful observed shape:

- one-item minimal overhead: about 21 seconds
- independent 16-item fan-out: about 51-52 seconds, 17 native Slurm jobs
- batch size 2 with 16 items: about 42 seconds, 9 native Slurm jobs
- batch size 4 with 16 items: about 41 seconds, 5 native Slurm jobs
- `queueSize=4` with 16 independent items: about 1 minute
- `submitRateLimit='4 / 1 min'`: about 4 minutes and should not be the first
  tuning knob
- queue wait was negligible in tiny tests, usually 0-1 seconds

Interpretation:

- Nextflow can submit, track, validate, and collect Slurm accounting on Alpine
  when submitted through `Persistence1`.
- Batching reduced Slurm job count and modestly improved elapsed time in tiny
  synthetic tests.
- Batch sizes 2-4 are the first batching range to consider.
- Use `queueSize` before `submitRateLimit` for scheduler pressure control.
- Keep CPU and GPU work separated into different profiles or runs.

For NF1 orchestration, prefer a thin Nextflow layer around the existing Stage 3
work list and feature scripts before rewriting processing code.

## ZedProfiler Notes

The `zp_synthetic_features` experiment completed successfully on Alpine through
`Persistence1`:

```bash
make submit EXPERIMENT=zp_synthetic_features ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1 RUN_ID=zp-sim-01
```

Observed result:

- coordinator job completed with Nextflow exit status `0`
- validation passed for 4 expected items
- 4 feature tasks plus 1 validation task were submitted
- 16 simulated feature rows were emitted
- feature tasks took about 1-3 seconds each
- peak RSS was about 9-32 MB

This confirms the orchestration shape for tiny CPU-first 3D feature work, but it
does not validate real ZedProfiler imports or image I/O.

The tested base Python environment on `Persistence1` is not suitable for real
ZedProfiler:

- Python 3.9.13
- NumPy 1.21.5
- Pandas 1.4.4
- scikit-image 0.19.2
- missing `mahotas`
- missing `pyarrow`
- missing `zedprofiler`

Real ZedProfiler work needs a project-owned Python 3.11+ environment or an
Apptainer image. For NF1, prefer grouping compatible ZedProfiler feature families
by image-set when possible so each task loads image data once and writes validated
outputs.

## Important Failure Mode

Submitting directly from the regular Alpine login node failed because the batch
job could not load `nextflow/25.10.2`. Use `SUBMIT_HOST=Persistence1` unless the
module environment changes.

## CURC Questions To Preserve

Ask CURC before scaling:

- What `queueSize` range is recommended for Nextflow on Alpine?
- Should small NF1-style jobs use moderate independent submission or batching?
- Are Slurm job arrays recommended, or is Nextflow-managed submission preferred
  for retries and accounting?
- Should SAMMed3D GPU work be a separate Nextflow profile and submission path?
