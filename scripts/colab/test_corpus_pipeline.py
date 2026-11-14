#!/usr/bin/env python3
"""Unit tests for the Task 5 & Task 6 offline v2 corpus, training, eval, and release scripts."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
import zlib

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from scripts.colab.build_offline_v2_corpus import (
    CANONICAL_SCHEMA_KEYS,
    LAYOUT_VARIANTS,
    build_corpus,
    estimate_token_count,
    render_poster_png_fallback,
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

        # Hardened schema_valid checks: reject extra keys, non-list specs/candidate_roles, or invalid orientation
        extra_key_pred = dict(gold, unexpected_extra="x")
        self.assertFalse(score_record(gold, extra_key_pred)["schema_valid"])
        bad_orientation_pred = dict(gold, orientation="Square")
        self.assertFalse(score_record(gold, bad_orientation_pred)["schema_valid"])
        bad_roles_pred = dict(gold, candidate_roles="Detective Maya Lin")
        self.assertFalse(score_record(gold, bad_roles_pred)["schema_valid"])

    def test_partial_by_id_predictions_do_not_shift_alignment(self) -> None:
        gold_a = {
            "project": "Project Alpha",
            "project_type": "Feature Film",
            "role": "Maya",
            "candidate_roles": ["Maya"],
            "role_size": "Lead",
            "casting_office": "Alpha Casting",
            "due_date_text": "Nov 20, 2026",
            "specs": ["Landscape"],
            "sides_link": "https://sides.example.org/alpha",
            "submission_email": "alpha@cast.example",
            "location": "Mumbai",
            "casting_notes": "Natural",
            "union_status": "Non-Union",
            "pay_terms": None,
            "callback_dates_text": None,
            "shoot_dates_text": None,
            "orientation": "Landscape",
            "file_naming": None,
        }
        gold_b = dict(
            gold_a,
            project="Project Beta",
            role="Kabir",
            candidate_roles=["Kabir"],
            casting_office="Beta Casting",
            sides_link="https://sides.example.org/beta",
            submission_email="beta@cast.example",
        )
        gold_c = dict(
            gold_a,
            project="Project Gamma",
            role="Simran",
            candidate_roles=["Simran"],
            casting_office="Gamma Casting",
            sides_link="https://sides.example.org/gamma",
            submission_email="gamma@cast.example",
        )

        # Omit id "2" completely; id "3" must still align with gold_c and id "2" must score 0.0
        report = evaluate_offline(
            [{"id": "1", "target": gold_a}, {"id": "2", "target": gold_b}, {"id": "3", "target": gold_c}],
            [{"id": "1", "prediction": dict(gold_a)}, {"id": "3", "prediction": dict(gold_c)}],
        )
        by_case_id = {case["id"]: case for case in report["cases"]}
        self.assertEqual(by_case_id["1"]["submission_email_exact"], 1.0)
        self.assertEqual(by_case_id["1"]["core_f1"], 1.0)
        self.assertFalse(by_case_id["2"]["valid_json"])
        self.assertEqual(by_case_id["2"]["submission_email_exact"], 0.0)
        self.assertEqual(by_case_id["2"]["core_f1"], 0.0)
        self.assertEqual(by_case_id["3"]["submission_email_exact"], 1.0)
        self.assertEqual(by_case_id["3"]["core_f1"], 1.0)

    def test_fallback_png_renderer_wraps_long_fields_and_two_column_layout(self) -> None:
        long_sample = {
            "layout": "two_column_grid",
            "agency_brand": "Long Agency Brand Name",
            "decoy_email": "decoy@agency-brand.invalid",
            "target": {
                "project": "A Very Long Multi-Word Feature Film Title That Wraps Cleanly",
                "project_type": "Feature Film",
                "role": "Inspector Kavita Nair",
                "candidate_roles": ["Inspector Kavita Nair", "Rohan Bedi", "Sub-Inspector Arjun"],
                "role_size": "Lead",
                "casting_office": "Katha Audition Studio & Regional Talent Collective",
                "due_date_text": "Nov 28, 2026 6:00 PM IST",
                "specs": ["Landscape", "Slate first", "Two takes", "Hindi and Punjabi bilingual"],
                "sides_link": "https://scripts.auditionvault.example/files/very-long-feature-film-sides-packet-v2-final.pdf",
                "submission_email": "cast-very-long-project-submissions-desk@katha-auditions.example",
                "location": "Chandigarh / Mumbai",
                "casting_notes": "Fluent Hindi & Punjabi speaker (Hinglish natural tone, अमृतसर / दिल्ली accent welcome).",
                "union_status": "CINTAA / Non-Union",
                "pay_terms": "INR 45,000 / shoot day",
                "callback_dates_text": "Dec 03, 2026",
                "shoot_dates_text": "Dec 12-18, 2026",
                "orientation": "Landscape",
                "file_naming": "inspector_kavita_nair_very_long_project_fullname.mp4",
            },
        }
        with tempfile.TemporaryDirectory() as tmp:
            png_path = Path(tmp) / "wrapped_two_col.png"
            render_poster_png_fallback(long_sample, png_path)
            self.assertEqual(read_png_dimensions_and_validate(png_path), (768, 960))

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


class TestColabTrainingAndRelease(unittest.TestCase):
    def test_needle3_dry_run_config_and_command_validation(self) -> None:
        from scripts.colab.train_needle3_lora import (
            Needle3TrainConfig,
            build_cactus_convert_command,
            validate_needle_config,
        )

        cfg = Needle3TrainConfig()
        validate_needle_config(cfg)
        cmd = build_cactus_convert_command(
            base_model=cfg.base_model,
            output_dir=cfg.export_dir,
            lora_dir=cfg.lora_dir,
            bits=cfg.quant_bits,
        )
        self.assertEqual(cmd[:2], ["cactus", "convert"])
        self.assertIn("--lora", cmd)
        self.assertEqual(cmd[-2:], ["--bits", "2"])

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            build_corpus(output_dir=tmp_dir, train_count=4, eval_count=2, seed=11)
            proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "train_needle3_lora.py"),
                    "--dry-run",
                    "--require-data",
                    "--train-file",
                    str(tmp_dir / "train_needle.jsonl"),
                    "--eval-file",
                    str(tmp_dir / "eval_needle.jsonl"),
                    "--output-dir",
                    str(tmp_dir / "out"),
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            payload = json.loads(proc.stdout)
            self.assertEqual(payload["config"]["quant_bits"], 2)
            self.assertEqual(payload["config"]["max_seq_len"], 1024)
            self.assertEqual(payload["config"]["output_name"], "needle3-onetake-cq2")
            self.assertIn("--bits", payload["cactus_convert_command"])
            self.assertIn("2", payload["cactus_convert_command"])
            self.assertTrue(any("eval_offline_v2.py" in part for part in payload["eval_command"]))
            self.assertEqual(payload["data_status"]["train_rows"], 4)
            self.assertEqual(payload["data_status"]["eval_rows"], 2)

            bad_proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "train_needle3_lora.py"),
                    "--dry-run",
                    "--max-seq-len",
                    "2048",
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(bad_proc.returncode, 0)

    def test_lfm25_vl_dry_run_config_and_fallback_model(self) -> None:
        from scripts.colab.train_lfm25_vl_lora import (
            LFM25VLTrainConfig,
            validate_vlm_config,
        )

        cfg = LFM25VLTrainConfig()
        validate_vlm_config(cfg)
        self.assertEqual(cfg.model_id, "LiquidAI/LFM2.5-VL-450M")
        self.assertEqual(cfg.fallback_model_id, "LiquidAI/LFM2-VL-450M")
        self.assertEqual(cfg.quant_bits, 4)

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            build_corpus(output_dir=tmp_dir, train_count=4, eval_count=2, seed=17)
            proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "train_lfm25_vl_lora.py"),
                    "--dry-run",
                    "--require-data",
                    "--train-file",
                    str(tmp_dir / "train_vlm.jsonl"),
                    "--eval-file",
                    str(tmp_dir / "eval_vlm.jsonl"),
                    "--output-dir",
                    str(tmp_dir / "out_vlm"),
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr)
            payload = json.loads(proc.stdout)
            self.assertEqual(payload["config"]["model_id"], "LiquidAI/LFM2.5-VL-450M")
            self.assertEqual(payload["config"]["fallback_model_id"], "LiquidAI/LFM2-VL-450M")
            self.assertEqual(payload["config"]["output_name"], "lfm2.5-vl-450m-onetake-cq4")
            self.assertEqual(payload["config"]["quant_bits"], 4)
            self.assertEqual(payload["cactus_convert_command"][:3], ["cactus", "convert", "LiquidAI/LFM2.5-VL-450M"])
            self.assertEqual(payload["cactus_convert_command"][-2:], ["--bits", "4"])
            self.assertEqual(payload["data_status"]["train_rows"], 4)
            self.assertEqual(payload["data_status"]["eval_rows"], 2)

            fallback_proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "train_lfm25_vl_lora.py"),
                    "--dry-run",
                    "--model-id",
                    "LiquidAI/LFM2-VL-450M",
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(fallback_proc.returncode, 0, msg=fallback_proc.stderr)
            fallback_payload = json.loads(fallback_proc.stdout)
            self.assertEqual(fallback_payload["cactus_convert_command"][2], "LiquidAI/LFM2-VL-450M")

            bad_bits_proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "train_lfm25_vl_lora.py"),
                    "--dry-run",
                    "--bits",
                    "5",
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(bad_bits_proc.returncode, 0)

    def test_publish_release_manifest_sha256_and_deterministic_zip(self) -> None:
        from scripts.colab.publish_release import (
            REQUIRED_MANIFEST_KEYS,
            publish_release,
        )

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            weights_dir = tmp_dir / "lfm2.5-vl-450m-onetake-cq4"
            weights_dir.mkdir(parents=True)
            (weights_dir / "config.json").write_text('{"arch": "lfm2.5-vl", "bits": 4}\n', encoding="utf-8")
            (weights_dir / "weights.bin").write_bytes(b"CQ4_FAKE_WEIGHT_BYTES_0123456789" * 64)

            eval_report_path = tmp_dir / "eval_report.json"
            eval_report_path.write_text(
                json.dumps(
                    {
                        "samples": 500,
                        "valid_json_rate": 0.996,
                        "schema_valid_rate": 0.992,
                        "exact_match": {
                            "submission_email": 0.99,
                            "sides_link": 0.985,
                        },
                        "core_f1": 0.935,
                    }
                ),
                encoding="utf-8",
            )

            out_a = tmp_dir / "release_a"
            result_a = publish_release(
                weights_path=weights_dir,
                eval_report_path=eval_report_path,
                output_dir=out_a,
                model_id="lfm2.5-vl-450m-onetake-cq4",
                version="2.0.0",
                min_app_version="2.0.0",
                download_url="https://huggingface.co/OneTake/models/resolve/main/lfm2.5-vl-450m-onetake-cq4-2.0.0.zip",
                target="local",
            )
            manifest_path = Path(result_a["manifest_path"])
            archive_path = Path(result_a["archive_path"])
            self.assertTrue(manifest_path.exists())
            self.assertTrue(archive_path.exists())

            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            self.assertTrue(set(REQUIRED_MANIFEST_KEYS).issubset(manifest.keys()))
            self.assertEqual(manifest["modelId"], "lfm2.5-vl-450m-onetake-cq4")
            self.assertEqual(manifest["version"], "2.0.0")
            self.assertEqual(manifest["minAppVersion"], "2.0.0")
            self.assertEqual(
                manifest["downloadURL"],
                "https://huggingface.co/OneTake/models/resolve/main/lfm2.5-vl-450m-onetake-cq4-2.0.0.zip",
            )

            actual_bytes = archive_path.read_bytes()
            expected_sha256 = hashlib.sha256(actual_bytes).hexdigest()
            self.assertEqual(manifest["byteSize"], len(actual_bytes))
            self.assertEqual(manifest["sha256"], expected_sha256)

            with zipfile.ZipFile(archive_path, "r") as zf:
                self.assertEqual(sorted(zf.namelist()), ["config.json", "weights.bin"])

            # Packaging the same weights directory again must yield identical SHA-256
            out_b = tmp_dir / "release_b"
            result_b = publish_release(
                weights_path=weights_dir,
                eval_report_path=eval_report_path,
                output_dir=out_b,
                model_id="lfm2.5-vl-450m-onetake-cq4",
                version="2.0.0",
                min_app_version="2.0.0",
                download_url="https://huggingface.co/OneTake/models/resolve/main/lfm2.5-vl-450m-onetake-cq4-2.0.0.zip",
                target="local",
            )
            self.assertEqual(result_a["manifest"]["sha256"], result_b["manifest"]["sha256"])

            # Dry-run CLI with huggingface target must not require huggingface_hub or network
            dry_proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "publish_release.py"),
                    "--weights-dir",
                    str(weights_dir),
                    "--eval-report",
                    str(eval_report_path),
                    "--output-dir",
                    str(tmp_dir / "release_dry"),
                    "--model-id",
                    "lfm2.5-vl-450m-onetake-cq4",
                    "--version",
                    "2.0.0",
                    "--target",
                    "huggingface",
                    "--hf-repo",
                    "OneTake/offline-v2-models",
                    "--dry-run",
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(dry_proc.returncode, 0, msg=dry_proc.stderr)
            dry_payload = json.loads(dry_proc.stdout)
            self.assertTrue(dry_payload["dry_run"])
            self.assertEqual(dry_payload["manifest"]["sha256"], expected_sha256)

    def test_publish_release_accuracy_gate_thresholds(self) -> None:
        from scripts.colab.publish_release import check_accuracy_gate

        # Boundary pass
        passed = check_accuracy_gate(
            {
                "samples": 500,
                "exact_match": {"submission_email": 0.98, "sides_link": 0.98},
                "core_f1": 0.90,
            }
        )
        self.assertTrue(passed["passed"])

        # Fail on email < 0.98
        with self.assertRaises(ValueError):
            check_accuracy_gate(
                {
                    "samples": 500,
                    "exact_match": {"submission_email": 0.979, "sides_link": 0.99},
                    "core_f1": 0.95,
                }
            )

        # Fail on core_f1 < 0.90
        with self.assertRaises(ValueError):
            check_accuracy_gate(
                {
                    "samples": 500,
                    "exact_match": {"submission_email": 0.99, "sides_link": 0.99},
                    "core_f1": 0.899,
                }
            )

        # CLI must exit non-zero and refuse to write manifest when gate fails
        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            weights_dir = tmp_dir / "weights"
            weights_dir.mkdir()
            (weights_dir / "weights.bin").write_bytes(b"1234")
            failing_report = tmp_dir / "failing_eval.json"
            failing_report.write_text(
                json.dumps(
                    {
                        "samples": 500,
                        "exact_match": {"submission_email": 0.95, "sides_link": 0.98},
                        "core_f1": 0.92,
                    }
                ),
                encoding="utf-8",
            )
            out_dir = tmp_dir / "out"
            proc = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "scripts" / "colab" / "publish_release.py"),
                    "--weights-dir",
                    str(weights_dir),
                    "--eval-report",
                    str(failing_report),
                    "--output-dir",
                    str(out_dir),
                    "--model-id",
                    "lfm2.5-vl-450m-onetake-cq4",
                    "--version",
                    "2.0.0",
                ],
                cwd=str(REPO_ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertFalse((out_dir / "manifest.json").exists())

    def test_publish_release_packages_single_bin_file_as_valid_zip(self) -> None:
        from scripts.colab.publish_release import package_release_artifact

        with tempfile.TemporaryDirectory() as tmp:
            tmp_dir = Path(tmp)
            single_file = tmp_dir / "needle3-onetake-cq2.bin"
            single_file.write_bytes(b"NEEDLE3_RAW_BYTES_SAMPLE_9999")
            out_zip = tmp_dir / "needle3-onetake-cq2.zip"

            packaged = package_release_artifact(single_file, out_zip)
            self.assertEqual(packaged, out_zip)
            self.assertTrue(out_zip.exists())
            self.assertTrue(zipfile.is_zipfile(out_zip))

            with zipfile.ZipFile(out_zip, "r") as zf:
                self.assertEqual(zf.namelist(), ["needle3-onetake-cq2.bin"])
                self.assertEqual(zf.read("needle3-onetake-cq2.bin"), b"NEEDLE3_RAW_BYTES_SAMPLE_9999")

    def test_publish_release_accuracy_gate_rejects_nan(self) -> None:
        from scripts.colab.publish_release import check_accuracy_gate

        with self.assertRaises(ValueError):
            check_accuracy_gate(
                {
                    "samples": 100,
                    "exact_match": {"submission_email": float("nan"), "sides_link": 0.99},
                    "core_f1": 0.95,
                }
            )

        with self.assertRaises(ValueError):
            check_accuracy_gate(
                {
                    "samples": 100,
                    "exact_match": {"submission_email": 0.99, "sides_link": 0.99},
                    "core_f1": float("nan"),
                }
            )

    def test_vlm_multimodal_message_normalization_and_label_masking(self) -> None:
        from scripts.colab.train_lfm25_vl_lora import compute_vlm_labels, normalize_vlm_messages

        # Plain string user message with image present -> converted to multimodal blocks
        msgs = [
            {"role": "user", "content": "Extract notice JSON."},
            {"role": "assistant", "content": '{"project": "Test"}'},
        ]
        norm = normalize_vlm_messages(msgs, has_image=True)
        self.assertEqual(norm[0]["role"], "user")
        self.assertEqual(
            norm[0]["content"],
            [
                {"type": "image"},
                {"type": "text", "text": "Extract notice JSON."},
            ],
        )
        self.assertEqual(norm[1]["content"], '{"project": "Test"}')

        # User message without image -> preserves plain string
        norm_no_img = normalize_vlm_messages(msgs, has_image=False)
        self.assertEqual(norm_no_img[0]["content"], "Extract notice JSON.")

        # compute_vlm_labels masks prompt length with -100
        # Suppose input_ids has 10 tokens: prompt is first 4 tokens, assistant is next 6 tokens
        fake_ids = [[101, 102, 103, 104, 201, 202, 203, 204, 205, 0]]
        prompt_lens = [4]
        labels = compute_vlm_labels(fake_ids, prompt_lens, pad_token_id=0)
        # First 4 tokens should be -100
        self.assertEqual(labels[0][:4], [-100, -100, -100, -100])
        # Next 5 tokens should be preserved
        self.assertEqual(labels[0][4:9], [201, 202, 203, 204, 205])
        # Last token (pad) should be -100
        self.assertEqual(labels[0][9], -100)


if __name__ == "__main__":
    unittest.main()
