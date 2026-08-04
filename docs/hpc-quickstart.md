# HPC Quickstart

Clone the repository on the HPC login node, load the site modules, and run a
small characterization experiment from the repository root.

```bash
git clone <repo-url> formascute
cd formascute
module load nextflow
module load singularity
make check
make doctor
make preflight ACCOUNT=amc-general
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=amc-general
make submit EXPERIMENT=independent_jobs ITEMS=16 ACCOUNT=amc-general
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
bash bin/formascute preflight --account amc-general
bash bin/formascute submit nf1_featurization_independent --items 16 --account amc-general --dry-run
bash bin/formascute submit independent_jobs --items 16 --account amc-general
```

## Baseline And Experiments

The Alpine baseline lives in `conf/alpine.reference.config`. Treat it as the
control. Experiment configs in `conf/experiments/` change one setting at a time.

Initial experiments:

- `independent_jobs`: one work item per task.
- `batched_jobs`: multiple work items per task.
- `queue_size_20`: Slurm executor queue size set to 20.
- `nf1_featurization_independent`: small approximation of the NF1 Stage 3
  parent/child fan-out pattern.
- `nf1_featurization_batched`: same synthetic NF1-like work grouped into
  batches.
- `nf1_queue_size_20`: NF1-like independent work with a conservative queue size.

Run examples:

```bash
make submit EXPERIMENT=independent_jobs ITEMS=32 ACCOUNT=amc-general
make submit EXPERIMENT=batched_jobs ITEMS=16 BATCH_SIZE=4 ACCOUNT=amc-general
make submit EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=amc-general
make submit EXPERIMENT=nf1_featurization_batched ITEMS=16 BATCH_SIZE=4 ACCOUNT=amc-general
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
- `PARTITION`: Slurm partition for `make submit`. Defaults to `amilan`.
- `QOS`: Slurm QoS for `make submit`. Defaults to `normal`.

Useful environment overrides:

- `FORMASCUTE_NEXTFLOW_MODULE`: module loaded by generated Slurm scripts.
  Defaults to `nextflow`.
- `FORMASCUTE_CONTAINER_MODULE`: container module loaded by generated Slurm
  scripts. Defaults to `singularity`.
- `FORMASCUTE_SCRATCH`: shared scratch root. Defaults to `/scratch/alpine/$USER`.
- `FORMASCUTE_PROJECT`: project/cache root. Defaults to `/projects/$USER`.

When behavior is unclear, share the complete run directory with HPC support.
