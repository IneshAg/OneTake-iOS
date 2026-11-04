# OneTake dataset catalog

This catalog separates datasets that are downloaded and usable from datasets
that still require license or size review. Dataset suitability is not the same
as permission to train or redistribute.

## Downloaded

| Dataset | License | Local asset | Use |
|---|---|---|---|
| [Inkwell screenplay-format-edge-cases](https://huggingface.co/datasets/Inkwell-Software/screenplay-format-edge-cases) | CC0-1.0 | `data/raw/sides/inkwell-screenplay-format-edge-cases.jsonl` | Script-parser edge cases |
| [Rattata screenplay-format-conventions](https://huggingface.co/datasets/Rattata/screenplay-format-conventions) | CC0-1.0 | `data/raw/sides/rattata-*.json` | Scene-heading, cue, transition, and glossary rules |

The download manifest and SHA-256 records are in
`data/manifests/collection.jsonl`.

## Candidate OCR evaluation datasets

| Dataset | License status | Assessment |
|---|---|---|
| [ICDAR2019 SROIE mirror](https://huggingface.co/datasets/jsdnrs/ICDAR2019-SROIE) | CC BY 4.0 tag | Useful for photographed document OCR, but receipts are not casting notices or screenplay pages. Use for robustness evaluation, not domain training without review of upstream terms. |
| [OCRBench](https://huggingface.co/datasets/echo840/OCRBench) | No license tag verified | Do not download for training until the upstream terms are confirmed. |
| [NVIDIA OCR Synthetic Multilingual v1](https://huggingface.co/datasets/nvidia/OCR-Synthetic-Multilingual-v1) | Requires dataset-card review | Potentially useful for multilingual OCR; confirm redistribution and commercial-use terms first. |

## Candidate pose datasets

| Dataset | License status | Size/fit |
|---|---|---|
| [StevenLe456/head-pose](https://huggingface.co/datasets/StevenLe456/head-pose) | No license tag verified | About 13,950 images and roughly 1.3 GB; inspect labels and terms before downloading. |
| 300W-LP | Research dataset; terms must be checked | Broad yaw coverage, but not a casting/headshot-quality dataset. |
| AFLW | Research dataset; terms must be checked | Broad face/landmark variation; not a direct front/left/right product benchmark. |
| BIWI Kinect Head Pose | Research dataset; terms must be checked | Calibrated pose labels; controlled capture differs from phone headshots. |

## Required custom evaluation set

Public datasets do not fully represent OneTake's inputs. Build a small,
permission-cleared evaluation set with:

- digital casting notices;
- scanned and photographed PDF pages;
- browser/screenshot artifacts;
- screenplay sides with multiple roles;
- front, left-profile, and right-profile headshots;
- labels for yaw, pitch, roll, distance, shoulder tilt, lighting, and
  acceptable/ unacceptable framing.

Keep the private Pilgrimage PDF and any user-submitted images outside the
repository unless redistribution permission is obtained.
