# Production Checklist

Use this checklist before increasing run size on an HPC system.

## First Clone

```bash
git clone <repo-url> formascute
cd formascute
make check
make doctor
make preflight ACCOUNT=<allocation>
make submit-dry-run EXPERIMENT=nf1_featurization_independent ITEMS=16 ACCOUNT=<allocation>
```

Review `results/<run-id>/preflight/` before submitting work.

Confirm:

- `nextflow-version.txt` shows a runnable Nextflow installation.
- `sinfo-target-partition.txt` includes the requested partition.
- `sacctmgr-user.txt` shows the expected allocation and QoS when available.
- `container-runtime.txt` shows Singularity or Apptainer.
- `summary.txt` records the expected account, partition, and QoS.
- `results/<run-id>/coordinator.sbatch` from `submit-dry-run` has the expected
  Slurm directives.

Expected Alpine defaults:

- partition: `acpu`
- QoS: `cpu-normal`
- Nextflow module: `nextflow/25.10.2`
- submit host: `Persistence1`

## First Scheduler Run

Submit the smallest Slurm-backed experiment:

```bash
make submit EXPERIMENT=independent_jobs ITEMS=4 ACCOUNT=<allocation> SUBMIT_HOST=Persistence1
```

Review the run directory after completion.

Confirm:

- `completion_status.txt` reports `nextflow_exit_status: 0`.
- `validation.json` reports `"valid": true`.
- `trace.tsv` exists and includes Slurm native job IDs.
- `slurm.tsv` exists when accounting is available.
- `coordinator_<jobid>.out` and `coordinator_<jobid>.err` do not contain module,
  filesystem, scheduler, or container errors.

## Scale-Up Rule

Increase only one setting at a time. Prefer this sequence:

1. `EXPERIMENT=nf1_minimal_overhead ITEMS=1`
2. `EXPERIMENT=nf1_featurization_independent ITEMS=4`
3. `EXPERIMENT=nf1_featurization_independent ITEMS=16`
4. `EXPERIMENT=nf1_featurization_batched_2 ITEMS=16 BATCH_SIZE=2`
5. `EXPERIMENT=nf1_featurization_batched ITEMS=16 BATCH_SIZE=4`
6. `EXPERIMENT=nf1_queue_size_4 ITEMS=16`
7. `EXPERIMENT=nf1_queue_size_20 ITEMS=16`
8. `EXPERIMENT=nf1_submit_rate_4 ITEMS=16`

Stop and review artifacts whenever validation fails, retry behavior appears, or
queue wait differs from expectations.
