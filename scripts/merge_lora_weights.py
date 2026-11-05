#!/usr/bin/env python3
"""
OneTake LoRA Weight Merger
==========================
Merges the trained PEFT LoRA adapter weights from:
  models/onetake-parser-lora/
into the base model:
  Qwen/Qwen2.5-1.5B-Instruct
and outputs a standalone, consolidated FP16 model to:
  models/onetake-parser-merged/

This standalone model can then be used for:
  1. Direct GPU inference via FastAPI / vLLM
  2. Conversion to Apple Core ML (.mlpackage) for Apple Neural Engine
"""

import os
import sys
import argparse
from pathlib import Path

import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from peft import PeftModel

BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_LORA_PATH = BASE_DIR / "models" / "onetake-parser-lora"
DEFAULT_OUTPUT_PATH = BASE_DIR / "models" / "onetake-parser-merged"

def merge_lora(lora_path: Path, output_path: Path, base_model_name: str = None, device: str = "cpu"):
    print("============================================================")
    print(" OneTake LoRA Weight Merger")
    print("============================================================")
    print(f"[*] LoRA Adapter Source: {lora_path}")
    print(f"[*] Merged Output Target: {output_path}")

    if not lora_path.exists():
        raise FileNotFoundError(f"LoRA directory does not exist: {lora_path}")

    # Detect base model from adapter config if not specified
    if not base_model_name:
        import json
        config_file = lora_path / "adapter_config.json"
        if config_file.exists():
            with open(config_file, "r", encoding="utf-8") as f:
                cfg = json.load(f)
                base_model_name = cfg.get("base_model_name_or_path", "Qwen/Qwen2.5-1.5B-Instruct")
        else:
            base_model_name = "Qwen/Qwen2.5-1.5B-Instruct"

    print(f"[*] Base Model Name: {base_model_name}")
    print(f"[*] Target Compute Device for Merge: {device}")

    # Load tokenizer
    print("[*] Loading tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(str(lora_path), trust_remote_code=True)

    # Load base model in FP16
    print(f"[*] Loading base model {base_model_name} in torch.float16...")
    dtype = torch.float16 if torch.cuda.is_available() and device != "cpu" else torch.float32
    torch_device = torch.device(device if torch.cuda.is_available() and device != "cpu" else "cpu")

    base_model = AutoModelForCausalLM.from_pretrained(
        base_model_name,
        torch_dtype=dtype,
        device_map=device if device != "cpu" else None,
        trust_remote_code=True,
        low_cpu_mem_usage=True
    )

    # Load LoRA adapter
    print(f"[*] Attaching LoRA weights from {lora_path}...")
    peft_model = PeftModel.from_pretrained(
        base_model,
        str(lora_path),
        torch_dtype=dtype,
        device_map=device if device != "cpu" else None
    )

    # Merge weights
    print("[*] Merging LoRA layers into base model weights...")
    merged_model = peft_model.merge_and_unload()
    merged_model.eval()

    # Save consolidated model
    output_path.mkdir(parents=True, exist_ok=True)
    print(f"[*] Saving consolidated model to {output_path}...")
    merged_model.save_pretrained(str(output_path), safe_serialization=True)
    tokenizer.save_pretrained(str(output_path))

    print(f"[OK] Successfully merged LoRA weights into {output_path}!")

def main():
    parser = argparse.ArgumentParser(description="Merge LoRA adapter into base model weights.")
    parser.add_argument("--lora", type=Path, default=DEFAULT_LORA_PATH, help="Path to LoRA directory")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PATH, help="Path to save merged model")
    parser.add_argument("--base-model", type=str, default=None, help="Base model identifier or path")
    parser.add_argument("--device", type=str, default="cuda" if torch.cuda.is_available() else "cpu", help="Device for merge operation (cuda or cpu)")

    args = parser.parse_args()
    merge_lora(args.lora, args.output, args.base_model, args.device)

if __name__ == "__main__":
    main()
