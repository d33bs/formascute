# formascute

**formascute** is a reproducible characterization framework for
understanding how scientific workflows execute on HPC systems.

> *Reveal the shape of workflow execution.*

## Philosophy

formascute is **not** a benchmarking suite.

It is a characterization framework that helps answer engineering
questions about workflow execution by running small, reproducible
experiments against a known-working HPC configuration.

The project begins from a **known-good Alpine Nextflow deployment**
rather than inventing a new execution model. The provided `examples/run_sarek.sh`
launcher and `examples/curc_alpine.config` serve as the initial reference
implementation.

Each experiment changes **exactly one variable** while leaving
everything else untouched.

## Goals

- Understand execution behavior rather than maximize benchmark scores.
- Reach scientific results sooner by understanding scheduler behavior.
- Produce evidence that HPC engineers can interpret.
- Generate reproducible observations and targeted questions.
- Keep every experiment small, deterministic, and open source.

## Baseline

Start from the existing Alpine deployment:

- Coordinator launched with `sbatch`
- Nextflow loads as a module
- Singularity/Apptainer environment
- Existing `NXF_WORK`, `NXF_TEMP`, and `NXF_HOME`
- Existing Slurm executor configuration
- Existing queue, QoS, account, retry, and submission settings

Treat this configuration as the **control**.

## Repository layout

``` text
formascute/
├── README.md
├── PLAN.md
├── nextflow.config
├── conf/
│   ├── alpine.reference.config
│   ├── characterization.config
│   └── experiments/
├── workflows/
├── modules/
├── bin/
├── experiments/
├── reports/
├── results/
└── docs/
```

## Experiment philosophy

Each experiment:

1. Starts from the Alpine reference configuration.
2. Applies one configuration mutation.
3. Executes the same synthetic workflow.
4. Validates output correctness.
5. Collects Nextflow + Slurm metrics.
6. Produces observations.
7. Generates questions for HPC engineers if behavior is unexplained.

## Canonical synthetic workflow

```text
Manifest
   │
Fan out N work items
   │
Aggregate
   │
Validate
```

Synthetic work items support:

- CPU work
- Memory allocation
- I/O
- Sleep
- Controlled failures

No biological data are required.

## Initial execution strategies

- One Slurm job per Nextflow process
- Batched work items
- Slurm job arrays
- Persistent Nextflow coordinator

## Initial characterization dimensions

Only modify one at a time.

- queueSize
- submitRateLimit
- batching
- concurrency
- QoS
- partition
- retries
- work directory placement
- scratch usage

## Safety

Every experiment must define:

- maximum jobs
- maximum concurrent jobs
- maximum CPUs
- maximum memory
- maximum walltime
- maximum output size
- maximum retries

Experiments terminate immediately if limits are exceeded.

## Metrics

Capture:

- Nextflow trace
- Timeline
- Report
- DAG
- Slurm accounting
- Queue wait
- Runtime
- Retry behavior
- Output correctness

Primary metric:

> Time to validated scientific output.

## Deliverables

Each run produces:

```text
results/
└── run-id/
    ├── experiment.yaml
    ├── trace.tsv
    ├── report.html
    ├── timeline.html
    ├── slurm.tsv
    ├── validation.json
    ├── summary.json
    └── questions.md
```

## Questions for HPC engineers

formascute should never guess.

When observations cannot be explained, generate concise engineering
questions supported by reproducible evidence.

## Long-term vision

formascute becomes a reusable characterization framework that any
institution can point at an HPC cluster to understand workflow behavior
before running production-scale scientific analyses.
