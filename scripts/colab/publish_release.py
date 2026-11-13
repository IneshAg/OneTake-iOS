#!/usr/bin/env python3
"""OneTake Offline v2 Model Packager, Accuracy Gate & Release Publisher.

Validates held-out metrics from `scripts/colab/eval_offline_v2.py` against
the release accuracy gate (`submission_email >= 0.98`, `core_f1 >= 0.90`),
packages quantized Cactus weights (e.g. `lfm2.5-vl-450m-onetake-cq4`) into a
deterministic `.zip` archive, computes SHA-256 and `byteSize`, writes
`manifest.json` (`modelId`, `version`, `downloadURL`, `byteSize`, `sha256`,
`minAppVersion`), and optionally uploads to Hugging Face Hub or GitHub Releases.

Local packaging (`--target local`) and `--dry-run` use Python stdlib only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Any
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "artifacts" / "offline_v2" / "release"

DEFAULT_MODEL_ID = "lfm2.5-vl-450m-onetake-cq4"
DEFAULT_VERSION = "2.0.0"
DEFAULT_MIN_APP_VERSION = "2.0.0"
DEFAULT_MIN_EMAIL_ACCURACY = 0.98
DEFAULT_MIN_CORE_F1 = 0.90

REQUIRED_MANIFEST_KEYS: tuple[str, ...] = (
    "modelId",
    "version",
    "downloadURL",
    "byteSize",
    "sha256",
    "minAppVersion",
)

DETERMINISTIC_ZIP_TIMESTAMP = (2026, 1, 1, 0, 0, 0)


def extract_gate_metrics(report: dict[str, Any]) -> dict[str, Any]:
    """Extract held-out accuracy metrics from an `eval_offline_v2.py` report."""
    if not isinstance(report, dict):
        raise ValueError("Eval report must be a JSON object")

    exact_match = report.get("exact_match")
    if isinstance(exact_match, dict):
        if "submission_email" not in exact_match:
            raise ValueError("Eval report missing `exact_match.submission_email`")
        email_acc = exact_match["submission_email"]
        sides_acc = exact_match.get("sides_link")
    elif "submission_email" in report:
        email_acc = report["submission_email"]
        sides_acc = report.get("sides_link")
    elif "email" in report:
        email_acc = report["email"]
        sides_acc = report.get("sides_link")
    else:
        raise ValueError(
            "Eval report missing `exact_match.submission_email` (from eval_offline_v2.py)"
        )

    if "core_f1" not in report:
        raise ValueError("Eval report missing `core_f1`")

    samples = report.get("samples")
    return {
        "samples": int(samples) if samples is not None else None,
        "submission_email": float(email_acc),
        "sides_link": float(sides_acc) if sides_acc is not None else None,
        "core_f1": float(report["core_f1"]),
        "valid_json_rate": (
            float(report["valid_json_rate"]) if "valid_json_rate" in report else None
        ),
        "schema_valid_rate": (
            float(report["schema_valid_rate"]) if "schema_valid_rate" in report else None
        ),
    }


def check_accuracy_gate(
    report: dict[str, Any],
    *,
    min_email: float = DEFAULT_MIN_EMAIL_ACCURACY,
    min_core_f1: float = DEFAULT_MIN_CORE_F1,
    min_sides_link: float | None = None,
) -> dict[str, Any]:
    """Verify held-out metrics meet release thresholds; raise ValueError on failure."""
    metrics = extract_gate_metrics(report)
    failures: list[str] = []

    if metrics["samples"] is not None and metrics["samples"] <= 0:
        failures.append(f"samples={metrics['samples']} (must be > 0)")
    if metrics["submission_email"] < min_email:
        failures.append(
            f"submission_email={metrics['submission_email']:.4f} < {min_email:.4f}"
        )
    if metrics["core_f1"] < min_core_f1:
        failures.append(f"core_f1={metrics['core_f1']:.4f} < {min_core_f1:.4f}")
    if min_sides_link is not None:
        sides = metrics["sides_link"]
        if sides is None or sides < min_sides_link:
            failures.append(f"sides_link={sides} < {min_sides_link:.4f}")

    if failures:
        raise ValueError("Accuracy gate failed: " + "; ".join(failures))

    return {
        "passed": True,
        "thresholds": {
            "min_email": min_email,
            "min_core_f1": min_core_f1,
            "min_sides_link": min_sides_link,
        },
        "metrics": metrics,
    }


def compute_sha256(file_path: Path) -> str:
    """Compute lowercase hexadecimal SHA-256 digest of a file."""
    digest = hashlib.sha256()
    with file_path.open("rb") as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def package_release_artifact(weights_path: Path, output_archive: Path) -> Path:
    """Package a weights directory into a deterministic `.zip` or copy an existing file."""
    if not weights_path.exists():
        raise FileNotFoundError(f"Weights path not found: {weights_path}")

    output_archive.parent.mkdir(parents=True, exist_ok=True)
    if weights_path.is_file():
        if weights_path.resolve() != output_archive.resolve():
            shutil.copy2(weights_path, output_archive)
        return output_archive

    files = sorted(
        (path for path in weights_path.rglob("*") if path.is_file()),
        key=lambda p: p.relative_to(weights_path).as_posix(),
    )
    if not files:
        raise ValueError(f"Weights directory is empty: {weights_path}")

    with zipfile.ZipFile(
        output_archive,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=6,
    ) as zf:
        for file_path in files:
            rel_name = file_path.relative_to(weights_path).as_posix()
            zinfo = zipfile.ZipInfo(filename=rel_name, date_time=DETERMINISTIC_ZIP_TIMESTAMP)
            zinfo.compress_type = zipfile.ZIP_DEFLATED
            zinfo.external_attr = 0o644 << 16
            zf.writestr(zinfo, file_path.read_bytes())

    return output_archive


def resolve_download_url(
    *,
    download_url: str | None,
    archive_name: str,
    target: str,
    hf_repo: str | None,
    gh_repo: str | None,
    gh_tag: str | None,
    version: str,
    output_dir: Path,
) -> str:
    """Resolve the manifest `downloadURL` for Hugging Face, GitHub Release, or local mode."""
    if download_url:
        return download_url
    if target == "huggingface":
        if not hf_repo:
            raise ValueError("--hf-repo is required for --target huggingface unless --download-url is set")
        return f"https://huggingface.co/{hf_repo}/resolve/main/{archive_name}"
    if target == "github":
        if not gh_repo:
            raise ValueError("--gh-repo is required for --target github unless --download-url is set")
        tag = gh_tag or f"v{version}"
        return f"https://github.com/{gh_repo}/releases/download/{tag}/{archive_name}"
    return (output_dir / archive_name).resolve().as_uri()


def build_manifest(
    *,
    model_id: str,
    version: str,
    download_url: str,
    byte_size: int,
    sha256: str,
    min_app_version: str,
    metrics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Build the release `manifest.json` payload matching ModelPackManager's schema."""
    manifest: dict[str, Any] = {
        "modelId": model_id,
        "version": version,
        "downloadURL": download_url,
        "byteSize": int(byte_size),
        "sha256": sha256,
        "minAppVersion": min_app_version,
    }
    if metrics is not None:
        manifest["metrics"] = metrics
    return manifest


def _build_github_upload_command(
    *,
    gh_repo: str,
    gh_tag: str,
    archive_path: Path,
    manifest_path: Path,
) -> list[str]:
    return [
        "gh",
        "release",
        "upload",
        gh_tag,
        str(archive_path),
        str(manifest_path),
        "--repo",
        gh_repo,
        "--clobber",
    ]


def _upload_to_huggingface(
    *,
    hf_repo: str,
    archive_path: Path,
    manifest_path: Path,
) -> dict[str, Any]:
    from huggingface_hub import HfApi  # type: ignore

    api = HfApi()
    api.upload_file(
        path_or_fileobj=str(archive_path),
        path_in_repo=archive_path.name,
        repo_id=hf_repo,
        repo_type="model",
    )
    api.upload_file(
        path_or_fileobj=str(manifest_path),
        path_in_repo=manifest_path.name,
        repo_id=hf_repo,
        repo_type="model",
    )
    return {
        "provider": "huggingface",
        "repo": hf_repo,
        "uploaded_files": [archive_path.name, manifest_path.name],
    }


def _upload_to_github(
    *,
    gh_repo: str,
    gh_tag: str,
    archive_path: Path,
    manifest_path: Path,
) -> dict[str, Any]:
    if shutil.which("gh") is None:
        raise RuntimeError("`gh` CLI not found on PATH for GitHub Release upload.")
    cmd = _build_github_upload_command(
        gh_repo=gh_repo,
        gh_tag=gh_tag,
        archive_path=archive_path,
        manifest_path=manifest_path,
    )
    subprocess.run(cmd, check=True)
    return {"provider": "github", "repo": gh_repo, "tag": gh_tag, "command": cmd}


def publish_release(
    *,
    weights_path: Path,
    eval_report_path: Path,
    output_dir: Path,
    model_id: str = DEFAULT_MODEL_ID,
    version: str = DEFAULT_VERSION,
    min_app_version: str = DEFAULT_MIN_APP_VERSION,
    download_url: str | None = None,
    min_email: float = DEFAULT_MIN_EMAIL_ACCURACY,
    min_core_f1: float = DEFAULT_MIN_CORE_F1,
    min_sides_link: float | None = None,
    target: str = "local",
    hf_repo: str | None = None,
    gh_repo: str | None = None,
    gh_tag: str | None = None,
    dry_run: bool = False,
    no_upload: bool = False,
) -> dict[str, Any]:
    """Validate accuracy gate, package deterministic zip, write manifest, and optionally upload."""
    if target not in ("local", "huggingface", "github"):
        raise ValueError(f"Unsupported publish target: {target}")
    if not eval_report_path.exists():
        raise FileNotFoundError(f"Eval report JSON not found: {eval_report_path}")

    report_data = json.loads(eval_report_path.read_text(encoding="utf-8"))
    gate_result = check_accuracy_gate(
        report_data,
        min_email=min_email,
        min_core_f1=min_core_f1,
        min_sides_link=min_sides_link,
    )

    archive_name = (
        weights_path.name
        if weights_path.is_file() and weights_path.suffix == ".zip"
        else f"{model_id}-{version}.zip"
    )
    resolved_url = resolve_download_url(
        download_url=download_url,
        archive_name=archive_name,
        target=target,
        hf_repo=hf_repo,
        gh_repo=gh_repo,
        gh_tag=gh_tag,
        version=version,
        output_dir=output_dir,
    )

    if dry_run:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_archive = Path(tmp) / archive_name
            package_release_artifact(weights_path, tmp_archive)
            byte_size = tmp_archive.stat().st_size
            sha256 = compute_sha256(tmp_archive)
        target_archive = output_dir / archive_name
        target_manifest = output_dir / "manifest.json"
        manifest = build_manifest(
            model_id=model_id,
            version=version,
            download_url=resolved_url,
            byte_size=byte_size,
            sha256=sha256,
            min_app_version=min_app_version,
            metrics=gate_result["metrics"],
        )
        planned_upload: dict[str, Any] = {"provider": target, "skipped": True}
        if target == "github" and gh_repo:
            planned_upload["command"] = _build_github_upload_command(
                gh_repo=gh_repo,
                gh_tag=gh_tag or f"v{version}",
                archive_path=target_archive,
                manifest_path=target_manifest,
            )
        elif target == "huggingface" and hf_repo:
            planned_upload["repo"] = hf_repo
            planned_upload["files"] = [archive_name, "manifest.json"]
        return {
            "dry_run": True,
            "gate": gate_result,
            "archive_path": str(target_archive),
            "manifest_path": str(target_manifest),
            "manifest": manifest,
            "upload": planned_upload,
        }

    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = package_release_artifact(weights_path, output_dir / archive_name)
    byte_size = archive_path.stat().st_size
    sha256 = compute_sha256(archive_path)

    manifest = build_manifest(
        model_id=model_id,
        version=version,
        download_url=resolved_url,
        byte_size=byte_size,
        sha256=sha256,
        min_app_version=min_app_version,
        metrics=gate_result["metrics"],
    )
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    upload_result: dict[str, Any] = {"provider": target, "uploaded": False}
    if not no_upload and target == "huggingface":
        if not hf_repo:
            raise ValueError("--hf-repo is required for --target huggingface")
        upload_result = _upload_to_huggingface(
            hf_repo=hf_repo,
            archive_path=archive_path,
            manifest_path=manifest_path,
        )
        upload_result["uploaded"] = True
    elif not no_upload and target == "github":
        if not gh_repo:
            raise ValueError("--gh-repo is required for --target github")
        upload_result = _upload_to_github(
            gh_repo=gh_repo,
            gh_tag=gh_tag or f"v{version}",
            archive_path=archive_path,
            manifest_path=manifest_path,
        )
        upload_result["uploaded"] = True

    return {
        "dry_run": False,
        "gate": gate_result,
        "archive_path": str(archive_path),
        "manifest_path": str(manifest_path),
        "manifest": manifest,
        "upload": upload_result,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--weights-dir",
        type=Path,
        required=True,
        help="Path to exported quantized weights directory (or pre-built .zip artifact).",
    )
    parser.add_argument(
        "--eval-report",
        type=Path,
        required=True,
        help="Path to JSON report produced by scripts/colab/eval_offline_v2.py.",
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--model-id", type=str, default=DEFAULT_MODEL_ID)
    parser.add_argument("--version", type=str, default=DEFAULT_VERSION)
    parser.add_argument("--min-app-version", type=str, default=DEFAULT_MIN_APP_VERSION)
    parser.add_argument("--download-url", type=str, default=None)
    parser.add_argument("--min-email", type=float, default=DEFAULT_MIN_EMAIL_ACCURACY)
    parser.add_argument("--min-core-f1", type=float, default=DEFAULT_MIN_CORE_F1)
    parser.add_argument("--min-sides-link", type=float, default=None)
    parser.add_argument(
        "--target",
        choices=("local", "huggingface", "github"),
        default="local",
    )
    parser.add_argument("--hf-repo", type=str, default=None)
    parser.add_argument("--gh-repo", type=str, default=None)
    parser.add_argument("--gh-tag", type=str, default=None)
    parser.add_argument("--no-upload", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        result = publish_release(
            weights_path=args.weights_dir,
            eval_report_path=args.eval_report,
            output_dir=args.output_dir,
            model_id=args.model_id,
            version=args.version,
            min_app_version=args.min_app_version,
            download_url=args.download_url,
            min_email=args.min_email,
            min_core_f1=args.min_core_f1,
            min_sides_link=args.min_sides_link,
            target=args.target,
            hf_repo=args.hf_repo,
            gh_repo=args.gh_repo,
            gh_tag=args.gh_tag,
            dry_run=args.dry_run,
            no_upload=args.no_upload,
        )
    except (ValueError, FileNotFoundError, RuntimeError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
