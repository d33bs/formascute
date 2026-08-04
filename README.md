# formascute

Reveal the shape of workflow execution.

formascute takes its name from shape and scute: the patterned plates on a turtle
shell. The project is about seeing the shape of the shell before we need it,
making each layer of workflow execution visible before production science
depends on it. 🐢

formascute runs small, reproducible characterization experiments for workflow
engines on HPC systems. It starts from a known-working deployment, changes one
execution setting at a time, validates correctness, and records enough
provenance to make scheduler and filesystem behavior discussable with HPC
engineers.

formascute is not a benchmarking suite. The goal is to understand execution
behavior before running production science.

## Quick Start

From the repository root:

```bash
make check
make doctor
make smoke
```

On an HPC system with Nextflow and Slurm:

```bash
module load nextflow
module load singularity
make check
make doctor
make preflight ACCOUNT=amc-general
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=amc-general
make submit EXPERIMENT=independent_jobs ITEMS=16 ACCOUNT=amc-general
```

Run outputs are written to `results/<run-id>/`.
Preflight output is written to `results/<run-id>/preflight/`.

## Entry Points

- `make check`: verify the cloned repository has the expected local files and a
  writable `results/` directory.
- `make lint`: run shell, Markdown, and best-effort Nextflow lint checks.
- `make prek`: run the same lint configuration used by pull request CI.
- `make doctor`: show available runtime tools.
- `make preflight ACCOUNT=amc-general`: record Slurm, module, filesystem, and
  runtime context without submitting work.
- `make smoke`: run a tiny local Nextflow check.
- `make run EXPERIMENT=independent_jobs ITEMS=16`: run directly.
- `make submit EXPERIMENT=independent_jobs ITEMS=16`: submit the Nextflow
  coordinator with `sbatch`.
- `make submit-dry-run EXPERIMENT=independent_jobs ITEMS=16`: generate the
  coordinator script and preflight files without submitting to Slurm.
- `bin/formascute doctor`: show available runtime tools.
- `bin/formascute run-local-smoke`: run a tiny local Nextflow check.
- `bin/formascute run EXPERIMENT --profile alpine`: run an experiment with the
  Slurm baseline profile.
- `bin/formascute submit EXPERIMENT`: submit the Nextflow coordinator with
  `sbatch`.

No installation step is required. Clone the repository on the HPC system and run
the Make targets from the repository root. If `make` is unavailable, use the
matching `bash bin/formascute` commands directly.

Available initial experiments:

- `independent_jobs`
- `batched_jobs`
- `queue_size_20`
- `nf1_featurization_independent`
- `nf1_featurization_batched`
- `nf1_queue_size_20`

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

See `docs/clone-ready.md` for the first clone-and-run sequence,
`docs/hpc-quickstart.md` for HPC usage notes,
`docs/production-checklist.md` for first-run validation,
`docs/nf1-pipeline-target.md` for the target pipeline, and `PLAN.md` for the
project direction.
