#!/usr/bin/env python3
"""Offline v2 Accuracy Evaluator for Needle 3 & LFM2.5-VL-450M.

Evaluates held-out JSONL predictions against the 18-key SemanticNoticePayload
ground truth without fabricating scores:
  - Exact match on `submission_email` and `sides_link`
  - Token-level F1 on `role`, `project`, `casting_office`, `asks`/`specs`, and `location`
  - JSON validity and 18-key canonical schema conformance rates
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import statistics
import sys
from typing import Any

try:
    from scripts.colab.build_offline_v2_corpus import CANONICAL_SCHEMA_KEYS, REPO_ROOT
except ImportError:  # pragma: no cover - direct script invocation
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from scripts.colab.build_offline_v2_corpus import CANONICAL_SCHEMA_KEYS, REPO_ROOT

DEFAULT_EVAL_FILE = REPO_ROOT / "dataset" / "offline_v2" / "eval_needle.jsonl"
CORE_F1_FIELDS: tuple[str, ...] = ("role", "project", "casting_office", "asks", "location")


def normalize_exact(value: Any) -> str:
    """Normalize scalar fields for exact-match comparison (emails, URLs)."""
    if value is None:
        return ""
    if isinstance(value, list):
        return " | ".join(normalize_exact(item) for item in value if item is not None)
    text = " ".join(str(value).strip().split()).casefold()
    if text.startswith("mailto:"):
        text = text[len("mailto:") :]
    return text.rstrip("/")


def tokenize_for_f1(value: Any) -> list[str]:
    """Tokenize string or list values into lowercase alphanumeric/word tokens."""
    if value is None:
        return []
    if isinstance(value, list):
        text = " ".join(str(item) for item in value if item is not None)
    else:
        text = str(value)
    return re.findall(r"\w+", text.casefold(), flags=re.UNICODE)


def token_f1(gold_value: Any, pred_value: Any) -> float:
    """Compute SQuAD-style multiset token-level F1 between gold and predicted values."""
    gold_tokens = tokenize_for_f1(gold_value)
    pred_tokens = tokenize_for_f1(pred_value)
    if not gold_tokens and not pred_tokens:
        return 1.0
    if not gold_tokens or not pred_tokens:
        return 0.0

    overlap = sum((Counter(gold_tokens) & Counter(pred_tokens)).values())
    if overlap == 0:
        return 0.0
    precision = overlap / len(pred_tokens)
    recall = overlap / len(gold_tokens)
    return (2.0 * precision * recall) / (precision + recall)


def extract_specs_or_asks(payload: dict[str, Any]) -> Any:
    """Return `specs` (canonical) with backward-compatible fallback to `asks`."""
    if "specs" in payload and payload["specs"] is not None:
        return payload["specs"]
    return payload.get("asks")


def parse_prediction_payload(raw_prediction: Any) -> dict[str, Any] | None:
    """Parse prediction dict or JSON string without substituting gold labels."""
    if raw_prediction is None:
        return None
    if isinstance(raw_prediction, dict):
        if "prediction" in raw_prediction and not any(k in raw_prediction for k in CANONICAL_SCHEMA_KEYS):
            return parse_prediction_payload(raw_prediction["prediction"])
        return raw_prediction
    if isinstance(raw_prediction, str):
        cleaned = raw_prediction.strip()
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?\s*|\s*```$", "", cleaned, flags=re.IGNORECASE | re.DOTALL).strip()
        try:
            parsed = json.loads(cleaned)
        except json.JSONDecodeError:
            return None
        return parsed if isinstance(parsed, dict) else None
    return None


def score_record(gold: dict[str, Any], raw_prediction: Any) -> dict[str, Any]:
    """Score one prediction against canonical ground truth."""
    pred = parse_prediction_payload(raw_prediction)
    if pred is None:
        zero_f1 = {field: 0.0 for field in CORE_F1_FIELDS}
        zero_f1["specs"] = 0.0
        return {
            "valid_json": False,
            "schema_valid": False,
            "submission_email_exact": 0.0,
            "sides_link_exact": 0.0,
            "field_f1": zero_f1,
            "core_f1": 0.0,
        }

    schema_valid = all(key in pred for key in CANONICAL_SCHEMA_KEYS)
    email_exact = float(normalize_exact(gold.get("submission_email")) == normalize_exact(pred.get("submission_email")))
    sides_exact = float(normalize_exact(gold.get("sides_link")) == normalize_exact(pred.get("sides_link")))

    asks_f1 = token_f1(extract_specs_or_asks(gold), extract_specs_or_asks(pred))
    field_f1: dict[str, float] = {
        "role": token_f1(gold.get("role"), pred.get("role")),
        "project": token_f1(gold.get("project"), pred.get("project")),
        "casting_office": token_f1(gold.get("casting_office"), pred.get("casting_office")),
        "asks": asks_f1,
        "specs": asks_f1,
        "location": token_f1(gold.get("location"), pred.get("location")),
    }
    core_f1 = statistics.mean(field_f1[field] for field in CORE_F1_FIELDS)

    return {
        "valid_json": True,
        "schema_valid": schema_valid,
        "submission_email_exact": email_exact,
        "sides_link_exact": sides_exact,
        "field_f1": field_f1,
        "core_f1": core_f1,
    }


def load_eval_rows(path: Path) -> list[dict[str, Any]]:
    """Load held-out JSONL rows containing `target` or assistant JSON messages."""
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            row = json.loads(line)
            if isinstance(row.get("target"), dict):
                target = row["target"]
            else:
                messages = row.get("messages", [])
                if len(messages) < 3:
                    raise ValueError(f"{path}:{line_number}: missing `target` and assistant message")
                target = json.loads(messages[2]["content"])
            rows.append({"id": row.get("id", str(line_number)), "target": target})
    return rows


def load_prediction_rows(path: Path) -> list[Any]:
    """Load JSONL prediction rows (either objects with `id`/`prediction` or raw payloads)."""
    rows: list[Any] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            rows.append(json.loads(line))
    return rows


def evaluate_offline(
    gold_rows: list[dict[str, Any]],
    prediction_rows: list[Any],
) -> dict[str, Any]:
    """Evaluate predictions aligned by `id` (when available) or positional index."""
    by_id: dict[str, Any] = {}
    for item in prediction_rows:
        if isinstance(item, dict) and "id" in item:
            by_id[str(item["id"])] = item.get("prediction", item)

    cases: list[dict[str, Any]] = []
    for idx, gold_row in enumerate(gold_rows):
        row_id = str(gold_row.get("id", idx))
        if row_id in by_id:
            raw_pred = by_id[row_id]
        elif idx < len(prediction_rows):
            raw_pred = prediction_rows[idx]
        else:
            raw_pred = None

        gold_target = gold_row["target"] if "target" in gold_row else gold_row
        scored = score_record(gold_target, raw_pred)
        scored["id"] = row_id
        cases.append(scored)

    total = len(cases)
    if total == 0:
        return {
            "samples": 0,
            "valid_json_rate": 0.0,
            "schema_valid_rate": 0.0,
            "exact_match": {"submission_email": 0.0, "sides_link": 0.0},
            "field_f1": {field: 0.0 for field in (*CORE_F1_FIELDS, "specs")},
            "core_f1": 0.0,
            "cases": [],
        }

    asks_mean = statistics.mean(case["field_f1"]["asks"] for case in cases)
    field_f1_summary = {
        "role": statistics.mean(case["field_f1"]["role"] for case in cases),
        "project": statistics.mean(case["field_f1"]["project"] for case in cases),
        "casting_office": statistics.mean(case["field_f1"]["casting_office"] for case in cases),
        "asks": asks_mean,
        "specs": asks_mean,
        "location": statistics.mean(case["field_f1"]["location"] for case in cases),
    }

    return {
        "samples": total,
        "valid_json_rate": sum(case["valid_json"] for case in cases) / total,
        "schema_valid_rate": sum(case["schema_valid"] for case in cases) / total,
        "exact_match": {
            "submission_email": sum(case["submission_email_exact"] for case in cases) / total,
            "sides_link": sum(case["sides_link_exact"] for case in cases) / total,
        },
        "field_f1": field_f1_summary,
        "core_f1": statistics.mean(case["core_f1"] for case in cases),
        "cases": cases,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--eval-file", type=Path, default=DEFAULT_EVAL_FILE)
    parser.add_argument(
        "--predictions",
        type=Path,
        required=True,
        help="Path to predictions JSONL (required; gold labels are never substituted).",
    )
    parser.add_argument("--output", type=Path, help="Optional path to write full JSON report.")
    args = parser.parse_args(argv)

    if not args.eval_file.exists():
        print(f"Error: eval file not found: {args.eval_file}", file=sys.stderr)
        return 2
    if not args.predictions.exists():
        print(f"Error: predictions file not found: {args.predictions}", file=sys.stderr)
        return 2

    gold_rows = load_eval_rows(args.eval_file)
    pred_rows = load_prediction_rows(args.predictions)
    report = evaluate_offline(gold_rows, pred_rows)

    summary = {k: v for k, v in report.items() if k != "cases"}
    print(json.dumps(summary, indent=2))
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
