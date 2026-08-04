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

def zpVoxels = (params.zp_z as int) * (params.zp_y as int) * (params.zp_x as int)
if (zpVoxels > (params.max_zp_voxels as int)) {
  error "ZedProfiler synthetic volume exceeds ${params.max_zp_voxels} voxels"
}

if ((params.zp_objects as int) > (params.max_zp_objects as int)) {
  error "params.zp_objects exceeds ${params.max_zp_objects}"
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
import math
import statistics
import time
from pathlib import Path

batch_id = ${batch_id}
item_ids = [int(value) for value in "${itemCsv}".split(",") if value]
should_fail = "${should_fail}" == "true"
sleep_seconds = ${params.sleep_seconds}
cpu_seconds = ${params.cpu_seconds}
mem_mb = ${params.mem_mb}
io_mb = ${params.io_mb}
workload = "${params.workload}"
zp_shape = (${params.zp_z}, ${params.zp_y}, ${params.zp_x})
zp_objects = ${params.zp_objects}

if should_fail:
    raise SystemExit(f"Intentional failure for batch {batch_id}")

scratch = Path(f"scratch_{batch_id}")
scratch.mkdir(exist_ok=True)

def run_basic_work(item_id):
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
    return {
        "checksum": checksum,
        "feature_rows": 0,
        "feature_checksum": "",
        "shape": "",
    }

def run_zedprofiler_sim(item_id):
    z_size, y_size, x_size = zp_shape
    cube = 3
    records = []
    digest = hashlib.sha256()

    for object_id in range(1, zp_objects + 1):
        z0 = 1 + ((item_id + object_id) % max(1, z_size - cube - 1))
        y0 = 1 + ((item_id * 3 + object_id * 5) % max(1, y_size - cube - 1))
        x0 = 1 + ((item_id * 7 + object_id * 11) % max(1, x_size - cube - 1))
        values = []
        weighted_z = weighted_y = weighted_x = 0.0

        for z in range(z0, z0 + cube):
            for y in range(y0, y0 + cube):
                for x in range(x0, x0 + cube):
                    value = ((item_id * 17 + object_id * 31 + z * 3 + y * 5 + x * 7) % 251) + 1
                    values.append(value)
                    weighted_z += z * value
                    weighted_y += y * value
                    weighted_x += x * value

        integrated = sum(values)
        volume = len(values)
        mean_value = integrated / volume
        center_z = sum(range(z0, z0 + cube)) / cube
        center_y = sum(range(y0, y0 + cube)) / cube
        center_x = sum(range(x0, x0 + cube)) / cube
        intensity_z = weighted_z / integrated
        intensity_y = weighted_y / integrated
        intensity_x = weighted_x / integrated
        displacement = math.sqrt(
            (center_z - intensity_z) ** 2
            + (center_y - intensity_y) ** 2
            + (center_x - intensity_x) ** 2
        )
        row = {
            "item_id": item_id,
            "object_id": object_id,
            "volume_voxels": volume,
            "integrated_intensity": integrated,
            "mean_intensity": round(mean_value, 6),
            "std_intensity": round(statistics.pstdev(values), 6),
            "min_intensity": min(values),
            "max_intensity": max(values),
            "mass_displacement": round(displacement, 6),
        }
        encoded = json.dumps(row, sort_keys=True).encode()
        digest.update(encoded)
        digest.update(b"\\n")
        records.append(row)

    feature_path = scratch / f"item_{item_id}_zp_features.jsonl"
    feature_path.write_text(
        "".join(json.dumps(record, sort_keys=True) + "\\n" for record in records)
    )
    return {
        "checksum": "",
        "feature_rows": len(records),
        "feature_checksum": digest.hexdigest(),
        "shape": f"{z_size}x{y_size}x{x_size}",
    }

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

        if workload == "basic":
            payload = run_basic_work(item_id)
        elif workload == "zedprofiler_sim":
            payload = run_zedprofiler_sim(item_id)
        else:
            raise SystemExit(f"Unsupported workload: {workload}")

        end_epoch = int(time.time())
        handle.write(json.dumps({
            "item_id": item_id,
            "batch_id": batch_id,
            "start_epoch": start_epoch,
            "end_epoch": end_epoch,
            "workload": workload,
            "checksum": payload["checksum"],
            "feature_rows": payload["feature_rows"],
            "feature_checksum": payload["feature_checksum"],
            "shape": payload["shape"],
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
    'workload': '${params.workload}',
    'items': expected_items,
    'batch_size': ${batchSize},
    'valid': valid,
    'min_item_seconds': min(durations) if durations else None,
    'max_item_seconds': max(durations) if durations else None,
    'total_item_seconds': sum(durations),
    'feature_rows': sum(int(record.get('feature_rows') or 0) for record in records),
    'feature_checksums': sorted(
        record.get('feature_checksum')
        for record in records
        if record.get('feature_checksum')
    ),
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
