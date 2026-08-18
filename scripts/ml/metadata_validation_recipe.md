# Running the genuine metadata library on this machine

**This was recorded as `ENVIRONMENT_BLOCKED` for several passes. That was wrong**, and the way it
was wrong is worth keeping: `pip install tflite-support` was attempted *inside* a container, it
failed with `CERTIFICATE_VERIFY_FAILED`, and the conclusion drawn was that *this host* cannot reach
PyPI. The host reaches PyPI perfectly well. The interception CA is in the Windows trust store and
absent from `python:3-slim`'s bundle — so the failure was a property of the container, generalised
into a property of the environment.

The fix needs no TLS bypass, no `--trusted-host`, and no widening of the pipeline's stub. Download
on the host, where the certificate chain already validates; install offline in the container.

## The recipe

```powershell
# 1. On the Windows host, with certificate verification fully on.
python -m pip download `
  --only-binary=:all: --platform manylinux2014_x86_64 `
  --python-version 3.11 --implementation cp --abi cp311 `
  -d ./wheels tflite-support==0.4.4
# -> 9 wheels: tflite_support, absl_py, cffi, flatbuffers, numpy,
#    protobuf 3.20.3, pybind11, pycparser, sounddevice
```

```bash
# 2. In a Linux container. `libusb-1.0-0` is the one OS library the extension
#    needs; without it the import fails at
#    `_pywrap_metadata_version`, which is exactly the piece the pipeline stubs.
docker run --rm \
  -v "D:/Repo/_wt-formcoach:/repo:ro" \
  -v "$PWD/wheels:/w:ro" \
  python:3.11-slim bash -c \
  "apt-get -qq update && apt-get -qq install -y libusb-1.0-0 && \
   pip install --no-index --find-links /w tflite-support==0.4.4 && \
   python /repo/scripts/ml/validate_metadata.py \
     --model mobile/assets/models/equipment_v1.tflite"
```

The repository is mounted **read-only**, and `validate_metadata.py` reads a copy in a temporary
directory regardless — the champion is safe twice over, by mount and by construction.

## What it answered, 2026-08-18

```
INPUT_SHA256                 6f159ec32cd6c010c5319cb3436b22e97ce07ee72ff6f05daf02d3a2c7e696e3
RECORDED_MIN_PARSER_VERSION  1.0.0
COMPUTED_MIN_PARSER_VERSION  1.0.0
LABELS                       ['labels.txt']
INPUT_NORMALIZATION          [{'options_type': 'NormalizationOptions',
                               'options': {'mean': [0.0], 'std': [1.0]}}]
STATE                        VALIDATED_MATCH
```

**The stub's stamp was right.** That is a genuinely good outcome and it is worth being precise about
what it does and does not mean:

* It **does** mean the shipped `equipment_v1.tflite` declares a minimum parser version the real
  library agrees with, that its label file survived, and that its normalisation block is intact.
  Nobody had checked any of that before; the number was asserted by a function that returned the
  string `"1.0.0"` for any input at all.
* It **does not** retrospectively make the stub acceptable. The genuine function rejects an empty
  buffer with `The model metadata is not a valid FlatBuffer buffer`; the stub would have answered
  `1.0.0`. Being right by luck for one artefact is not a process.
* `mean=[0.0], std=[1.0]` means **no normalisation is applied** — the model expects raw 0–255 pixel
  values. That is a statement about the model, not about the metadata, and it is consistent rather
  than suspicious: the metadata correctly describes a model trained without input scaling.

## Why this is committed rather than left in a shell history

The row it settles was blocked on an environment nobody had actually established was blocking. A
recipe that lives only in a transcript reproduces that failure the next time somebody asks.
