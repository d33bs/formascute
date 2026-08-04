# North Star

This is the current gold-standard target for applying formascute's Alpine
findings to `WayScience/NF1_3D_organoid_profiling_pipeline`.

The goal is not to make the NF1 pipeline more abstract. The goal is to make its
execution model easier to reason about, resume, validate, and discuss with CURC
before production-scale image profiling.

## Position

Use Nextflow as the orchestration layer for NF1 execution on Alpine. Keep the
domain processing code in Python, R, and existing scripts where that code is
already correct. Replace nested `sbatch` parent/child submission with explicit
Nextflow processes, manifests, resource labels, and validated outputs.

This should be a thin workflow layer around real work, not a broad rewrite.

## Baseline Facts

- Alpine submission should run through `SUBMIT_HOST=Persistence1`.
- Use `acpu` and `cpu-normal` for small CPU characterization and initial CPU
  feature extraction work.
- Load `nextflow/25.10.2` in the coordinator job.
- Keep CPU feature extraction and GPU segmentation or SAMMed3D-style work in
  separate profiles or separate runs.
- Do not rely on the base `Persistence1` Python for ZedProfiler. It is Python
  3.9 and lacks required packages.
- Use a project-owned `uv` Python 3.11+ environment as the first ZedProfiler
  runtime path; use Apptainer if native wheels or system libraries fail.
- The documented CURC `uv` module was not visible during validation, but a
  user-space `uv` install under `/projects/$USER/software/uv/bin` worked.

## Target Shape

The preferred production shape is:

1. Generate a manifest of work items.
2. Submit one Nextflow coordinator job.
3. Let Nextflow submit Slurm tasks with bounded concurrency.
4. Validate every task output.
5. Collect `trace.tsv`, `slurm.tsv`, logs, reports, and manifest provenance.
6. Resume from the same work directory when safe.
7. Scale only after a small real-work probe succeeds.

The manifest should be the contract between NF1 data discovery and workflow
execution. It should include enough fields to reproduce a task without rerunning
discovery:

- patient
- plate or batch
- well
- field of view
- channel paths
- compartment mask paths
- feature families to compute
- output path
- expected output schema or validator
- CPU, memory, time, and profile label

## ZedProfiler Strategy

For ZedProfiler-based feature extraction, prefer one task per image-set when
possible. An image-set means one well/FOV with the channels and masks needed for
compatible feature families.

Within one task:

- load the image-set once
- compute compatible ZedProfiler feature families
- write one or more validated parquet outputs
- emit a compact task summary

This is preferred over one Slurm job per feature family, compartment, and channel
when those jobs repeatedly load the same image data. The formascute findings show
that tiny jobs are dominated by orchestration overhead; ZedProfiler's own
scalability guidance also supports choosing horizontal or vertical task grouping
based on data-loading cost and available compute.

Start independent, then batch only when evidence says to batch:

- Use independent image-set tasks when each task does enough CPU work to amortize
  Slurm overhead.
- Use batch sizes of 2-4 only when tasks are very short or repeatedly reload the
  same data.
- Use `queueSize` as the first scheduler pressure control.
- Avoid aggressive `submitRateLimit` unless CURC asks for it or scheduler
  behavior requires it.

## Nextflow Profiles

Use separate profiles or labels for distinct resource classes:

- `alpine_cpu`: `acpu`, `cpu-normal`, ZedProfiler and CPU feature extraction
- `alpine_gpu`: GPU partition and QoS for segmentation or SAMMed3D-style work
- `local_smoke`: tiny local syntax and validation check

Each process should declare realistic starting resources and retry escalation.
Initial CPU feature extraction defaults should be conservative:

- `cpus`: 1-4
- `memory`: 4-16 GB
- `time`: 1-4 hours
- `queueSize`: conservative and below user job limits
- `errorStrategy`: retry transient failures, fail validation failures

Do not mix CPU and GPU work in one executor profile.

## Validation Standard

Every production-facing task must produce a small validation artifact alongside
the science output. A task is not complete just because the command exited zero.

Validation should check:

- expected output files exist
- outputs are non-empty
- row counts are plausible
- required columns are present
- object or image-set identifiers match the manifest
- parquet or tabular outputs can be opened
- task summary records runtime inputs, output paths, and package versions

The workflow run directory should preserve:

- input manifest
- resolved config
- command line
- Nextflow log
- `trace.tsv`
- `timeline.html`
- `report.html`
- `dag.html`
- Slurm accounting when available
- per-task validation summaries

## First NF1 Implementation Slice

The first production-facing NF1 branch should implement only Stage 3 CPU
feature extraction with a tiny controlled manifest.

Recommended slice:

1. Add a manifest builder for a few known-safe image-sets.
2. Add a ZedProfiler `uv` runtime environment definition.
3. Add one Nextflow process for CPU feature extraction.
4. Add per-task validation and summary output.
5. Run one image-set with real ZedProfiler on Alpine.
6. Run 4-8 image-sets independently.
7. Compare independent execution to batch size 2 only if tasks are short.

Do not include full dataset scale, GPU segmentation, SAMMed3D, profile merging,
or production data movement in the first slice.

## Scaling Gates

Scale only after these gates pass:

- formascute synthetic Alpine checks pass from a fresh clone
- ZedProfiler `uv` environment builds reproducibly on Alpine
- one real image-set completes and validates
- 4-8 real image-sets complete and validate
- `trace.tsv` and `slurm.tsv` show acceptable queue wait and memory use
- failed-task behavior is understood
- CURC has reviewed the intended `queueSize`, partition, QoS, and job volume

## Not The North Star

Avoid these as first moves:

- replacing scientific feature code before orchestration is stable
- using the base Alpine Python environment for ZedProfiler
- keeping nested parent/child `sbatch` submission for new work
- moving directly to Slurm job arrays
- submitting hundreds of tiny jobs before real task duration is known
- combining CPU and GPU work in one Nextflow profile
- using production NF1 data as the first validation target

## Current Best Bet

The best direction today is a thin Nextflow wrapper around NF1 Stage 3 that
consumes a manifest of image-set work items and runs ZedProfiler in a controlled
`uv` Python 3.11+ environment. Start with independent CPU tasks on `acpu` /
`cpu-normal` through `Persistence1`, validate every output, collect trace and
Slurm accounting, and tune batching only after real image-set runtimes show
whether repeated image loading or scheduler overhead dominates.
