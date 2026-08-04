# NF1 3D Organoid Pipeline Target

FormaScute is aimed at improving the Alpine execution model for
`WayScience/NF1_3D_organoid_profiling_pipeline`.

The current NF1 pipeline uses Slurm directly from shell scripts. The largest
scheduler pressure appears in Stage 3 feature extraction and Stage 4 profile
merging, where parent scripts read work lists, throttle with `squeue`, and submit
many child jobs with `sbatch`.

Relevant current behavior:

- Stage 3 featurization submits one child job per patient, well-FOV, feature,
  compartment, channel, and processor combination.
- Stage 3 throttles based on the user's queued/running Slurm job count.
- Stage 4 profile merging submits one child job per patient and well-FOV.
- Alpine CPU jobs use `amilan`; GPU jobs use `aa100`.
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

## Initial Experiments

Use only synthetic work in this phase:

```bash
make submit EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=<allocation>
make submit EXPERIMENT=nf1_featurization_batched ITEMS=16 BATCH_SIZE=4 ACCOUNT=<allocation>
make submit EXPERIMENT=nf1_queue_size_20 ITEMS=16 ACCOUNT=<allocation>
```

Interpretation:

- `nf1_featurization_independent` approximates the current one-child-job-per-work
  item pattern.
- `nf1_featurization_batched` tests whether grouping well-FOV-like work reduces
  queue pressure.
- `nf1_queue_size_20` tests a conservative Nextflow queue size well below the
  pipeline's documented 990-user-job scale.

## What This Does Not Answer Yet

These experiments do not measure image-processing runtime, GPU memory, CellPose,
SAMMed3D, DuckDB, or parquet performance. They only characterize scheduler,
submission, retry, validation, and artifact behavior with a small controlled
workload.

Do not use NF1 image data in this phase. Data-based testing belongs in a later
phase, after synthetic runs have shown stable submission, accounting,
validation, and retry behavior on Alpine.
