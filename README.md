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
make check
make doctor
make preflight ACCOUNT=<allocation>
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=<allocation>
make submit EXPERIMENT=independent_jobs ITEMS=16 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
```

Run outputs are written to `results/<run-id>/`.
Preflight output is written to `results/<run-id>/preflight/`.

## Entry Points

- `make bootstrap`: optional fallback to create a repo-local conda environment
  with Nextflow and Java 17 when site modules do not provide them.
- `make check`: verify the cloned repository has the expected local files and a
  writable `results/` directory.
- `make lint`: run shell, Markdown, and best-effort Nextflow lint checks.
- `make prek`: run the same lint configuration used by pull request CI.
- `make doctor`: show available runtime tools.
- `make preflight ACCOUNT=<allocation>`: record Slurm, module, filesystem, and
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

## Alpine SSH Access

Agent-driven Alpine work assumes the local machine has an `ssh-alpine` shell
alias or equivalent SSH config entry. It should connect to the Alpine login node
using the user's CURC/ACCESS identity and SSH key, for example:

```bash
alias ssh-alpine='ssh -i ~/.ssh/<alpine_key> <username>@xsede.org@login.rc.colorado.edu'
```

The exact key path and username are user-specific. Configure SSH access following
CURC's AMC SSH key authentication guidance:
[SSH Key-Based Authentication for Anschutz Medical Campus](https://curc.readthedocs.io/en/latest/additional-resources/amc_ssh_auth.html).

The alias lets local automation run commands like:

```bash
zsh -lic 'ssh-alpine "hostname; pwd"'
```

Within Alpine, formascute submits workflow coordinator jobs through
`Persistence1` with `SUBMIT_HOST=Persistence1`.

Available initial experiments:

- `independent_jobs`
- `batched_jobs`
- `queue_size_20`
- `nf1_minimal_overhead`
- `nf1_featurization_independent`
- `nf1_featurization_batched_2`
- `nf1_featurization_batched`
- `nf1_queue_size_4`
- `nf1_queue_size_20`
- `nf1_submit_rate_4`
- `zp_synthetic_features`

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
  `Persistence1` so the Nextflow module tree is available at submission time.

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

See `docs/clone-ready.md` for the first clone-and-run sequence,
`docs/hpc-quickstart.md` for HPC usage notes,
`docs/production-checklist.md` for first-run validation,
`docs/alpine-findings.md` for validated Alpine observations,
`docs/nf1-pipeline-target.md` for the target pipeline,
`docs/north-star.md` for the current NF1 gold-standard direction, and `PLAN.md`
for the project direction.

See `CONTRIBUTING.md` for development expectations, `CODE_OF_CONDUCT.md` for
collaboration standards, and `CITATION.cff` for citation metadata.
