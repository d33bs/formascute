# Alpine Skill

Use this note before changing, testing, or scaling formascute on CURC Alpine,
especially for Nextflow, Slurm submission, `Persistence1`, ZedProfiler, or
runtime environment behavior.

## Current Position

- Submit and orchestrate through `Persistence1`; treat this as selected project
  policy, not an open question.
- Keep compute work on Slurm. `Persistence1` is for the long-lived workflow
  manager, not image processing or other heavy work.
- Use `queueSize = 200` as the conservative production default. This aligns with
  the reported campus/user active-job limit.
- Do not use `queueSize > 1000`. Treat `1000` as a stress-test ceiling, not a
  normal operating value.
- Prefer moderate batching before aggressive submit throttling. For imaging
  work, batch by data locality so each task loads an image set once and emits
  validated outputs.
- Prefer the validated project-owned `uv` environment for ZedProfiler work unless
  real production runs show a concrete reason to switch runtime strategy.
- Monitor the Nextflow orchestrator on `Persistence1`; its memory use may be the
  practical scaling limit before Slurm submission becomes the bottleneck.

## Connection

From the local machine, use the `ssh-alpine` zsh alias:

```bash
zsh -lic 'ssh-alpine "hostname; pwd"'
```

The alias should be defined in the user's shell configuration as an SSH command
to `login.rc.colorado.edu` using that user's Alpine SSH key.

`Persistence1` is not directly resolvable from the local machine. Reach it from
the Alpine login node:

```bash
zsh -lic 'ssh-alpine "ssh Persistence1 hostname"'
```

For real runs, use `tmux` or `screen` on `Persistence1` so the workflow manager
survives SSH disconnects.

## Downtime Awareness

Before debugging failed Alpine SSH, module, Slurm, or filesystem behavior, check
whether the date is near CURC planned maintenance.

CURC policy says the first Wednesday of each month is reserved for planned
maintenance. CURC resources, including compute clusters, filesystems, and
servers, may be unavailable. A CURC course-support page describes the practical
first-Wednesday window as roughly `7a-5p`; the status page is authoritative for
the actual current window because CURC can cancel, move, or extend maintenance.

Check the live status page first:

```bash
curl -fsSL https://curc.statuspage.io/api/v2/summary.json
```

Useful fields to inspect:

- top-level `status.indicator`; expected value during maintenance:
  `maintenance`
- `components[]` entry named `Alpine`; expected status during downtime:
  `under_maintenance`
- `scheduled_maintenances[]`; look for an `in_progress` or `scheduled` event
  affecting Alpine, Research Computing Core, PetaLibrary, or Open OnDemand
- `scheduled_for` and `scheduled_until`; use these exact timestamps over the
  rough first-Wednesday rule

Actual maintenance-day probe on `2026-08-05`, the first Wednesday of August
2026:

- status page updated at `2026-08-05T06:30:07-06:00`
- top-level status was `maintenance`
- Alpine, Research Computing Core, Blanca, PetaLibrary, and Open OnDemand were
  `under_maintenance`
- the scheduled maintenance entry said affected services would be unavailable
- `ssh-alpine "date; hostname; pwd"` still reached login node `login-ci3`
- `ssh-alpine "ssh Persistence1 'date; hostname; pwd'"` still reached
  `persistence1`
- `module load nextflow/25.10.2 && nextflow -version` still worked on
  `Persistence1`
- `sinfo` still showed partitions such as `acpu` as `up`, so `sinfo` alone is
  not sufficient to rule out maintenance
- `scontrol show reservation` showed active `pm-8.5-*` reservations from
  `2026-08-05T06:30:00` to `2026-08-06T06:30:00` with `Flags=MAINT` across CPU,
  GPU, compile, testing, and DTN partitions
- `sbatch --test-only` did not submit and returned policy/transition messages
  during this window, including the `amilan` to `acpu` and `normal` to
  `cpu-normal` rename notices, plus `allocation failure: Invalid qos
  specification`

Interpretation: maintenance does not necessarily mean SSH, `Persistence1`,
Nextflow modules, or Slurm commands are totally unreachable. Treat the status
page and `scontrol show reservation` as stronger signals than basic connectivity
or `sinfo` partition state.

Slurm can also show maintenance before the outage begins. If jobs sit pending
with reason `ReqNodeNotAvail`, especially in the days leading up to the first
Wednesday, check maintenance reservations:

```bash
squeue -u "$USER" --start
scontrol show reservation
```

Long walltime jobs may not start if their requested runtime intersects the
maintenance reservation. Reduce walltime, wait until maintenance completes, or
resubmit after the status page returns Alpine to `operational`.

## Module And Runtime Facts

The regular Alpine login node did not expose a usable Nextflow module during
validation. `Persistence1` did expose these Nextflow modules:

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
available and reported Apptainer 1.4.5. Treat this as an available fallback for
future packaging, not as the preferred current path.

## Slurm Defaults

Use these defaults for CPU work unless the user or CURC gives a newer allocation
policy:

- account: project allocation supplied by the user
- partition: `acpu`
- QoS: `cpu-normal`
- submit host: `Persistence1`
- executor: Slurm
- production `queueSize`: `200`
- production submit throttle: optional, start around `200 / 60 min` only when
  real task walltime justifies it

Slurm accepted `acpu` and `cpu-normal` and mapped them to the current CPU
partition backing the older `amilan`/`normal` names.

Keep CPU and GPU work separated into different profiles or runs.

## Production Submission Shape

For production-scale workflow execution, prefer a direct `Persistence1` run in
`tmux` or `screen`. From the Alpine login node:

```bash
ssh Persistence1
tmux new -s formascute
cd /scratch/alpine/$USER/formascute-codex-test
module load nextflow/25.10.2
make preflight ACCOUNT=<allocation>
make run EXPERIMENT=<experiment> ITEMS=<n> ACCOUNT=<allocation> PROFILE=alpine RUN_ID=<run-id>
```

Use the generated `make submit ... SUBMIT_HOST=Persistence1` path for small smoke
tests and repository validation. Be cautious about making the Slurm coordinator
job the long-term UX because CURC positions `Persistence1` as the place to run
long-lived workflow managers directly.

Validated smoke path from a clone on Alpine shared scratch:

```bash
make check
make preflight ACCOUNT=<allocation>
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
```

Successful validation run:

```bash
make submit EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1 RUN_ID=remote-smoke-persistence
```

Observed result:

- coordinator Slurm job completed
- `completion_status.txt` reported `nextflow_exit_status: 0`
- `validation.json` reported `"valid": true`
- `trace.tsv` contained native Slurm job IDs
- `slurm.tsv` was collected

## Orchestrator Monitoring

Treat the Nextflow process on `Persistence1` as a constrained service.

Known `Persistence1` guidance received for this project:

- VM size: 8 cores and 8 GB RAM
- individual user cgroups: about 20% of total RAM and 80% of CPU
- the orchestrator may be cancelled if it exceeds RAM limits for too long

During real runs, monitor the user's processes:

```bash
htop -u "$USER"
top -u "$USER"
squeue -u "$USER"
```

Recommended implementation direction:

- capture or periodically log Nextflow/orchestrator RSS during larger runs
- keep the Nextflow JVM heap conservative, for example via `NXF_OPTS`, then tune
  from observed memory rather than guessing
- make preflight report host, loaded Nextflow, Python runtime, active job
  count, and suggested monitoring commands

## Queue And Batching Policy

The reported Alpine active-job limit for the campus/user context is 200 jobs.
`queueSize = 1000` may be accepted by Nextflow, but Slurm will likely run only
about 200 jobs at once and leave the rest pending.

Use this order of operations when optimizing:

1. First make the process granularity sensible.
2. Batch small imaging tasks by image set, plate, well group, or compatible
   feature family.
3. Keep `queueSize = 200` for initial production runs.
4. Add `submitRateLimit = '200 / 60 min'` only if the scheduler or CURC guidance
   indicates submit-rate pressure.
5. Adjust the rate window to match observed task walltime.
6. Test higher queue sizes only with explicit measurement and avoid anything
   above `1000`.

For NF1/ZedProfiler-style imaging, target tasks that are large enough to amortize
image I/O and Slurm overhead. The exact batch size should come from `trace.tsv`,
`slurm.tsv`, output validation, and image I/O behavior on real data.

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
- Batch sizes 2-4 are the first synthetic batching range to consider, but real
  imaging data should drive the production batch shape.
- Use `queueSize` before `submitRateLimit` for scheduler pressure control unless
  CURC explicitly asks for rate limiting.

For NF1 orchestration, prefer a thin Nextflow layer around the existing Stage 3
work list and feature scripts before rewriting processing code.

## ZedProfiler Runtime

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

Real ZedProfiler work needs a project-owned Python 3.11+ environment. The
validated `uv` path satisfies that requirement today. Consider an
Apptainer/Singularity image only if `uv` becomes hard to reproduce across users,
the dependency set stops resolving cleanly, or CURC/project policy requires a
container artifact.

## uv Prototype Path

CURC documents a `uv` module for Python environments. The documented flow is:

```bash
module load uv
uv venv "$UV_ENVS/mycustomenv" --python 3.12
source "$UV_ENVS/mycustomenv/bin/activate"
uv pip install <packages>
```

The documentation says `module load uv` creates and sets `UV_ENVS` to
`/projects/$USER/software/uv/envs`. During live validation on `2026-08-04`,
neither the regular login node nor `Persistence1` exposed an `uv` module via
`module avail uv` or `module spider uv`.

The tested fallback is a project-owned `uv` install that keeps the same CURC
environment layout:

```bash
export UV_HOME="/projects/$USER/software/uv"
export UV_INSTALL_DIR="$UV_HOME/bin"
export UV_ENVS="$UV_HOME/envs"
export UV_CACHE_DIR="/scratch/alpine/$USER/uv-cache"
export UV_LINK_MODE=copy
export PATH="$UV_INSTALL_DIR:$PATH"
mkdir -p "$UV_INSTALL_DIR" "$UV_ENVS" "$UV_CACHE_DIR"

if [[ ! -x "$UV_INSTALL_DIR/uv" ]]; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

uv venv "$UV_ENVS/zedprofiler-simple" --python 3.12
source "$UV_ENVS/zedprofiler-simple/bin/activate"
uv pip install zedprofiler
python - <<'PY'
import importlib.metadata as metadata
import zedprofiler
print(metadata.version("zedprofiler"))
print(zedprofiler.__file__)
PY
```

Validated simple experiment using the `uv` environment:

```bash
cd /scratch/alpine/$USER/formascute-codex-test
module load nextflow/25.10.2
source "/projects/$USER/software/uv/envs/zedprofiler-simple/bin/activate"
make run EXPERIMENT=zp_synthetic_features ITEMS=4 ACCOUNT=amc-general PROFILE=alpine RUN_ID=zp-sim-uv-01
```

Observed `uv` environment validation:

- `uv 0.12.1` installed under `/projects/$USER/software/uv/bin`
- `uv venv --python 3.12` used `/usr/bin/python3.12`
- ZedProfiler `0.1.1` installed and imported
- heavy dependencies resolved as wheels, including `mahotas`, `pyarrow`,
  `numpy`, `pandas`, and `scikit-image`
- with `UV_CACHE_DIR` on scratch and the env under `/projects`, hardlinking was
  not available, so `UV_LINK_MODE=copy` should be set explicitly

Observed result:

- Nextflow ran from `/curc/sw/install/bio/nextflow/25.10.2_env/bin/nextflow`
- `python3` resolved to the `uv` environment
- preflight recorded Python `3.12.13`
- `completion_status.txt` reported `nextflow_exit_status: 0`
- `validation.json` reported `"valid": true`
- 4 feature tasks plus 1 validation task were submitted to Slurm
- 16 simulated feature rows were emitted

For current repository behavior, prefer this direct `Persistence1` run pattern
when testing `uv`: load the Nextflow module first, then activate the `uv`
environment before invoking `make run`. The generated `make submit` coordinator
currently treats `FORMASCUTE_ENV_DIR` as a replacement environment and skips
module loading when it exists, so it is not yet the right interface for a
combined Nextflow-module plus `uv` Python environment.

## Runtime Direction

For current Alpine work, prioritize the validated `uv` runtime:

- keep the environment under `/projects/$USER/software/uv/envs`
- keep the cache under `/scratch/alpine/$USER/uv-cache`
- set `UV_LINK_MODE=copy`
- record the Python version, `uv` version, package versions, and Nextflow version
  in run manifests
- add import smoke checks for ZedProfiler and scientific imaging dependencies

Apptainer/Singularity remains a possible later packaging option, but do not push
the project toward it by default. The present evidence favors `uv` because it has
already worked on Alpine for Python 3.12 and ZedProfiler dependency resolution.

## Important Failure Modes

- Submitting directly from the regular Alpine login node failed because the batch
  job could not load `nextflow/25.10.2`. Use `Persistence1` unless the module
  environment changes.
- Do not rely on the base `Persistence1` Python environment for real ZedProfiler.
- Do not let the orchestrator perform image processing directly on
  `Persistence1`.
- Do not assume a large Nextflow `queueSize` increases active Slurm concurrency
  beyond the site/user limit.
- Do not raise submit rate or queue size without checking orchestrator RSS and
  Slurm accounting first.

## Questions To Revisit With CURC

Revisit these after real imaging traces exist:

- Does the 200 active-job limit apply exactly to this allocation and user group?
- Is `submitRateLimit = '200 / 60 min'` appropriate for the observed task
  duration, or should the window be shorter or longer?
- Does CURC prefer Nextflow-managed tasks over Slurm arrays for this workflow
  once retries, accounting, and output validation are considered?
- Should SAMMed3D GPU work use a separate profile, partition, QoS, and runtime?
- What orchestrator RSS range is acceptable for multi-day runs on
  `Persistence1`?
