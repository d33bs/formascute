#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

params.image1 = null
params.label1 = null
params.image2 = null
params.outdir = 'results/real-feature-probe'

process REAL_FEATURE_PROBE {
  publishDir params.outdir, mode: 'copy'
  memory '4 GB'
  cpus 2

  input:
  path image1_file
  path label1_file
  path image2_file

  output:
  path 'result.json'

  script:
  """
  set -euo pipefail

  python3 - <<'PY'
import json
import time

import numpy as np
import tifffile

from zedprofiler.featurization.colocalization import compute_colocalization
from zedprofiler.featurization.granularity import compute_granularity
from zedprofiler.featurization.intensity import compute_intensity
from zedprofiler.featurization.neighbors import compute_neighbors
from zedprofiler.featurization.texture import compute_texture
from zedprofiler.featurization.volumesizeshape import compute_volume_size_shape
from zedprofiler.IO.loading_classes import (
    ImageSetConfig,
    ImageSetLoader,
    ObjectLoader,
    TwoObjectLoader,
)

image = tifffile.imread("${image1_file}")
label = tifffile.imread("${label1_file}")
image2 = tifffile.imread("${image2_file}")

image_set_loader = ImageSetLoader(
    image_set_path=None,
    label_set_path=None,
    image_set_array=image,
    label_set_array=label,
    anisotropy_spacing=(1.0, 1.0, 1.0),
    channel_mapping={"DNA": "probe_image", "Nuclei": "SegmentationMask"},
    config=ImageSetConfig(
        image_set_name="real_feature_probe",
        label_key_name=["Nuclei"],
        raw_image_key_name=["DNA"],
    ),
)
object_loader = ObjectLoader(
    image_set_loader=image_set_loader,
    channel_name="DNA",
    compartment_name="Nuclei",
)

timings = {}
rows = {}


def _run(name, fn):
    t0 = time.time()
    df = fn()
    timings[name] = round(time.time() - t0, 3)
    rows[name] = int(df.shape[0])
    numeric = df.select_dtypes("number").to_numpy()
    if not np.isfinite(numeric).all():
        raise SystemExit(f"{name} produced non-finite values")
    return df


_run("intensity", lambda: compute_intensity(object_loader))
_run(
    "volume_size_shape",
    lambda: compute_volume_size_shape(
        image_set_loader=image_set_loader, object_loader=object_loader
    ),
)
_run(
    "neighbors",
    lambda: compute_neighbors(object_loader, distance_threshold=50, anisotropy_factor=1),
)
_run("texture", lambda: compute_texture(object_loader, distance=1, grayscale=256))
_run(
    "granularity",
    lambda: compute_granularity(
        object_loader,
        radius=1,
        granular_spectrum_length=2,
        subsample_size=1.0,
        image_sample_size=1.0,
    ),
)

object_ids = [int(x) for x in np.unique(label) if x != 0]
coloc_loader = ImageSetLoader.__new__(ImageSetLoader)
coloc_loader.image_set_name = "real_feature_probe_coloc"
coloc_loader.image_set_dict = {
    "DNA1": image,
    "DNA2": image2,
    "Nuclei": label,
}
coloc_loader.unique_compartment_objects = {"Nuclei": object_ids}
two_object_loader = TwoObjectLoader(
    image_set_loader=coloc_loader,
    compartment="Nuclei",
    channel1="DNA1",
    channel2="DNA2",
)
_run(
    "colocalization",
    lambda: compute_colocalization(
        two_object_loader, channel1="DNA1", channel2="DNA2", fast_costes="Faster"
    ),
)

with open("result.json", "w") as fh:
    json.dump({"timings_s": timings, "rows": rows}, fh, indent=2)

print("REAL_NEXTFLOW_PROBE_OK", json.dumps(timings))
PY
  """
}

workflow {
  REAL_FEATURE_PROBE(file(params.image1), file(params.label1), file(params.image2))
}
