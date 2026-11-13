#!/usr/bin/env python3
"""Unit tests for the Task 5 offline v2 corpus generator and evaluator."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.colab.build_offline_v2_corpus import (
    CANONICAL_SCHEMA_KEYS,
    LAYOUT_VARIANTS,
    build_corpus,
    estimate_token_count,
)
from scripts.colab.eval_offline_v2 import (
    evaluate_offline,
    score_record,
    token_f1,
)

EXPECTED_18_KEYS = {
    "project",
    "project_type",
    "role",
    "candidate_roles",
    "role_size",
    "casting_office",
    "due_date_text",
    "specs",
    "sides_link",
    "submission_email",
    "location",
    "casting_notes",
    "union_status",
    "pay_terms",
    "callback_dates_text",
    "shoot_dates_text",
    "orientation",
    "file_naming",
}


def read_png_dimensions_and_validate(path: Path) -> tuple[int, int]:
    """Validate PNG signature, IHDR dimensions, and zlib IDAT stream using stdlib only."""
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise AssertionError(f"{path} missing PNG signature")

    offset = 8
    width = None
    height = None
    idat_chunks: list[bytes] = []
    saw_iend = False

    while offset + 8 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_data = data[offset + 8 : offset + 8 + length]
        offset += 12 + length

        if chunk_type == b"IHDR":
            width, height = struct.unpack(">II", chunk_data[:8])
        elif chunk_type == b"IDAT":
            idat_chunks.append(chunk_data)
        elif chunk_type == b"IEND":
            saw_iend = True
            break

    if width is None or height is None:
        raise AssertionError(f"{path} missing IHDR chunk")
    if not saw_iend:
        raise AssertionError(f"{path} missing IEND chunk")
    raw_scanlines = zlib.decompress(b"".join(idat_chunks))
    if not raw_scanlines:
        raise AssertionError(f"{path} empty decompressed image data")
    return width, height


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


class TestCorpusPipeline(unittest.TestCase):
    def test_canonical_18_keys_constant(self) -> None:
        self.assertEqual(len(CANONICAL_SCHEMA_KEYS), 18)
        self.assertEqual(set(CANONICAL_SCHEMA_KEYS), EXPECTED_18_KEYS)

    def test_generated_corpus_schema_images_and_token_budget(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out_dir = Path(tmp)
            summary = build_corpus(
                output_dir=out_dir,
                train_count=12,
                eval_count=6,
                seed=123,
            )
            self.assertEqual(summary["train_count"], 12)
            self.assertEqual(summary["eval_count"], 6)

            train_vlm = load_jsonl(out_dir / "train_vlm.jsonl")
            eval_vlm = load_jsonl(out_dir / "eval_vlm.jsonl")
            train_needle = load_jsonl(out_dir / "train_needle.jsonl")
            eval_needle = load_jsonl(out_dir / "eval_needle.jsonl")

            self.assertEqual(len(train_vlm), 12)
            self.assertEqual(len(eval_vlm), 6)
            self.assertEqual(len(train_needle), 12)
            self.assertEqual(len(eval_needle), 6)

            seen_layouts = set()
            train_projects = set()
            eval_projects = set()
            train_emails = set()
            eval_emails = set()

            for split_name, vlm_rows, needle_rows in (
                ("train", train_vlm, train_needle),
                ("eval", eval_vlm, eval_needle),
            ):
                for vlm_row, needle_row in zip(vlm_rows, needle_rows):
                    seen_layouts.add(vlm_row["layout"])

                    # 1. Verify all 18 SemanticNoticePayload keys in both target & assistant message
                    for row in (vlm_row, needle_row):
                        target = row["target"]
                        self.assertEqual(set(target.keys()), EXPECTED_18_KEYS)
                        assistant_payload = json.loads(row["messages"][2]["content"])
                        self.assertEqual(set(assistant_payload.keys()), EXPECTED_18_KEYS)
                        self.assertIsInstance(target["candidate_roles"], list)
                        self.assertIsInstance(target["specs"], list)
                        self.assertIn(target["orientation"], ("Landscape", "Portrait", None))

                    # 2. Verify Needle 3 token & word budget
                    needle_text = needle_row["text"]
                    word_count = len(needle_text.split())
                    est_tokens = estimate_token_count(needle_text)
                    self.assertLessEqual(word_count, 750)
                    self.assertLessEqual(est_tokens, 1024)

                    if target["submission_email"]:
                        self.assertIn(target["submission_email"].lower(), needle_text.lower())

                    # 3. Verify 768x960 valid PNG file exists
                    image_path = out_dir / vlm_row["image"]
                    self.assertTrue(image_path.exists(), f"Missing poster PNG {image_path}")
                    width, height = read_png_dimensions_and_validate(image_path)
                    self.assertEqual((width, height), (768, 960))

                    if split_name == "train":
                        if target["project"]:
                            train_projects.add(target["project"])
                        if target["submission_email"]:
                            train_emails.add(target["submission_email"])
                    else:
                        if target["project"]:
                            eval_projects.add(target["project"])
                        if target["submission_email"]:
                            eval_emails.add(target["submission_email"])

            self.assertGreaterEqual(len(seen_layouts), len(LAYOUT_VARIANTS))
            self.assertTrue(train_projects.isdisjoint(eval_projects))
            self.assertTrue(train_emails.isdisjoint(eval_emails))

    def test_evaluator_exact_match_and_token_f1_no_fabrication(self) -> None:
        self.assertAlmostEqual(token_f1("Detective Maya Lin", "Maya Lin"), 0.8, places=4)
        self.assertAlmostEqual(token_f1("", "Maya Lin"), 0.0, places=4)
        self.assertAlmostEqual(token_f1(None, None), 1.0, places=4)

        gold = {
            "project": "Midnight Monsoon",
            "project_type": "Feature Film",
            "role": "Detective Maya Lin",
            "candidate_roles": ["Detective Maya Lin", "Inspector Rao"],
            "role_size": "Lead",
            "casting_office": "Bayshore Casting",
            "due_date_text": "Nov 22, 2026 5:00 PM",
            "specs": ["Landscape", "Slate first", "Full body frame"],
            "sides_link": "https://sides.example.org/monsoon",
            "submission_email": "tapes@bayshorecasting.example",
            "location": "Mumbai, India",
            "casting_notes": "Grounded intensity",
            "union_status": "Non-Union",
            "pay_terms": "INR 45,000/day",
            "callback_dates_text": "Nov 28, 2026",
            "shoot_dates_text": "Dec 10-14, 2026",
            "orientation": "Landscape",
            "file_naming": "Role_Name_City.mp4",
        }

        perfect_case = score_record(gold, dict(gold))
        self.assertEqual(perfect_case["submission_email_exact"], 1.0)
        self.assertEqual(perfect_case["sides_link_exact"], 1.0)
        self.assertEqual(perfect_case["field_f1"]["role"], 1.0)
        self.assertEqual(perfect_case["field_f1"]["asks"], 1.0)
        self.assertTrue(perfect_case["schema_valid"])

        partial_pred = {
            "project": "Midnight Monsoon",
            "role": "Maya Lin",
            "casting_office": "Bayshore",
            "asks": ["Landscape", "Slate"],
            "location": "Mumbai",
            "sides_link": "https://sides.example.org/monsoon",
            "submission_email": "wrong@agency.example",
        }
        partial_case = score_record(gold, partial_pred)
        self.assertEqual(partial_case["submission_email_exact"], 0.0)
        self.assertEqual(partial_case["sides_link_exact"], 1.0)
        self.assertAlmostEqual(partial_case["field_f1"]["role"], 0.8, places=4)
        self.assertAlmostEqual(partial_case["field_f1"]["project"], 1.0, places=4)
        self.assertAlmostEqual(partial_case["field_f1"]["casting_office"], 2 / 3, places=4)
        self.assertAlmostEqual(partial_case["field_f1"]["asks"], 0.5, places=4)
        self.assertAlmostEqual(partial_case["field_f1"]["location"], 2 / 3, places=4)
        self.assertFalse(partial_case["schema_valid"])

        # Missing --predictions CLI flag must exit non-zero instead of fabricating scores
        no_preds_proc = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts" / "colab" / "eval_offline_v2.py")],
            cwd=str(REPO_ROOT),
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(no_preds_proc.returncode, 0)

        # Missing/unparseable prediction must score 0.0 and never fabricate gold scores
        missing_case = score_record(gold, None)
        self.assertEqual(missing_case["submission_email_exact"], 0.0)
        self.assertEqual(missing_case["sides_link_exact"], 0.0)
        self.assertEqual(missing_case["field_f1"]["role"], 0.0)
        self.assertFalse(missing_case["valid_json"])

        report = evaluate_offline([{"id": "1", "target": gold}], [{"id": "1", "prediction": None}])
        self.assertEqual(report["valid_json_rate"], 0.0)
        self.assertEqual(report["exact_match"]["submission_email"], 0.0)
        self.assertEqual(report["core_f1"], 0.0)

    def test_evaluate_field_accuracy_forwards_offline_eval(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            build_corpus(output_dir=tmp_dir, train_count=4, eval_count=2, seed=7)
            eval_rows = load_jsonl(tmp_dir / "eval_needle.jsonl")
            preds_path = tmp_dir / "preds.jsonl"
            with preds_path.open("w", encoding="utf-8") as handle:
                for row in eval_rows:
                    handle.write(json.dumps({"id": row["id"], "prediction": row["target"]}) + "\n")

            output_json = tmp_dir / "report.json"
            proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "evaluate_field_accuracy.py"),
                    "--offline-eval",
                    "--eval-file",
                    str(tmp_dir / "eval_needle.jsonl"),
                    "--predictions",
                    str(preds_path),
                    "--output",
                    str(output_json),
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            report = json.loads(output_json.read_text(encoding="utf-8"))
            self.assertEqual(report["samples"], 2)
            self.assertEqual(report["exact_match"]["submission_email"], 1.0)
            self.assertEqual(report["core_f1"], 1.0)


if __name__ == "__main__":
    unittest.main()
