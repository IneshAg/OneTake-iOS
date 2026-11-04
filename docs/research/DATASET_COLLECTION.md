# OneTake dataset collection

OneTake currently uses Apple's Vision and PDFKit. It does **not** ship a custom
OCR or head-pose model. This collection tool is for creating an auditable
evaluation/training corpus before deciding whether a custom Core ML model is
necessary.

## What belongs in the corpus

- `notice`: public casting notices and flyers
- `sides`: screenplay or audition-side documents
- `ocr`: scanned or photographed document samples with permission to use them
- `pose`: licensed front, left-profile, and right-profile face images

Pose labels should record the source label and, when available, continuous yaw,
pitch, and roll. Do not reduce a continuous pose dataset to three classes until
the evaluation thresholds are chosen.

## Collector safeguards

[`download_approved_datasets.py`](../../scripts/download_approved_datasets.py) is
the manifest-driven downloader. The existing
[`collect_audition_dataset.py`](../../scripts/collect_audition_dataset.py) creates
synthetic fixtures and is not a real-world dataset scraper. The downloader:

- downloads only HTTPS URLs explicitly listed by the researcher;
- requires a license or permission value for every record;
- checks the source site's `robots.txt`;
- rate-limits requests per host;
- limits download size;
- records retrieval time, MIME type, byte count, path, and SHA-256;
- never searches, crawls, logs in, or bypasses anti-bot controls.

The collector cannot verify that a license claim is true. The researcher must
retain the license or permission evidence separately.

## Usage

```bash
/usr/bin/python3 scripts/download_approved_datasets.py \
  scripts/approved_dataset_manifest.jsonl \
  --output data
```

Validate URLs and robots rules without downloading:

```bash
/usr/bin/python3 scripts/download_approved_datasets.py \
  scripts/approved_dataset_manifest.jsonl \
  --dry-run
```

The example manifest is intentionally not downloadable. Replace its URLs only
after checking the dataset card or publisher terms. Do not add private
Instagram material, authenticated pages, or the supplied Pilgrimage PDF unless
you have permission to use and redistribute them.
