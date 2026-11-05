#!/usr/bin/env python3
"""Evaluate OneTake parser endpoints against the held-out JSONL corpus.

The endpoint must accept POST requests containing {"text": "..."} and expose:
  POST /api/v1/parse/notice
  POST /api/v1/parse/sides

This evaluator measures output validity, normalized field accuracy, scene
structure, dialogue preservation, hallucinated notice fields, and latency.
It intentionally does not download or load a model itself, so the same
corpus can be used with the Qwen backend, an OpenAI-compatible proxy, or a
different local model.
"""

from __future__ import annotations

import argparse
import difflib
import json
import statistics
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_EVAL_FILE = BASE_DIR / "dataset" / "parsing_dataset_eval.jsonl"
NOTICE_FIELDS = (
    "project",
    "project_type",
    "role",
    "role_size",
    "casting_office",
    "due_date",
    "sides_link",
    "submission_email",
)


def normalize(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        return " | ".join(normalize(item) for item in value)
    return " ".join(str(value).casefold().split())


def extract_input(user_content: str) -> str:
    marker = "\n\n"
    return user_content.rsplit(marker, 1)[-1].strip()


def load_rows(path: Path) -> list[dict[str, Any]]:
    rows = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
            messages = row.get("messages", [])
            if len(messages) < 3:
                raise ValueError(f"{path}:{line_number}: expected system, user, assistant messages")
            try:
                row["_gold"] = json.loads(messages[2]["content"])
            except (KeyError, json.JSONDecodeError) as exc:
                raise ValueError(f"{path}:{line_number}: invalid assistant target") from exc
            row["_input"] = extract_input(messages[1]["content"])
            row["_kind"] = "notice" if "notice" in messages[1]["content"].casefold() else "sides"
            rows.append(row)
    return rows


def request_prediction(base_url: str, kind: str, text: str, timeout: float) -> tuple[Any, float, str | None]:
    url = f"{base_url.rstrip('/')}/api/v1/parse/{kind}"
    request = urllib.request.Request(
        url,
        data=json.dumps({"text": text}).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = response.read().decode("utf-8")
        elapsed = time.perf_counter() - started
        try:
            return json.loads(payload), elapsed, None
        except json.JSONDecodeError as exc:
            return None, elapsed, f"invalid JSON response: {exc}"
    except (OSError, urllib.error.HTTPError, urllib.error.URLError) as exc:
        return None, time.perf_counter() - started, str(exc)


def score_notice(gold: dict[str, Any], prediction: Any) -> dict[str, Any]:
    if not isinstance(prediction, dict):
        return {"valid_schema": False, "field_matches": 0, "field_total": len(NOTICE_FIELDS), "hallucinated": 0}
    matches = sum(normalize(prediction.get(field)) == normalize(gold.get(field)) for field in NOTICE_FIELDS)
    comparable_missing = sum(
        not normalize(gold.get(field)) and normalize(prediction.get(field))
        for field in NOTICE_FIELDS
    )
    return {
        "valid_schema": all(field in prediction for field in ("project", "role", "specs")),
        "field_matches": matches,
        "field_total": len(NOTICE_FIELDS),
        "hallucinated": comparable_missing,
    }


def scene_data(value: Any) -> list[dict[str, Any]]:
    if not isinstance(value, dict) or not isinstance(value.get("scenes"), list):
        return []
    return [scene for scene in value["scenes"] if isinstance(scene, dict)]


def lines_data(scenes: list[dict[str, Any]]) -> list[dict[str, Any]]:
    lines = []
    for scene in scenes:
        if isinstance(scene.get("lines"), list):
            lines.extend(line for line in scene["lines"] if isinstance(line, dict))
    return lines


def sequence_similarity(expected: list[Any], actual: list[Any]) -> float:
    expected_values = [normalize(item) for item in expected]
    actual_values = [normalize(item) for item in actual]
    return difflib.SequenceMatcher(a=expected_values, b=actual_values).ratio()


def score_sides(gold: dict[str, Any], prediction: Any) -> dict[str, Any]:
    gold_scenes = scene_data(gold)
    predicted_scenes = scene_data(prediction)
    gold_lines = lines_data(gold_scenes)
    predicted_lines = lines_data(predicted_scenes)
    gold_headings = [scene.get("heading", "") for scene in gold_scenes]
    predicted_headings = [scene.get("heading", "") for scene in predicted_scenes]
    gold_characters = [line.get("character", "") for line in gold_lines]
    predicted_characters = [line.get("character", "") for line in predicted_lines]
    gold_text = [line.get("text", "") for line in gold_lines]
    predicted_text = [line.get("text", "") for line in predicted_lines]
    return {
        "valid_schema": isinstance(prediction, dict) and isinstance(prediction.get("scenes"), list),
        "scene_count_exact": len(gold_scenes) == len(predicted_scenes),
        "scene_count_error": abs(len(gold_scenes) - len(predicted_scenes)),
        "heading_similarity": sequence_similarity(gold_headings, predicted_headings),
        "character_similarity": sequence_similarity(gold_characters, predicted_characters),
        "dialogue_similarity": sequence_similarity(gold_text, predicted_text),
        "gold_lines": len(gold_lines),
        "predicted_lines": len(predicted_lines),
    }


def percentile(values: list[float], percentile_value: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, round((percentile_value / 100) * (len(ordered) - 1)))
    return ordered[index]


def evaluate(base_url: str, rows: list[dict[str, Any]], timeout: float) -> dict[str, Any]:
    results = []
    latencies = []
    for index, row in enumerate(rows, 1):
        prediction, elapsed, error = request_prediction(base_url, row["_kind"], row["_input"], timeout)
        latencies.append(elapsed)
        score = (
            score_notice(row["_gold"], prediction)
            if row["_kind"] == "notice"
            else score_sides(row["_gold"], prediction)
        )
        score.update({"index": index, "kind": row["_kind"], "latency_seconds": round(elapsed, 4), "error": error})
        results.append(score)

    notices = [result for result in results if result["kind"] == "notice"]
    sides = [result for result in results if result["kind"] == "sides"]
    valid_json = sum(result["error"] is None for result in results)
    valid_schema = sum(result["valid_schema"] for result in results)
    report: dict[str, Any] = {
        "endpoint": base_url,
        "samples": len(results),
        "valid_json_rate": valid_json / len(results) if results else 0,
        "schema_valid_rate": valid_schema / len(results) if results else 0,
        "latency_seconds": {
            "mean": statistics.mean(latencies) if latencies else None,
            "median": statistics.median(latencies) if latencies else None,
            "p95": percentile(latencies, 95),
        },
        "notice": {
            "samples": len(notices),
            "field_exact_match_rate": (
                sum(result["field_matches"] for result in notices)
                / sum(result["field_total"] for result in notices)
                if notices else 0
            ),
            "hallucinated_empty_fields": sum(result["hallucinated"] for result in notices),
        },
        "sides": {
            "samples": len(sides),
            "scene_count_accuracy": (
                sum(result["scene_count_exact"] for result in sides) / len(sides)
                if sides else 0
            ),
            "heading_similarity": statistics.mean(result["heading_similarity"] for result in sides) if sides else 0,
            "character_similarity": statistics.mean(result["character_similarity"] for result in sides) if sides else 0,
            "dialogue_similarity": statistics.mean(result["dialogue_similarity"] for result in sides) if sides else 0,
        },
        "cases": results,
    }
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://localhost:8080")
    parser.add_argument("--eval-file", type=Path, default=DEFAULT_EVAL_FILE)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", type=Path, help="Write the complete report as JSON")
    args = parser.parse_args()

    rows = load_rows(args.eval_file)
    report = evaluate(args.base_url, rows, args.timeout)
    print(json.dumps({key: value for key, value in report.items() if key != "cases"}, indent=2))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Detailed report written to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
