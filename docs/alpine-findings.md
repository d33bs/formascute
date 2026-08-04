# Alpine Findings

These findings come from small synthetic formascute runs on CURC Alpine. No NF1
image data were used.

## Validated Setup

- Submit from the Alpine login node with `SUBMIT_HOST=Persistence1`.
- `Persistence1` is the selected submission location for this project.
- Use the project allocation supplied by the user.
- Use partition `acpu` and QoS `cpu-normal`.
- The coordinator job loads `nextflow/25.10.2`.
- `Persistence1` exposes the Nextflow module tree; the regular login node did
  not expose that module during testing.
- `/usr/bin/apptainer` and `/usr/bin/singularity` are available on the tested
  compute environment.

The validated smoke command was:

```bash
make submit EXPERIMENT=nf1_featurization_independent ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1 RUN_ID=remote-smoke-persistence
```

Result:

- coordinator job completed
- Nextflow exit status was `0`
- validation passed
- `trace.tsv` contained native Slurm job IDs
- `slurm.tsv` was collected

## Small Experiment Results

All runs validated successfully.

| mode | experiment | items | batch | coordinator elapsed | native jobs | median wait |
| --- | --- | ---: | ---: | --- | ---: | ---: |
| burst | `nf1_minimal_overhead` | 1 | 1 | 00:00:21 | 2 | 1 s |
| burst | `nf1_featurization_independent` | 4 | 1 | 00:00:27 | 5 | 1 s |
| burst | `nf1_featurization_independent` | 16 | 1 | 00:00:52 | 17 | 1 s |
| burst | `nf1_featurization_batched_2` | 16 | 2 | 00:00:41 | 9 | 1 s |
| burst | `nf1_featurization_batched` | 16 | 4 | 00:00:37 | 5 | 0 s |
| burst | `nf1_queue_size_4` | 16 | 1 | 00:00:57 | 17 | 0 s |
| burst | `nf1_queue_size_20` | 16 | 1 | 00:01:06 | 17 | 0 s |
| burst | `nf1_submit_rate_4` | 16 | 1 | 00:04:16 | 17 | 1 s |
| sequential | `nf1_featurization_independent` | 16 | 1 | 00:00:51 | 17 | 1 s |
| sequential | `nf1_featurization_batched_2` | 16 | 2 | 00:00:42 | 9 | 1 s |
| sequential | `nf1_featurization_batched` | 16 | 4 | 00:00:41 | 5 | 1 s |
| sequential | `nf1_queue_size_4` | 16 | 1 | 00:01:02 | 17 | 1 s |
| burst | `zp_synthetic_features` | 4 | 1 | about 00:00:42 | 5 | 0-1 s |

## ZedProfiler-Shaped Probe

`zp_synthetic_features` is a tiny generated-volume workload shaped after
ZedProfiler's CPU-first 3D feature extraction. It creates small object-like
volumes, computes intensity and volume-style summaries, records deterministic
feature checksums, and validates expected item completion. It does not import
ZedProfiler or use NF1 image data.

The validated command was:

```bash
make submit EXPERIMENT=zp_synthetic_features ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1 RUN_ID=zp-sim-01
```

Result:

- coordinator job completed
- Nextflow exit status was `0`
- validation passed for 4 expected items
- the run emitted 16 feature rows
- `trace.tsv` contained 4 feature tasks and 1 validation task
- Slurm accounting showed feature tasks completed in about 1-3 seconds each
- peak RSS for feature tasks was about 9-32 MB

The base Python environment on `Persistence1` is not sufficient for real
ZedProfiler execution:

- Python: 3.9.13
- NumPy: 1.21.5
- Pandas: 1.4.4
- scikit-image: 0.19.2
- missing: `mahotas`, `pyarrow`, `zedprofiler`

ZedProfiler requires Python `>=3.11,<3.15` and depends on packages that are not
present in the tested base environment. A production NF1/ZedProfiler run should
therefore use a project-owned environment or container instead of the default
`Persistence1` Python.

## Interpretation

- Nextflow can successfully submit and track Slurm jobs on Alpine when submitted
  through `Persistence1`.
- Queue wait was negligible for these tiny runs, usually around 0-1 seconds.
- The fixed overhead for a one-item run was about 21 seconds.
- Independent 16-item fan-out completed in about 51-52 seconds.
- Batching reduced the number of Slurm jobs and slightly reduced elapsed time.
- Batch size 4 was fastest in the burst run, but only slightly faster than batch
  size 2 in the sequential run.
- `queueSize=4` was slower than the default independent run at this scale.
- `submitRateLimit='4 / 1 min'` was much slower and should not be the first
  control knob for NF1-style work.
- The ZedProfiler-shaped probe behaved like the earlier tiny fan-out tests:
  scheduler wait was negligible, and task overhead dominated actual work.

## Recommended NF1 Orchestration Direction

Start with a Nextflow wrapper around the existing Stage 3 CPU featurization work
list rather than rewriting feature code.

Recommended first implementation:

- Generate a manifest equivalent to `3.cellprofiling/load_data/load_combinations.txt`.
- Use one Nextflow process for CPU featurization work items.
- Keep the existing Python feature scripts as the task payload.
- Use Slurm executor with `acpu`, `cpu-normal`, and account configuration.
- Build an explicit ZedProfiler runtime environment before real data tests.
- Start with independent jobs for real feature tasks when each task loads a
  single image-set and runs enough feature work to amortize Slurm overhead.
- Add optional batching when individual feature calls are very short or repeatedly
  reload the same image data.
- Prefer batch sizes of 2-4 when batching is needed.
- Do not start with aggressive submit-rate throttling.
- Use `queueSize` as the first scheduler pressure control, then tune only after
  observing real queue behavior.
- Consider changing the NF1/ZedProfiler integration so one task can load an
  image-set once and compute multiple compatible feature families before writing
  outputs. That direction should reduce repeated image I/O compared with one
  Slurm job per feature family, channel, and compartment.

Avoid for the first production-facing iteration:

- Rewriting the image-processing code.
- Moving directly to Slurm job arrays.
- Mixing CPU and GPU work in one executor profile.
- Running real NF1 image data before a tiny real-work probe is designed.
- Relying on the base `Persistence1` Python environment for ZedProfiler.

## Questions For CURC

Ask CURC these before scaling:

- Should production runs use `acpu`/`cpu-normal` now, or keep compatibility with
  `amilan`/`normal` during the transition?
- What `queueSize` range is recommended for Nextflow on Alpine under the
  documented user job limit?
- Is a moderate burst of independent jobs preferred over submit-rate throttling
  for small jobs?
- Are Slurm job arrays recommended for this workload, or is Nextflow-managed
  independent submission easier for accounting and retries?
- Should CPU featurization and SAMMed3D GPU work be split into separate Nextflow
  profiles and runs?
- Should ZedProfiler be installed as a project conda/uv environment or as an
  Apptainer image for production NF1 runs?
