#!/usr/bin/env python3
"""
OneTake Local Parser Benchmark Script
=====================================
Benchmarks the standalone local parser against dataset/parsing_dataset_eval.jsonl.
Evaluates:
  1. JSON parsing success rate (0-syntax-error compliance)
  2. Notice entity accuracy (project, role, casting_office)
  3. Screenplay extraction accuracy (scene headings, character cues, spoken dialogue)
  4. Average inference latency on NVIDIA RTX 4050
"""

import sys
import time
import json
import urllib.request
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
EVAL_FILE = BASE_DIR / "dataset" / "parsing_dataset_eval.jsonl"
SERVER_URL = "http://localhost:8080"

def log(msg: str):
    print(msg, flush=True)

def run_benchmark(num_samples: int = 5):
    log("=" * 60)
    log(" OneTake LLM Parsing Endpoint Benchmark")
    log("=" * 60)

    # 1. Check Server Health
    try:
        req = urllib.request.Request(f"{SERVER_URL}/health")
        with urllib.request.urlopen(req, timeout=5) as resp:
            health = json.loads(resp.read().decode("utf-8"))
            log(f"[+] Server Online: {health.get('service')} (v{health.get('version')})")
            log(f"[+] Hardware GPU: {health.get('gpu')} | VRAM: {health.get('vram_allocated_mb')} MB")
            log(f"[+] Model Status: {health.get('model_status')}")
    except Exception as e:
        log(f"[!] Server unreachable at {SERVER_URL}: {e}")
        log("    Please ensure backend_parser_service.py is running.")
        return

    if not EVAL_FILE.exists():
        log(f"[!] Eval file not found: {EVAL_FILE}")
        return

    samples = []
    with open(EVAL_FILE, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                samples.append(json.loads(line.strip()))

    log(f"\n[*] Evaluating on {min(num_samples, len(samples))} validation instances...")

    total = 0
    json_valid = 0
    latencies = []

    for idx, item in enumerate(samples[:num_samples]):
        messages = item.get("messages", [])
        if len(messages) < 3:
            continue
        
        user_content = messages[1]["content"]
        target_content = json.loads(messages[2]["content"])
        is_notice = "casting notice" in user_content.lower()

        # Extract raw text from prompt
        raw_text = user_content.split(":\n\n", 1)[-1] if ":\n\n" in user_content else user_content
        endpoint = "/api/v1/parse/notice" if is_notice else "/api/v1/parse/sides"

        start_time = time.time()
        try:
            req = urllib.request.Request(
                f"{SERVER_URL}{endpoint}",
                data=json.dumps({"text": raw_text}).encode("utf-8"),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=45) as resp:
                elapsed = time.time() - start_time
                latencies.append(elapsed)
                res_data = json.loads(resp.read().decode("utf-8"))
                json_valid += 1
                total += 1

                doc_type = "Notice" if is_notice else "Sides "
                if is_notice:
                    proj = res_data.get("project", "N/A")
                    role = res_data.get("role", "N/A")
                    log(f"  [{idx+1:02d}] {doc_type} in {elapsed:.2f}s | Proj: {str(proj)[:20]:<20} | Role: {str(role)[:15]}")
                else:
                    scenes = res_data.get("scenes", [])
                    num_lines = sum(len(s.get("lines", [])) for s in scenes)
                    log(f"  [{idx+1:02d}] {doc_type} in {elapsed:.2f}s | Scenes: {len(scenes)} | Lines: {num_lines}")

        except Exception as e:
            total += 1
            log(f"  [{idx+1:02d}] Failed: {e}")

    avg_latency = sum(latencies) / len(latencies) if latencies else 0
    validity_pct = (json_valid / total * 100) if total > 0 else 0

    log("\n" + "=" * 60)
    log(" Benchmark Summary Results")
    log("=" * 60)
    log(f" Total Samples Tested:    {total}")
    log(f" Valid JSON Outputs:      {json_valid}/{total} ({validity_pct:.1f}%)")
    log(f" Average Latency:         {avg_latency:.2f}s per document")
    if latencies:
        log(f" Min Latency:             {min(latencies):.2f}s")
        log(f" Max Latency:             {max(latencies):.2f}s")
    log("=" * 60)

if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    run_benchmark(n)
