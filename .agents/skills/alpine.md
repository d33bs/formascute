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
  real production runs show a concrete reason to switch runtime strategy. CURC's
  contact expressed a reproducibility preference for Apptainer/Singularity over
  `uv`/conda for this shared project; a minimal Apptainer smoke test now backs
  that path too (see ZedProfiler Runtime), so re-evaluate before committing hard
  to `uv` for the production environment.
- Monitor the Nextflow orchestrator on `Persistence1`; its memory use may be the
  practical scaling limit before Slurm submission becomes the bottleneck. The
  exact cap is now confirmed by direct cgroup inspection, not just guidance: see
  Orchestrator Monitoring.
- `submitRateLimit` paces submissions at a constant rate starting from the very
  first job, regardless of total item count or `queueSize` headroom. It is not
  dormant just because the run is far below the job-count ceiling. Confirmed by
  experiment: see Queue And Batching Policy.

## Connection

*Scope: general Alpine/`Persistence1` access. Applies whether or not Nextflow
is involved.*

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

*Scope: general Alpine usage. Applies whether or not Nextflow is involved.*

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

## Nextflow Module

*Scope: when using Nextflow.*

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

## Container Runtime Binaries

*Scope: general — applies whether or not Nextflow is orchestrating the
container. `apptainer`/`singularity` are plain system binaries here, not
modules.*

On `Persistence1` and on `acpu` compute nodes, `/usr/bin/apptainer` and
`/usr/bin/singularity` are both available (Apptainer `1.4.5`), with no `module
load` step required. This holds for direct `apptainer build`/`apptainer exec`
usage (see ZedProfiler Runtime below) as much as for Nextflow-orchestrated
container tasks.

## Slurm Defaults

*Scope: `account`/`partition`/`QoS`/`submit host` are general Slurm settings —
they apply to any job on Alpine, including a plain `sbatch` script with no
Nextflow involved. `executor`, `queueSize`, and the submit throttle are
Nextflow executor settings and only mean something when using Nextflow.*

Use these defaults for CPU work unless the user or CURC gives a newer allocation
policy:

- account: project allocation supplied by the user
- partition: `acpu`
- QoS: `cpu-normal`
- submit host: `Persistence1`
- executor: Slurm *(Nextflow only)*
- production `queueSize`: `200` *(Nextflow only)*
- production submit throttle: optional, start around `200 / 60 min` only when
  real task walltime justifies it *(Nextflow only)*

Slurm accepted `acpu` and `cpu-normal` and mapped them to the current CPU
partition backing the older `amilan`/`normal` names.

Keep CPU and GPU work separated into different profiles or runs.

**Per-task memory/CPU allocation, confirmed on `2026-08-06` (Nextflow-only).**
`nextflow.config`/`conf/alpine.reference.config` set no `process.memory` or
`process.cpus` for `CHARACTERIZE_ITEM`, so every Nextflow task submitted so far
has silently gotten Nextflow's own conservative default. Checked via
`sacct --format=ReqMem,ReqCPUS,AllocTRES` across several completed jobs:

- every task got exactly `ReqMem=1G`, `ReqCPUS=1`, `AllocTRES=cpu=1,mem=1G,node=1`
- this is *smaller* than the `acpu` partition's own default: `scontrol show
  partition acpu` reports `DefMemPerCPU=3840` (MB, i.e. `~3.75 GB` for `1`
  CPU) — so Nextflow's own default undercuts what a bare `sbatch` with no
  `--mem` would have gotten
- this default has been silently fine for every synthetic run so far because
  none of them approached `1 GB`. It stopped being fine once real ZedProfiler
  calls were tested — see ZedProfiler Runtime, where a single real image's
  partial feature extraction hit `~1.01 GB` peak RSS, right at this ceiling.

Set an explicit `process.memory` (and likely `process.cpus`) before any real
ZedProfiler/NF1 production run; do not rely on Nextflow's default.

## Production Submission Shape

*Scope: when using Nextflow.*

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

*Scope: when using Nextflow (the orchestrator is the Nextflow process). The
underlying cgroup limits documented below are a general `Persistence1` fact —
they cap everything a user runs there, Nextflow or not.*

Treat the Nextflow process on `Persistence1` as a constrained service.

Known `Persistence1` guidance received for this project:

- VM size: 8 cores and 8 GB RAM
- individual user cgroups: about 20% of total RAM and 80% of CPU
- the orchestrator may be cancelled if it exceeds RAM limits for too long

Confirmed directly on `2026-08-06` by reading cgroup and systemd state on
`Persistence1` (read-only check, no job submitted). The limit is enforced on the
`user-<uid>.slice`, not on the SSH session scope one level below it, so check the
slice, not the session:

```bash
cat /sys/fs/cgroup/memory/user.slice/user-<uid>.slice/memory.limit_in_bytes
cat /sys/fs/cgroup/cpu,cpuacct/user.slice/user-<uid>.slice/cpu.cfs_quota_us
cat /sys/fs/cgroup/cpu,cpuacct/user.slice/user-<uid>.slice/cpu.cfs_period_us
systemctl show user-<uid>.slice -p MemoryLimit -p CPUQuotaPerSecUSec
```

Observed values:

- host total RAM: `8069439488` bytes (about 7.51 GiB)
- host CPUs: `8`
- `memory.limit_in_bytes` on the user slice: `1613885440` bytes, which is
  exactly `20%` of host RAM (about 1.5 GiB / 1.6 GB)
- `cpu.cfs_quota_us` / `cpu.cfs_period_us` on the user slice: `640000 / 100000`,
  i.e. `6.4` of `8` CPUs, exactly `80%`
- enforced via legacy cgroup v1 fields driven by systemd drop-ins
  (`.../user-.slice.d/50-CPUQuota.conf`, `.../user-<uid>.slice.d/50-MemoryLimit.conf`),
  not `MemoryMax`/`MemoryHigh`, which both read `infinity`; check `MemoryLimit`
  and `CPUQuotaPerSecUSec` specifically, not the newer systemd properties
- at idle, the user slice's own `MemoryCurrent` was about `8 MB`, far below the
  `~1.6 GB` cap

This upgrades "monitor RAM, roughly 20%/80%" to a hard, quantified ceiling:
about `1.6 GB` RAM and `6.4` CPUs for everything the user runs on `Persistence1`,
including the Nextflow JVM. The earlier `zp_synthetic_features` probe peaked at
`9-32 MB` RSS per task, only about `1-2%` of the confirmed cap, so tiny synthetic
runs have not come close to stressing this limit. Real ZedProfiler-scale runs
should log orchestrator RSS against this `~1.6 GB` number specifically, not the
VM's full `8 GB`.

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

*Scope: when using Nextflow (`queueSize` and `submitRateLimit` are Nextflow
executor settings). The underlying 200-job campus/user limit is a Slurm fact
that applies regardless of orchestration mechanism.*

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

CURC's contact suggested `submitRateLimit = '200 / 60 min'` as a companion to
`queueSize = 200`, with the framing "the rest will go pending" implying it only
matters once submissions approach the 200 ceiling. An experiment on `2026-08-06`
(`nf1_submit_rate_prod_ratio`, `queueSize=200`, `submitRateLimit='200 / 60 min'`,
16 items, well under the ceiling) shows that framing is incomplete:

- individual task submissions landed about 18 seconds apart from the very first
  job, matching `60 min / 200 = 18s` exactly
- the coordinator took `5m 10s` for the same 16-item workload that finished in
  about `51-52s` unthrottled (`nf1_featurization_independent`)
- validation still passed (`16/16` items, exit `0`), so the setting is safe, just
  slow

Interpretation: `submitRateLimit` is a steady-rate limiter from job 1, not a
threshold that only engages once the job count nears the configured limit. For a
workload of `N` short tasks, it imposes a wall-clock floor of roughly
`N × (window / rate)`, independent of `queueSize` or actual task duration. Real
ZedProfiler feature tasks ran `1-3s` each in the synthetic probe; at
`200 / 60 min` a `200`-task run would take at least `~60` minutes from submit
pacing alone, regardless of how fast the tasks themselves complete. Treat
`submitRateLimit` as a throughput cap that multiplies against total task count,
not a pressure-relief valve that only bites past `queueSize`. Prefer batching to
cut task count before adding a submit-rate limit for many-short-task
workloads.

## Synthetic Experiment Findings

*Scope: when using Nextflow.*

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

### When Not Using Nextflow: Building And Validating The Runtime

*Scope: general — building and sanity-checking a ZedProfiler-capable runtime
does not require Nextflow at all. Everything in this subsection was run via a
plain `sbatch` job or direct `apptainer exec`/`apptainer build`, never through
`make run`/`make submit`.*

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

CURC's contact explicitly recommended Apptainer/Singularity over `uv`/conda for
this shared project, citing reproducibility and long-term maintainability over
raw convenience, and confirmed the site Apptainer (`1.4.5`) and Singularity
(`3.7.4`) should handle Python 3.11. A minimal smoke test on `2026-08-06`
confirms the mechanics work:

```bash
apptainer pull python311.sif docker://python:3.11-slim
apptainer exec python311.sif python3 --version
```

Run as a short (`10` min walltime, `1` CPU, `2` GB mem) batch job on the `acpu`
partition (not on `Persistence1`, consistent with keeping compute off the
orchestrator host):

- `apptainer version 1.4.5-3.el8` matched CURC's stated version
- the pull of `python:3.11-slim` from Docker Hub completed in about `25s`
- `python3 --version` reported `Python 3.11.15` inside the container
- basic standard-library imports (`sqlite3`, `zlib`) worked

This is still only a mechanics check: it does not install or import
`zedprofiler`, `mahotas`, `pyarrow`, or `scikit-image` inside a container, and it
does not build a project-owned `.sif` image or test on real NF1 image data. It
upgrades Apptainer from "available fallback, not preferred" to "confirmed
working for Python 3.11 on Alpine compute nodes," which is enough evidence to
justify a real side-by-side comparison (build a ZedProfiler-dependency
Apptainer image vs. the validated `uv` environment) before committing to one
runtime for production, especially given CURC's explicit reproducibility
preference for containers on a shared project.

**Real ZedProfiler dependencies confirmed in Apptainer (2026-08-06).** Followed
through on the side-by-side comparison above. Built a project-owned image with
the same dependency set as the validated `uv` environment:

```text
Bootstrap: docker
From: python:3.12-slim

%post
    apt-get update
    apt-get install -y --no-install-recommends procps
    rm -rf /var/lib/apt/lists/*
    pip install --no-cache-dir zedprofiler mahotas pyarrow numpy pandas scikit-image
```

Built via `apptainer build --fakeroot` as a short batch job on `acpu` (fakeroot
works via a root-mapped namespace fallback even though this user has no
`/etc/subuid`/`/etc/subgid` entries). Build + install took about `2m12s`-`3m20s`
across two builds. Image lands at
`/projects/$USER/software/apptainer/zedprofiler.sif` (about `294 MB`).
Import validation (direct `apptainer exec`, not Nextflow) matched the `uv`
probe exactly on `zedprofiler` version:

- `zedprofiler 0.1.1` (same release as `uv`), `numpy 2.5.1`, `pandas 3.0.5`,
  `mahotas 1.4.18`, `pyarrow 25.0.0`, `scikit-image 0.26.0` — all newer than the
  `uv` probe's pinned versions, since this was an unconstrained `pip install`
  inside a fresh image rather than a lockfile-driven resolve
- all imports succeeded on the first real ZedProfiler-dependency build

The `procps` package (providing `ps`) was included in the `%post` step above
from the start of this build. That's not incidental — see the next subsection
for why it's required the moment Nextflow orchestrates the container, even
though it made no difference to this direct `apptainer exec` validation.

**Real feature calls on real data (2026-08-06).** Everything above only proves
`zedprofiler` imports. To close that gap, ran actual feature extractors against
a small real CellProfiler-3D-tutorial nuclei dataset bundled with
ZedProfiler's own test suite (`100×258×258` `uint16` volumes + segmentation
masks, 5 objects) under `tests/data/CP_tutorial_3D_noise_nuclei_segmentation/`.
Pulled one image/mask pair (`nuclei1_out_c00_dr90_image.tif`), built an
`ImageSetLoader`/`ObjectLoader` exactly as ZedProfiler's own
`tests/featurization/test_real_world_data.py` does, and called three real
extractors (via the `uv` environment, no Nextflow, `2` CPUs / `4` GB / `15`
min batch job on `acpu`):

- `compute_intensity`: `5` rows, `2.835s`
- `compute_volume_size_shape`: `5` rows, `0.599s`
- `compute_granularity` (`radius=1`, `granular_spectrum_length=2`,
  `subsample_size=1.0`, `image_sample_size=1.0`): `5` rows, `12.878s`
- all three finite, `5/5` expected objects, exit `0`
- job peak RSS: `1061332K` (`~1.01 GB`) for just these 3 of 6 feature calls on
  a single image

This is the first real, non-synthetic, non-import-only evidence that
`zedprofiler` actually runs correctly end-to-end on Alpine. Two things fall out
of it that change prior assumptions:

- **Granularity was far more expensive here than ZedProfiler's own upstream
  benchmarking has reported for comparable real-world data.** `12.9s` for one
  real image here vs. a roughly `~7×` lower number reported upstream at one
  point for the same feature on similar tutorial data. Treat any upstream
  ZedProfiler timing numbers as a moving target — they depend on which
  release/branch is installed and which `granularity` parameters were used
  (this probe used no downsampling: `subsample_size=1.0`/`image_sample_size=1.0`,
  likely the most expensive setting), not just hardware. Don't use a
  remembered upstream benchmark number for Alpine time-budget planning without
  re-measuring against the exact `zedprofiler` version actually installed —
  this probe's numbers are the ones actually measured on this cluster, with
  this version, with these parameters.
- **The ~1GB peak RSS for a partial real-image run lands right at Nextflow's
  silent 1 CPU / 1 GB per-task default** (see Slurm Defaults and Important
  Failure Modes). A real production task calling all 6 feature extractors, or a
  larger volume, would plausibly exceed `1 GB` and get OOM-killed with the
  current `nextflow.config`, which sets no `process.memory`/`process.cpus` for
  `CHARACTERIZE_ITEM`. This is no longer a hypothetical risk — treat setting an
  explicit, generous `process.memory` (well above `1 GB`) as a prerequisite for
  any real ZedProfiler production run, not an optimization to defer.

### When Using Nextflow: Orchestrating ZedProfiler Work

*Scope: when using Nextflow. This subsection covers running the validated
runtimes above (`uv` or the Apptainer image) as actual Nextflow processes
through `make run`/`make submit`.*

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

**Gotcha, first Apptainer-through-Nextflow attempt failed:** running
`zp_apptainer_probe` (the `zp_synthetic_features` workload with
`process.container` pointed at the `.sif` built above,
`FORMASCUTE_ENABLE_CONTAINER=true`) through Nextflow+Slurm failed every task
with:

```text
Command 'ps' required by nextflow to collect task metrics cannot be found
```

A bare `python:3.12-slim` base has no `procps` package, so no `ps` binary.
Nextflow's Slurm+container executor shells into the container to poll task
metrics for `trace.tsv`/RSS/CPU accounting, and needs `ps` present *inside* the
image, not just on the host. This never surfaced in the direct `apptainer exec`
import validation above — it only appears once Nextflow actually orchestrates
through the container. The `uv` path never hits this because it runs directly
on the host with no container boundary. Any Apptainer/Singularity image
intended for Nextflow-orchestrated execution on Alpine must include `procps`
(or equivalent), not just the workload's own Python dependencies.

After adding `procps` to the `%post` step and rebuilding, the same probe
completed cleanly:

```bash
FORMASCUTE_ENABLE_CONTAINER=true make run EXPERIMENT=zp_apptainer_probe ITEMS=4 ACCOUNT=amc-general PROFILE=alpine RUN_ID=zp-sim-apptainer-02
```

- `nextflow_exit_status: 0`, `validation.json` `"valid": true`, `4/4` items
- 4 feature tasks + 1 validation task, all `COMPLETED`
- per-task `realtime` about `1.3s`, `peak_rss` about `21 MB` — in the same range
  as the `uv` path's `zp_synthetic_features` probe (`9-32 MB` peak RSS)
- coordinator `Duration: 1m 16s` for 4 items + validation

Bottom line: Apptainer is now confirmed end-to-end for this workload shape —
same `zedprofiler` version, same synthetic feature output, comparable resource
footprint to `uv` — but only after fixing a container-specific plumbing gap
that has no equivalent on the `uv` path. Treat "does the image have `procps`"
as a standard checklist item for any future Apptainer image built for this
project's Nextflow pipeline. This still does not test real NF1 image I/O or
heavier ZedProfiler calls (`neighbors`, `granularity`, and other feature
extractors that are known to cost meaningfully more than a bare import) inside
the container — only that the dependency set installs, imports, and survives
Nextflow's container orchestration.

## uv Prototype Path

### When Not Using Nextflow: Building And Validating The uv Environment

*Scope: general — building and import-checking the `uv` environment is plain
shell/Python work, no Nextflow involved.*

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

### When Using Nextflow: Running Through Nextflow

*Scope: when using Nextflow. This subsection covers activating the `uv`
environment validated above and then running it as an actual Nextflow process
through `make run`.*

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

*Scope: general decision guidance — applies regardless of whether Nextflow
ends up orchestrating the runtime.*

For current Alpine work, prioritize the validated `uv` runtime:

- keep the environment under `/projects/$USER/software/uv/envs`
- keep the cache under `/scratch/alpine/$USER/uv-cache`
- set `UV_LINK_MODE=copy`
- record the Python version, `uv` version, package versions, and Nextflow version
  in run manifests
- add import smoke checks for ZedProfiler and scientific imaging dependencies

Apptainer/Singularity remains a real, now-validated alternative, not just a
later packaging option. As of `2026-08-06`, both paths are confirmed
end-to-end for the same synthetic workload: same `zedprofiler 0.1.1` release,
comparable peak RSS (`9-32 MB` for `uv`, `~21 MB` for Apptainer), both pass
validation through Nextflow+Slurm. CURC's contact explicitly prefers
Apptainer/Singularity for this shared project's reproducibility, and now that
preference has real evidence behind it, not just a smoke test. Real feature
calls (not just imports) are now validated on the `uv` side against real data
(see ZedProfiler Runtime); the Apptainer side has not had the same real-data
feature-call check yet, only synthetic orchestration and import validation.
Neither has been tested against real NF1 image I/O, and `granularity` is a
known expensive, currently-unoptimized feature extractor worth watching in any
timing comparison. Decide between them based on operational preference (CURC's
reproducibility argument for images vs. `uv`'s faster iteration for a
still-changing dependency set) rather than technical blockers, since there no
longer are any known blockers on the Apptainer side beyond the `procps`
requirement noted in ZedProfiler Runtime.

## Important Failure Modes

### When Using Nextflow

- Submitting directly from the regular Alpine login node failed because the batch
  job could not load `nextflow/25.10.2`. Use `Persistence1` unless the module
  environment changes.
- Do not let the orchestrator perform image processing directly on
  `Persistence1`.
- Do not assume a large Nextflow `queueSize` increases active Slurm concurrency
  beyond the site/user limit.
- Do not raise submit rate or queue size without checking orchestrator RSS and
  Slurm accounting first.
- Do not build an Apptainer/Singularity image for Nextflow-orchestrated
  execution without `procps` installed. Nextflow's Slurm+container executor
  needs `ps` *inside* the container for task metrics collection; a bare
  `python:3.x-slim` base lacks it and every task fails with `Command 'ps'
  required by nextflow to collect task metrics cannot be found`. A plain
  `apptainer exec` smoke test will not catch this — it only surfaces once
  Nextflow orchestrates through the container.
- Do not run real ZedProfiler work without setting an explicit
  `process.memory`. Nextflow's default (`1 GB`) is smaller than the `acpu`
  partition's own default and was measured landing right at that ceiling for a
  partial real-image feature extraction (`~1.01 GB` peak RSS for `3` of `6`
  extractors on one image). See Slurm Defaults.

### General (Alpine / Apptainer, Not Nextflow-Specific)

- Do not rely on the base `Persistence1` Python environment for real ZedProfiler.
- When building with `apptainer build --fakeroot` in a Slurm batch job, stage
  the `.def` file on a shared filesystem (scratch/project), not `/tmp` on the
  login node — compute nodes have their own local `/tmp`, not shared with the
  login node.

## Questions To Revisit With CURC

Answered by CURC's contact on `2026-08-06` and now also backed by direct
experiment/cgroup evidence in this file:

- The 200 active-job limit: CURC confirmed `queueSize=1000` would still be
  capped near 200 concurrent by Slurm, with the rest pending; `submitRateLimit`
  was offered as an alternative pressure valve, tunable by expected walltime.
- Container vs. `uv` vs. conda: CURC recommends Apptainer/Singularity for
  reproducibility on this shared project, confirmed the site version handles
  Python 3.11, called conda harder to maintain long-term, and had no strong
  view on `uv` specifically.
- `Persistence1` RAM: CURC recommends monitoring orchestrator RAM via
  `top`/`htop -u $USER`; the VM is `8` cores / `8` GB with per-user cgroups at
  `20%` RAM / `80%` CPU, and the orchestrator risks cancellation if it exceeds
  the RAM limit for too long. Now quantified exactly: see Orchestrator
  Monitoring.
- Use `tmux`/`screen` on `Persistence1` for long-lived runs: already documented
  above under Connection.

Still open, revisit after real imaging traces exist:

- Is `submitRateLimit = '200 / 60 min'` still the right shape given the
  `2026-08-06` finding that it paces every submission at a steady rate from job
  1, not just once near the 200-job ceiling, imposing a wall-clock floor of
  roughly `task_count × 18s` at that setting? For many short ZedProfiler tasks
  this floor could dominate total runtime; ask whether CURC would rather see
  moderate batching to cut task count, a shorter rate window, or no rate limit
  below some task-count threshold.
- Does CURC prefer Nextflow-managed tasks over Slurm arrays for this workflow
  once retries, accounting, and output validation are considered?
- Should SAMMed3D GPU work use a separate profile, partition, QoS, and runtime?
- What orchestrator RSS range is acceptable for multi-day runs on
  `Persistence1`, relative to the confirmed `~1.6 GB` cgroup cap?
- Does CURC have an opinion between the validated `uv` ZedProfiler environment
  and a project-owned Apptainer image once both are compared on the same real
  workload?
- Why did real `granularity` extraction on Alpine (`12.9s` for one image) run
  well above what upstream ZedProfiler benchmarking has reported for
  comparable real-world data at other points in time? Worth raising with the
  ZedProfiler maintainers directly (version/branch and parameter differences,
  not necessarily an Alpine-specific question) before trusting any remembered
  upstream number for time-budget planning — always re-measure against the
  exact installed version instead.
