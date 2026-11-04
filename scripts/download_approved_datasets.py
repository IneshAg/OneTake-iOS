#!/usr/bin/env python3
"""Download explicitly approved, public dataset assets from a JSONL manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import mimetypes
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import urllib.robotparser
from datetime import datetime, timezone
from pathlib import Path

USER_AGENT = "OneTakeDatasetDownloader/1.0"
MAX_BYTES = 100 * 1024 * 1024


class DownloadError(Exception):
    pass


def safe_filename(url: str, supplied: str | None) -> str:
    value = supplied or Path(urllib.parse.urlparse(url).path).name or "asset"
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", Path(value).name)
    if Path(value).suffix.lower() not in {".json", ".jsonl", ".csv", ".txt", ".pdf", ".zip"}:
        value += mimetypes.guess_extension("application/octet-stream") or ".bin"
    return value


def read_manifest(path: Path) -> list[dict[str, str]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise DownloadError(f"cannot read {path}: {error}") from error
    records: list[dict[str, str]] = []
    for line_number, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            raise DownloadError(f"{path}:{line_number}: invalid JSON: {error}") from error
        if not isinstance(record, dict):
            raise DownloadError(f"{path}:{line_number}: expected an object")
        for key in ("url", "category", "license"):
            if not record.get(key):
                raise DownloadError(f"{path}:{line_number}: missing {key}")
        parsed = urllib.parse.urlparse(str(record["url"]))
        if parsed.scheme != "https" or not parsed.netloc:
            raise DownloadError(f"{path}:{line_number}: URL must be HTTPS")
        if str(record["license"]).lower() in {"unknown", "unverified", "copyrighted"}:
            raise DownloadError(f"{path}:{line_number}: license is not verified")
        records.append({str(k): str(v) for k, v in record.items()})
    return records


def allowed_by_robots(
    url: str, cache: dict[str, urllib.robotparser.RobotFileParser]
) -> bool:
    parsed = urllib.parse.urlparse(url)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    if origin not in cache:
        parser = urllib.robotparser.RobotFileParser(f"{origin}/robots.txt")
        try:
            parser.read()
        except OSError as error:
            raise DownloadError(f"could not read {origin}/robots.txt: {error}") from error
        cache[origin] = parser
    return cache[origin].can_fetch(USER_AGENT, url)


def download(url: str, max_bytes: int) -> tuple[bytes, str]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            length = response.headers.get("Content-Length")
            if length and int(length) > max_bytes:
                raise DownloadError(f"download exceeds {max_bytes} bytes: {url}")
            content = response.read(max_bytes + 1)
            return content, response.headers.get_content_type()
    except (urllib.error.URLError, TimeoutError) as error:
        raise DownloadError(f"download failed for {url}: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, default=Path("data"))
    parser.add_argument("--delay", type=float, default=1.0)
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    try:
        records = read_manifest(args.manifest)
        robots: dict[str, urllib.robotparser.RobotFileParser] = {}
        last_host = ""
        last_request = 0.0
        log_path = args.output / "manifests" / "collection.jsonl"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("a", encoding="utf-8") as log:
            for record in records:
                url = record["url"]
                if not allowed_by_robots(url, robots):
                    raise DownloadError(f"robots.txt disallows URL: {url}")
                host = urllib.parse.urlparse(url).netloc
                if host == last_host:
                    time.sleep(max(0.0, args.delay - (time.monotonic() - last_request)))
                last_host, last_request = host, time.monotonic()
                entry = {
                    "source_url": url,
                    "category": record["category"],
                    "license": record["license"],
                    "retrieved_at": datetime.now(timezone.utc).isoformat(),
                }
                if not args.dry_run:
                    content, content_type = download(url, args.max_bytes)
                    if len(content) > args.max_bytes:
                        raise DownloadError(f"download exceeds {args.max_bytes} bytes: {url}")
                    destination = args.output / "raw" / record["category"] / safe_filename(
                        url, record.get("filename")
                    )
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(content)
                    entry.update(
                        path=str(destination),
                        bytes=len(content),
                        content_type=content_type,
                        sha256=hashlib.sha256(content).hexdigest(),
                    )
                print(json.dumps(entry, ensure_ascii=True))
                log.write(json.dumps(entry, ensure_ascii=True) + "\n")
        return 0
    except (DownloadError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
