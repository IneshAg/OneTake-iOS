#!/usr/bin/env python3
"""
OneTake Core ML & Apple Neural Engine (ANE) Exporter
===================================================
Converts the fine-tuned OneTake parser model to Apple Core ML (.mlpackage)
with post-training 4-bit / 8-bit weight palettization optimized for
the Apple Neural Engine (ANE) on iPhone and iPad.

Features:
  - 100% Free & Offline On-Device Execution (zero cloud calls, zero API fees)
  - Apple Neural Engine (ANE) & Apple Silicon GPU compute unit targeting
  - 4-bit Weight Palettization (LUT table lookup) for minimal memory footprint
  - iOS 18+ deployment target (compatible with iOS 18+, iPadOS 18+, macOS 15+)
  - Proper author metadata: Inesh Agarwal <ineshag123@gmail.com>

Outputs:
  - models/OneTakeParserANE.mlpackage
"""

import os
import sys
import argparse
from pathlib import Path

import torch
import torch.nn as nn
from transformers import AutoModelForCausalLM, AutoTokenizer
import coremltools as ct
import coremltools.optimize.coreml as cto

BASE_DIR = Path(__file__).resolve().parent.parent
DEFAULT_MODEL_PATH = BASE_DIR / "models" / "onetake-parser-merged"
DEFAULT_OUTPUT_PACKAGE = BASE_DIR / "models" / "OneTakeParserANE.mlpackage"

class CoreMLParserWrapper(nn.Module):
    """
    Tracing wrapper for causal LM on Apple Neural Engine.
    Exposes input_ids -> logits with strict FP16 types for ANE efficiency.
    """
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, input_ids: torch.Tensor):
        outputs = self.model(input_ids=input_ids, return_dict=False)
        logits = outputs[0]
        return logits

def export_to_coreml(
    model_path: Path,
    output_package: Path,
    nbits: int = 4,
    max_seq_len: int = 512,
    device: str = "cpu"
):
    print("============================================================")
    print(" OneTake Core ML Exporter (Apple Neural Engine Palettization)")
    print("============================================================")
    print(f"[*] Source Model: {model_path}")
    print(f"[*] Destination Core ML Package: {output_package}")
    print(f"[*] Palettization Bit Width: {nbits}-bit")
    print(f"[*] Max Sequence Length: {max_seq_len}")

    if not model_path.exists():
        raise FileNotFoundError(f"Model path does not exist: {model_path}. Please run merge_lora_weights.py first.")

    # 1. Load Tokenizer & Model
    print("[*] Loading PyTorch model and tokenizer...")
    tokenizer = AutoTokenizer.from_pretrained(str(model_path), trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        str(model_path),
        torch_dtype=torch.float32,
        device_map=device,
        trust_remote_code=True,
        low_cpu_mem_usage=True
    )
    model.eval()

    wrapper = CoreMLParserWrapper(model)
    wrapper.eval()

    # 2. Prepare Sample Input for Tracing
    print(f"[*] Tracing model with sample input sequence (len=64)...")
    sample_input = torch.randint(0, min(1000, model.config.vocab_size), (1, 64), dtype=torch.int32)

    with torch.no_grad():
        traced_model = torch.jit.trace(wrapper, (sample_input,), strict=False)

    # 3. Configure Flexible Input Shapes for Dynamic Sequence Lengths
    print("[*] Setting dynamic sequence length ranges [1, 512] for ANE...")
    seq_dim = ct.RangeDim(lower_bound=1, upper_bound=max_seq_len, default=64)
    inputs = [
        ct.TensorType(name="input_ids", shape=(1, seq_dim), dtype=int)
    ]
    outputs = [
        ct.TensorType(name="logits", dtype=torch.float16)
    ]

    # 4. Convert PyTorch model to Core ML MIL format
    print("[*] Converting PyTorch model to Core ML MIL graph (iOS 18+ target)...")
    mlmodel = ct.convert(
        traced_model,
        inputs=inputs,
        outputs=outputs,
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.iOS18
    )

    # 5. Apply Post-Training Weight Palettization for ANE
    if nbits in (4, 8):
        print(f"[*] Applying {nbits}-bit Apple Neural Engine weight palettization...")
        try:
            op_config = cto.OpPalettizerConfig(
                mode="kmeans",
                nbits=nbits,
                granularity="per_grouped_channel",
                group_size=32
            )
            config = cto.OptimizationConfig(global_config=op_config)
            mlmodel = cto.palettize_weights(mlmodel, config=config)
            print(f"[OK] {nbits}-bit palettization completed.")
        except Exception as e:
            print(f"[!] Warning: Palettization threw: {e}. Falling back to default FP16 Core ML model.")

    # 6. Set User-Facing Metadata
    print("[*] Setting Core ML model metadata and author signatures...")
    mlmodel.author = "Inesh Agarwal <ineshag123@gmail.com>"
    mlmodel.license = "Proprietary - OneTake Auditions"
    mlmodel.short_description = "On-Device Neural Engine Parser for Audition Notices, Screenplay Sides, and Commercial Call Sheets."
    mlmodel.version = "1.0.0"

    mlmodel.input_description["input_ids"] = "Input token IDs parsed from OCR text"
    mlmodel.output_description["logits"] = "Output token logits for structured JSON prediction"

    # 7. Save .mlpackage
    output_package.parent.mkdir(parents=True, exist_ok=True)
    print(f"[*] Saving Core ML package to {output_package}...")
    mlmodel.save(str(output_package))

    print(f"[OK] Successfully exported Core ML model to {output_package}!")
    print(f"[OK] Model is 100% offline and ready for Apple Neural Engine deployment in Xcode!")

def main():
    parser = argparse.ArgumentParser(description="Export OneTake parser to Core ML (.mlpackage) for Apple Neural Engine.")
    parser.add_argument("--model-path", type=Path, default=DEFAULT_MODEL_PATH, help="Path to merged model directory")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_PACKAGE, help="Path to output .mlpackage")
    parser.add_argument("--nbits", type=int, default=4, choices=[4, 8, 16], help="Weight palettization bit width (4 or 8)")
    parser.add_argument("--max-seq-len", type=int, default=512, help="Maximum sequence length")
    parser.add_argument("--device", type=str, default="cpu", help="Compute device for conversion")

    args = parser.parse_args()
    export_to_coreml(args.model_path, args.output, args.nbits, args.max_seq_len, args.device)

if __name__ == "__main__":
    main()
