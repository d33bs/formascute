# NF1 3D Organoid Pipeline Target

formascute is aimed at improving the Alpine execution model for
`WayScience/NF1_3D_organoid_profiling_pipeline`.

See `docs/north-star.md` for the current gold-standard direction for applying
these findings to the NF1 pipeline.

The current NF1 pipeline uses Slurm directly from shell scripts. The largest
scheduler pressure appears in Stage 3 feature extraction and Stage 4 profile
merging, where parent scripts read work lists, throttle with `squeue`, and submit
many child jobs with `sbatch`.

Relevant current behavior:

- Stage 3 featurization submits one child job per patient, well-FOV, feature,
  compartment, channel, and processor combination.
- Stage 3 throttles based on the user's queued/running Slurm job count.
- Stage 4 profile merging submits one child job per patient and well-FOV.
- Alpine CPU jobs use `acpu` with `cpu-normal`; GPU jobs use `aa100`.
- The README describes a maximum of 990 concurrent jobs per user.
- The pipeline uses both CPU and GPU jobs, with larger GPU work for SAMMed3D.
- Per well-FOV storage can be around 1-2 GB across raw, z-stack, mask, feature,
  and profile outputs.

## Characterization Questions

Start with scheduler behavior before touching real image data. These experiments
must stay synthetic, small, and reversible until Alpine behavior is understood.

1. Can Nextflow submit the same kind of fan-out workload more safely than the
   current parent/child shell scripts?
2. What `queueSize` and `submitRateLimit` keep Alpine responsive below the
   practical user job limit?
3. Does batching multiple well-FOV-like work items into one Slurm task reduce
   scheduler load without hiding failures or making retries too expensive?
4. Which work should stay as independent jobs because runtime or memory varies
   too much?
5. How should CPU and GPU work be separated so CPU queue pressure does not block
   SAMMed3D-style GPU tasks?
6. Should ZedProfiler work be grouped by image-set so one task loads data once
   and computes multiple compatible feature families?

## Initial Experiments

Use only synthetic work in this phase:

```bash
make submit EXPERIMENT=nf1_minimal_overhead ITEMS=1 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_batched_2 ITEMS=16 BATCH_SIZE=2 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_batched ITEMS=16 BATCH_SIZE=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_queue_size_4 ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_queue_size_20 ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_submit_rate_4 ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=zp_synthetic_features ITEMS=8 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
```

Interpretation:

- `nf1_minimal_overhead` estimates Nextflow + Slurm coordinator overhead before
  testing fan-out behavior.
- `nf1_featurization_independent` approximates the current one-child-job-per-work
  item pattern.
- `nf1_featurization_batched_2` tests a small batch size that may reduce job
  count without hiding much per-item variability.
- `nf1_featurization_batched` tests whether grouping well-FOV-like work reduces
  queue pressure.
- `nf1_queue_size_4` tests a very conservative active submission window.
- `nf1_queue_size_20` tests a conservative Nextflow queue size well below the
  pipeline's documented 990-user-job scale.
- `nf1_submit_rate_4` tests whether explicit submit-rate throttling changes queue
  wait or scheduler behavior separately from queue size.
- `zp_synthetic_features` approximates CPU-first 3D feature extraction using
  generated tiny volumes, object-like labels, intensity summaries, and feature
  checksums. It does not import ZedProfiler yet; it tests the orchestration
  shape before adding that dependency stack.

Use the resulting `trace.tsv` and `slurm.tsv` files to ask focused questions:

- Does Alpine prefer fewer larger batches, or many short independent jobs?
- Is queue wait dominated by scheduler load, submit rate, or job size?
- Are small jobs starting quickly enough to justify independent work items?
- Does `queueSize` or `submitRateLimit` better control scheduler pressure?
- Which limits should be set in a future Nextflow implementation before running
  real NF1 data?
- Does grouping by image-set reduce repeated image loading enough to justify
  larger, more vertical tasks?

## ZedProfiler Direction

ZedProfiler is CPU-first and documented as scalable across independent profiling
tasks. On Alpine, the base `Persistence1` Python environment is not ready for
real ZedProfiler work because it provides Python 3.9 and lacks required packages
such as `mahotas`, `pyarrow`, and `zedprofiler`.

For the NF1 refactor, prefer:

- a project-owned Python 3.11+ environment or Apptainer image for ZedProfiler
- a Nextflow process that consumes a manifest of image-set work items
- task payloads that can compute multiple compatible feature families after one
  image load
- independent Nextflow tasks first, with batch size 2-4 only when per-task
  runtime is too short or repeated image loading dominates

## What This Does Not Answer Yet

These experiments do not measure image-processing runtime, GPU memory, CellPose,
SAMMed3D, DuckDB, parquet performance, or real ZedProfiler dependency
installation. They only characterize scheduler, submission, retry, validation,
and artifact behavior with a small controlled workload.

Do not use NF1 image data in this phase. Data-based testing belongs in a later
phase, after synthetic runs have shown stable submission, accounting,
validation, and retry behavior on Alpine.
