#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

def outdir = params.outdir ?: "results/${params.run_id ?: 'manual'}"
def items = params.items as int
def batchSize = params.batch_size as int
def failItems = (params.fail_items ?: '')
  .split(',')
  .collect { it.trim() }
  .findAll { it }
  .collect { it as int }
  .toSet()

if (items < 1 || items > (params.max_items as int)) {
  error "params.items must be between 1 and ${params.max_items}"
}

if (batchSize < 1 || batchSize > (params.max_batch_size as int)) {
  error "params.batch_size must be between 1 and ${params.max_batch_size}"
}

if ((params.sleep_seconds as int) > (params.max_sleep_seconds as int)) {
  error "params.sleep_seconds exceeds ${params.max_sleep_seconds}"
}

if ((params.cpu_seconds as int) > (params.max_cpu_seconds as int)) {
  error "params.cpu_seconds exceeds ${params.max_cpu_seconds}"
}

if ((params.mem_mb as int) > (params.max_mem_mb as int)) {
  error "params.mem_mb exceeds ${params.max_mem_mb}"
}

if ((params.io_mb as int) > (params.max_io_mb as int)) {
  error "params.io_mb exceeds ${params.max_io_mb}"
}

process CHARACTERIZE_ITEM {
  tag { "batch_${batch_id}" }
  publishDir "${outdir}/work-items", mode: 'copy'

  input:
  tuple val(batch_id), val(item_ids), val(should_fail)

  output:
  path "batch_${batch_id}.jsonl"

  script:
  def itemCsv = item_ids.join(',')
  """
  set -euo pipefail

  python3 - <<'PY'
import hashlib
import json
import time
from pathlib import Path

batch_id = ${batch_id}
item_ids = [int(value) for value in "${itemCsv}".split(",") if value]
should_fail = "${should_fail}" == "true"
sleep_seconds = ${params.sleep_seconds}
cpu_seconds = ${params.cpu_seconds}
mem_mb = ${params.mem_mb}
io_mb = ${params.io_mb}

if should_fail:
    raise SystemExit(f"Intentional failure for batch {batch_id}")

scratch = Path(f"scratch_{batch_id}")
scratch.mkdir(exist_ok=True)

with Path(f"batch_{batch_id}.jsonl").open("w") as handle:
    for item_id in item_ids:
        start_epoch = int(time.time())
        time.sleep(sleep_seconds)

        if cpu_seconds > 0:
            end = time.time() + cpu_seconds
            value = 0
            while time.time() < end:
                value = (value + 1) % 1000003

        if mem_mb > 0:
            buf = bytearray(mem_mb * 1024 * 1024)
            buf[0] = 1
            buf[-1] = 1

        checksum = ""
        if io_mb > 0:
            path = scratch / f"item_{item_id}.bin"
            block = b"0" * 1024 * 1024
            digest = hashlib.sha256()
            with path.open("wb") as output:
                for _ in range(io_mb):
                    output.write(block)
                    digest.update(block)
            checksum = digest.hexdigest()

        end_epoch = int(time.time())
        handle.write(json.dumps({
            "item_id": item_id,
            "batch_id": batch_id,
            "start_epoch": start_epoch,
            "end_epoch": end_epoch,
            "checksum": checksum,
        }) + "\\n")
PY
  """
}

process VALIDATE_RESULTS {
  publishDir "${outdir}", mode: 'copy'

  input:
  path batch_files

  output:
  path 'validation.json'
  path 'summary.json'
  path 'questions.md'

  script:
  """
  set -euo pipefail

  python3 - <<'PY'
import json
from pathlib import Path

expected_items = ${items}
records = []
for path in sorted(Path('.').glob('batch_*.jsonl')):
    for line in path.read_text().splitlines():
        if line.strip():
            records.append(json.loads(line))

observed = sorted(record['item_id'] for record in records)
expected = list(range(1, expected_items + 1))
valid = observed == expected

validation = {
    'valid': valid,
    'expected_items': expected_items,
    'observed_items': len(records),
    'missing_items': sorted(set(expected) - set(observed)),
    'unexpected_items': sorted(set(observed) - set(expected)),
}

durations = [record['end_epoch'] - record['start_epoch'] for record in records]
summary = {
    'experiment': '${params.experiment}',
    'run_id': '${params.run_id ?: 'manual'}',
    'items': expected_items,
    'batch_size': ${batchSize},
    'valid': valid,
    'min_item_seconds': min(durations) if durations else None,
    'max_item_seconds': max(durations) if durations else None,
    'total_item_seconds': sum(durations),
}

Path('validation.json').write_text(json.dumps(validation, indent=2) + '\\n')
Path('summary.json').write_text(json.dumps(summary, indent=2) + '\\n')
Path('questions.md').write_text(
    '# Questions\\n\\n'
    '- Review trace.tsv and Slurm accounting for queue wait, retry behavior, and scheduler limits.\\n'
    '- If observed queue wait or retry behavior is unexpected, share this run directory with HPC support.\\n'
)

if not valid:
    raise SystemExit('Validation failed')
PY
  """
}

workflow {
  batches = Channel
    .fromList((1..items).collate(batchSize))
    .map { batch -> tuple(batch.first(), batch, batch.any { failItems.contains(it) }) }

  CHARACTERIZE_ITEM(batches)
  VALIDATE_RESULTS(CHARACTERIZE_ITEM.out.collect())
}
