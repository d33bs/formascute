# HPC Quickstart

Clone the repository on the HPC login node, load the site modules, and run a
small characterization experiment from the repository root.

```bash
git clone <repo-url> formascute
cd formascute
make check
make doctor
make preflight ACCOUNT=<allocation>
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=<allocation>
make submit EXPERIMENT=independent_jobs ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
```

Each run writes a timestamped directory under `results/` with:

- `experiment.yaml`
- `trace.tsv`
- `timeline.html`
- `report.html`
- `dag.html`
- `validation.json`
- `summary.json`
- `questions.md`
- `preflight/`

Use `make doctor` and `make submit` from a login node. Avoid `make smoke` and
`make run` on login nodes unless CURC support specifically tells you the run is
acceptable there.

No installation step is required. If `make` is not available, use the equivalent
commands directly:

```bash
bash bin/formascute doctor
bash bin/formascute preflight --account <allocation>
bash bin/formascute submit nf1_featurization_independent --items 16 --account <allocation> --dry-run
bash bin/formascute submit independent_jobs --items 16 --account <allocation> --submit-host Persistence1
```

## Baseline And Experiments

The Alpine baseline lives in `conf/alpine.reference.config`. Treat it as the
control. Experiment configs in `conf/experiments/` change one setting at a time.

Initial experiments:

- `independent_jobs`: one work item per task.
- `batched_jobs`: multiple work items per task.
- `queue_size_20`: Slurm executor queue size set to 20.
- `nf1_minimal_overhead`: one tiny synthetic item to measure coordinator overhead.
- `nf1_featurization_independent`: small approximation of the NF1 Stage 3
  parent/child fan-out pattern.
- `nf1_featurization_batched_2`: same synthetic NF1-like work grouped in pairs.
- `nf1_featurization_batched`: same synthetic NF1-like work grouped into
  batches.
- `nf1_queue_size_4`: NF1-like independent work with a very small queue size.
- `nf1_queue_size_20`: NF1-like independent work with a conservative queue size.
- `nf1_submit_rate_4`: NF1-like independent work with slow submission rate.
- `nf1_submit_rate_prod_ratio`: NF1-like independent work at the exact CURC-
  suggested production shape (`queueSize=200`, `submitRateLimit='200 / 60 min'`).
  Confirms the rate limiter paces every submission from job 1, not just once
  near the 200-job ceiling; see `docs/alpine-findings.md`.
- `zp_apptainer_probe`: same synthetic workload as `zp_synthetic_features`, but
  routed through a project-owned Apptainer image with the same dependency set
  as the validated `uv` environment. Requires
  `FORMASCUTE_ENABLE_CONTAINER=true` and a pre-built
  `/projects/$USER/software/apptainer/zedprofiler.sif`; see
  `docs/alpine-findings.md` for the build recipe and the `procps` gotcha.

Run examples:

```bash
make submit EXPERIMENT=independent_jobs ITEMS=32 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=batched_jobs ITEMS=16 BATCH_SIZE=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_minimal_overhead ITEMS=1 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_batched_2 ITEMS=16 BATCH_SIZE=2 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_featurization_batched ITEMS=16 BATCH_SIZE=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_queue_size_4 ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_submit_rate_4 ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make submit EXPERIMENT=nf1_submit_rate_prod_ratio ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
make run EXPERIMENT=independent_jobs ITEMS=32
make run EXPERIMENT=batched_jobs ITEMS=16 BATCH_SIZE=4
make run EXPERIMENT=queue_size_20 ITEMS=32
```

## Arguments

- `EXPERIMENT`: experiment config name from `conf/experiments/`, without
  `.config`.
- `ITEMS`: number of synthetic work items to run.
- `BATCH_SIZE`: number of work items per Nextflow task. Defaults to `1`,
  `8` for `batched_jobs`, and `4` for `nf1_featurization_batched`.
- `RUN_ID`: output directory name under `results/`. Defaults to a UTC timestamp.
- `PROFILE`: Nextflow profile for `make run`. Defaults to `alpine`.
- `ACCOUNT`: Slurm account/allocation for `make submit`. Defaults to no explicit
  account.
- `PARTITION`: Slurm partition for `make submit`. Defaults to `acpu`.
- `QOS`: Slurm QoS for `make submit`. Defaults to `cpu-normal`.
- `SUBMIT_HOST`: optional SSH host used to run `sbatch`. On Alpine, use
  `Persistence1`; it is the selected submission location for this project.

Useful environment overrides:

- `FORMASCUTE_NEXTFLOW_MODULE`: module loaded by generated Slurm scripts.
  Defaults to `nextflow/25.10.2`.
- `FORMASCUTE_CONTAINER_MODULE`: optional container module loaded by generated
  Slurm scripts.
- `FORMASCUTE_ENABLE_CONTAINER`: enable Nextflow Singularity support. Defaults
  to `false` for the synthetic experiments.
- `FORMASCUTE_ENV_DIR`: bootstrap environment directory. Defaults to
  `.formascute/conda`.
- `FORMASCUTE_SUBMIT_HOST`: same behavior as `SUBMIT_HOST`.
- `FORMASCUTE_SCRATCH`: shared scratch root. Defaults to `/scratch/alpine/$USER`.
- `FORMASCUTE_PROJECT`: project/cache root. Defaults to `/projects/$USER`.

When behavior is unclear, share the complete run directory with HPC support.
