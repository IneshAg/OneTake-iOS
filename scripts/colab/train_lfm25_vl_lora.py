#!/usr/bin/env python3
"""Google Colab LFM2.5-VL-450M LoRA Trainer & Cactus CQ4 Exporter.

Consumes `train_vlm.jsonl`, `eval_vlm.jsonl`, and poster PNG images produced by
`scripts/colab/build_offline_v2_corpus.py`, LoRA fine-tunes
`LiquidAI/LFM2.5-VL-450M` (or fallback `LiquidAI/LFM2-VL-450M`) on Colab L4/A100
GPU, merges & quantizes via `cactus convert ... --lora ... --bits 4` targeting
`lfm2.5-vl-450m-onetake-cq4` (~350-400 MB), and optionally runs held-out
evaluation via `scripts/colab/eval_offline_v2.py`.

Local macOS `--dry-run` mode requires Python stdlib only (no torch,
transformers, peft, Pillow, or GPU required).
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

try:
    from scripts.colab.train_needle3_lora import (
        DEFAULT_DATASET_DIR,
        MAX_NEEDLE_SEQ_LEN,
        REPO_ROOT,
        add_shared_training_args,
        build_cactus_convert_command,
        build_eval_command,
        finalize_held_out_eval,
        inspect_jsonl_dataset,
        load_jsonl_rows,
        run_cactus_convert,
        serialize_config,
        validate_common_lora_hparams,
    )
except ImportError:  # pragma: no cover - direct script invocation
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from scripts.colab.train_needle3_lora import (
        DEFAULT_DATASET_DIR,
        MAX_NEEDLE_SEQ_LEN,
        REPO_ROOT,
        add_shared_training_args,
        build_cactus_convert_command,
        build_eval_command,
        finalize_held_out_eval,
        inspect_jsonl_dataset,
        load_jsonl_rows,
        run_cactus_convert,
        serialize_config,
        validate_common_lora_hparams,
    )

DEFAULT_VLM_OUTPUT_ROOT = REPO_ROOT / "artifacts" / "offline_v2" / "lfm25_vl"
DEFAULT_VLM_MODEL_ID = "LiquidAI/LFM2.5-VL-450M"
DEFAULT_VLM_FALLBACK_MODEL_ID = "LiquidAI/LFM2-VL-450M"
DEFAULT_VLM_OUTPUT_NAME = "lfm2.5-vl-450m-onetake-cq4"
DEFAULT_MAX_IMAGE_EDGE = 768
MAX_VLM_SEQ_LEN = 2048


def normalize_vlm_messages(
    messages: list[dict[str, Any]],
    *,
    has_image: bool = True,
) -> list[dict[str, Any]]:
    """Normalize user messages into multimodal blocks [{"type": "image"}, {"type": "text", "text": ...}]
    when an image is present, matching HuggingFace AutoProcessor expectations.
    """
    normalized: list[dict[str, Any]] = []
    for msg in messages:
        role = msg.get("role", "")
        content = msg.get("content", "")
        if role != "user":
            normalized.append(dict(msg))
            continue

        if not has_image:
            if isinstance(content, list):
                filtered = [
                    item
                    for item in content
                    if not (isinstance(item, dict) and item.get("type") == "image")
                ]
                normalized.append({**msg, "content": filtered})
            else:
                normalized.append(dict(msg))
            continue

        # has_image is True
        if isinstance(content, str):
            normalized.append(
                {
                    **msg,
                    "content": [
                        {"type": "image"},
                        {"type": "text", "text": content},
                    ],
                }
            )
        elif isinstance(content, list):
            items = list(content)
            has_img_block = any(
                isinstance(item, dict) and item.get("type") == "image" for item in items
            )
            if not has_img_block:
                items.insert(0, {"type": "image"})
            normalized.append({**msg, "content": items})
        else:
            normalized.append(
                {
                    **msg,
                    "content": [
                        {"type": "image"},
                        {"type": "text", "text": str(content)},
                    ],
                }
            )
    return normalized


def compute_vlm_labels(
    input_ids: Any,
    prompt_lengths: list[int],
    *,
    pad_token_id: int | None = None,
) -> Any:
    """Mask prompt + image tokens and padding with -100 so loss is computed solely on assistant responses.

    Works with both PyTorch tensors and plain Python nested lists.
    """
    if hasattr(input_ids, "clone"):
        labels = input_ids.clone()
        for idx, prompt_len in enumerate(prompt_lengths):
            limit = min(prompt_len, labels.shape[-1])
            labels[idx, :limit] = -100
        if pad_token_id is not None:
            labels[labels == pad_token_id] = -100
        return labels

    labels_list: list[list[int]] = [list(seq) for seq in input_ids]
    for idx, prompt_len in enumerate(prompt_lengths):
        seq = labels_list[idx]
        limit = min(prompt_len, len(seq))
        for j in range(limit):
            seq[j] = -100
        if pad_token_id is not None:
            for j in range(len(seq)):
                if seq[j] == pad_token_id:
                    seq[j] = -100
    return labels_list


@dataclass
class LFM25VLTrainConfig:
    model_id: str = DEFAULT_VLM_MODEL_ID
    fallback_model_id: str = DEFAULT_VLM_FALLBACK_MODEL_ID
    train_file: Path = DEFAULT_DATASET_DIR / "train_vlm.jsonl"
    eval_file: Path = DEFAULT_DATASET_DIR / "eval_vlm.jsonl"
    output_dir: Path = DEFAULT_VLM_OUTPUT_ROOT
    output_name: str = DEFAULT_VLM_OUTPUT_NAME
    lora_r: int = 16
    lora_alpha: int = 32
    lora_dropout: float = 0.05
    learning_rate: float = 1e-4
    epochs: int = 3
    batch_size: int = 2
    grad_accum_steps: int = 8
    max_seq_len: int = MAX_NEEDLE_SEQ_LEN
    max_image_edge: int = DEFAULT_MAX_IMAGE_EDGE
    quant_bits: int = 4
    target_modules: tuple[str, ...] = ("q_proj", "k_proj", "v_proj", "o_proj")
    seed: int = 42
    predictions_file: Path | None = None
    eval_output: Path | None = None
    skip_eval: bool = False
    require_quantized_eval: bool = False

    @property
    def lora_dir(self) -> Path:
        return self.output_dir / "lora_adapter"

    @property
    def export_dir(self) -> Path:
        return self.output_dir / self.output_name

    @property
    def resolved_predictions_file(self) -> Path:
        return self.predictions_file or (self.output_dir / "eval_vlm_predictions.jsonl")

    @property
    def resolved_eval_output(self) -> Path:
        return self.eval_output or (self.output_dir / "eval_vlm_report.json")


def validate_vlm_config(cfg: LFM25VLTrainConfig) -> None:
    """Validate LFM2.5-VL-450M LoRA & CQ4 export configuration."""
    if not cfg.model_id.strip():
        raise ValueError("model_id must be non-empty")
    if not cfg.fallback_model_id.strip():
        raise ValueError("fallback_model_id must be non-empty")
    if not cfg.output_name.strip():
        raise ValueError("output_name must be non-empty")
    if not cfg.target_modules:
        raise ValueError("target_modules must be non-empty")
    if not (224 <= cfg.max_image_edge <= 1536):
        raise ValueError(
            f"max_image_edge must be in [224, 1536], got {cfg.max_image_edge}"
        )
    validate_common_lora_hparams(
        lora_r=cfg.lora_r,
        lora_alpha=cfg.lora_alpha,
        lora_dropout=cfg.lora_dropout,
        learning_rate=cfg.learning_rate,
        epochs=cfg.epochs,
        batch_size=cfg.batch_size,
        grad_accum_steps=cfg.grad_accum_steps,
        max_seq_len=cfg.max_seq_len,
        quant_bits=cfg.quant_bits,
        max_allowed_seq_len=MAX_VLM_SEQ_LEN,
        allowed_bits=(4, 8),
        skip_eval=cfg.skip_eval,
        require_quantized_eval=cfg.require_quantized_eval,
    )


def build_vlm_plan(
    cfg: LFM25VLTrainConfig,
    *,
    require_data: bool = False,
) -> dict[str, Any]:
    """Validate config/data and construct the LFM2.5-VL-450M training/export/eval plan."""
    validate_vlm_config(cfg)
    train_status = inspect_jsonl_dataset(cfg.train_file, require_exists=require_data)
    eval_status = inspect_jsonl_dataset(cfg.eval_file, require_exists=require_data)
    convert_cmd = build_cactus_convert_command(
        base_model=cfg.model_id,
        output_dir=cfg.export_dir,
        lora_dir=cfg.lora_dir,
        bits=cfg.quant_bits,
    )
    fallback_convert_cmd = build_cactus_convert_command(
        base_model=cfg.fallback_model_id,
        output_dir=cfg.export_dir,
        lora_dir=cfg.lora_dir,
        bits=cfg.quant_bits,
    )
    eval_cmd = build_eval_command(
        eval_file=cfg.eval_file,
        predictions_file=cfg.resolved_predictions_file,
        output_file=cfg.resolved_eval_output,
    )
    eval_mode = (
        "skipped"
        if cfg.skip_eval
        else (
            "quantized_required"
            if cfg.require_quantized_eval
            else "quantized_preferred_with_peft_fallback"
        )
    )
    return {
        "trainer": "lfm25_vl_lora",
        "config": serialize_config(cfg),
        "eval_mode": eval_mode,
        "output_paths": {
            "lora_dir": str(cfg.lora_dir),
            "export_dir": str(cfg.export_dir),
            "predictions_file": str(cfg.resolved_predictions_file),
            "eval_output": str(cfg.resolved_eval_output),
        },
        "data_status": {
            "train_file": train_status["path"],
            "train_exists": train_status["exists"],
            "train_rows": train_status["rows"],
            "eval_file": eval_status["path"],
            "eval_exists": eval_status["exists"],
            "eval_rows": eval_status["rows"],
        },
        "cactus_convert_command": convert_cmd,
        "fallback_cactus_convert_command": fallback_convert_cmd,
        "eval_command": eval_cmd,
    }


def _load_vlm_rows(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def _resize_poster_image(image_path: Path, max_edge: int) -> Any:
    from PIL import Image  # type: ignore

    img = Image.open(image_path).convert("RGB")
    width, height = img.size
    longest = max(width, height)
    if longest > max_edge:
        scale = max_edge / float(longest)
        new_size = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
        img = img.resize(new_size, Image.Resampling.LANCZOS)
    return img


def _resolve_vlm_model_and_processor(
    model_id: str,
    fallback_model_id: str,
    torch_dtype: Any,
) -> tuple[str, Any, Any]:
    from transformers import AutoModelForImageTextToText, AutoProcessor  # type: ignore

    candidates = [model_id]
    if fallback_model_id and fallback_model_id != model_id:
        candidates.append(fallback_model_id)

    last_error: Exception | None = None
    for candidate in candidates:
        try:
            processor = AutoProcessor.from_pretrained(candidate, trust_remote_code=True)
            model = AutoModelForImageTextToText.from_pretrained(
                candidate,
                torch_dtype=torch_dtype,
                trust_remote_code=True,
            )
            return candidate, processor, model
        except (OSError, ValueError) as exc:
            last_error = exc
    raise RuntimeError(
        f"Unable to load VLM model from {candidates}: {last_error}"
    ) from last_error


def _generate_vlm_predictions(
    *,
    model: Any,
    processor: Any,
    eval_rows: list[dict[str, Any]],
    dataset_root: Path,
    output_path: Path,
    max_image_edge: int,
) -> Path:
    import torch  # type: ignore

    output_path.parent.mkdir(parents=True, exist_ok=True)
    model.eval()
    device = next(model.parameters()).device

    with output_path.open("w", encoding="utf-8") as handle:
        for idx, row in enumerate(eval_rows):
            row_id = str(row.get("id", idx))
            image_rel = row.get("image")
            image_path = dataset_root / image_rel if image_rel else None
            image = (
                _resize_poster_image(image_path, max_image_edge)
                if image_path and image_path.exists()
                else None
            )
            raw_prompt_messages = [m for m in row["messages"] if m.get("role") != "assistant"]
            prompt_messages = normalize_vlm_messages(
                raw_prompt_messages,
                has_image=image is not None,
            )
            prompt_text = processor.apply_chat_template(
                prompt_messages,
                tokenize=False,
                add_generation_prompt=True,
            )
            inputs = processor(
                text=[prompt_text],
                images=[image] if image is not None else None,
                return_tensors="pt",
                padding=True,
            ).to(device)
            with torch.no_grad():
                generated = model.generate(**inputs, max_new_tokens=384, do_sample=False)
            prompt_len = inputs["input_ids"].shape[-1]
            decoded = processor.batch_decode(
                generated[:, prompt_len:], skip_special_tokens=True
            )[0].strip()
            handle.write(json.dumps({"id": row_id, "prediction": decoded}, ensure_ascii=False) + "\n")
    return output_path


def run_vlm_training(cfg: LFM25VLTrainConfig) -> dict[str, Any]:
    """Execute LFM2.5-VL-450M LoRA training, Cactus CQ4 export, and optional eval on Colab GPU."""
    plan = build_vlm_plan(cfg, require_data=True)
    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    cfg.lora_dir.mkdir(parents=True, exist_ok=True)

    # Lazy imports so local macOS `--dry-run` works with zero third-party packages.
    import torch  # type: ignore
    from peft import LoraConfig, get_peft_model  # type: ignore
    from torch.utils.data import Dataset  # type: ignore
    from transformers import Trainer, TrainingArguments  # type: ignore

    torch.manual_seed(cfg.seed)
    use_bf16 = bool(torch.cuda.is_available() and torch.cuda.is_bf16_supported())
    dtype = torch.bfloat16 if use_bf16 else (torch.float16 if torch.cuda.is_available() else torch.float32)

    resolved_model_id, processor, model = _resolve_vlm_model_and_processor(
        cfg.model_id,
        cfg.fallback_model_id,
        dtype,
    )
    model.config.use_cache = False

    lora_config = LoraConfig(
        r=cfg.lora_r,
        lora_alpha=cfg.lora_alpha,
        lora_dropout=cfg.lora_dropout,
        target_modules=list(cfg.target_modules),
        bias="none",
        task_type="CAUSAL_LM",
    )
    model = get_peft_model(model, lora_config)

    train_rows = _load_vlm_rows(cfg.train_file)
    eval_rows = _load_vlm_rows(cfg.eval_file)
    train_root = cfg.train_file.parent
    eval_root = cfg.eval_file.parent

    class PosterDataset(Dataset):
        def __init__(self, rows: list[dict[str, Any]], root_dir: Path) -> None:
            self.rows = rows
            self.root_dir = root_dir

        def __len__(self) -> int:
            return len(self.rows)

        def __getitem__(self, index: int) -> dict[str, Any]:
            row = self.rows[index]
            image = _resize_poster_image(self.root_dir / row["image"], cfg.max_image_edge)
            return {"messages": row["messages"], "image": image}

    def collate_vlm_batch(batch: list[dict[str, Any]]) -> dict[str, Any]:
        prompt_lengths: list[int] = []
        normalized_full_texts: list[str] = []
        images: list[Any] = []

        for item in batch:
            img = item.get("image")
            has_img = img is not None
            norm_msgs = normalize_vlm_messages(item["messages"], has_image=has_img)
            prompt_msgs = [m for m in norm_msgs if m.get("role") != "assistant"]
            prompt_text = processor.apply_chat_template(
                prompt_msgs, tokenize=False, add_generation_prompt=True
            )
            full_text = processor.apply_chat_template(
                norm_msgs, tokenize=False, add_generation_prompt=False
            )
            normalized_full_texts.append(full_text)
            images.append(img)

            prompt_inputs = processor(
                text=[prompt_text],
                images=[img] if has_img else None,
                return_tensors="pt",
            )
            prompt_lengths.append(int(prompt_inputs["input_ids"].shape[-1]))

        has_any_images = any(img is not None for img in images)
        encoded = processor(
            text=normalized_full_texts,
            images=images if has_any_images else None,
            return_tensors="pt",
            padding=True,
            truncation=False,
        )
        pad_id = getattr(getattr(processor, "tokenizer", processor), "pad_token_id", None)
        encoded["labels"] = compute_vlm_labels(
            encoded["input_ids"],
            prompt_lengths,
            pad_token_id=pad_id,
        )
        return encoded

    training_args = TrainingArguments(
        output_dir=str(cfg.output_dir / "checkpoints"),
        num_train_epochs=cfg.epochs,
        per_device_train_batch_size=cfg.batch_size,
        per_device_eval_batch_size=cfg.batch_size,
        gradient_accumulation_steps=cfg.grad_accum_steps,
        learning_rate=cfg.learning_rate,
        bf16=use_bf16,
        fp16=bool(torch.cuda.is_available() and not use_bf16),
        remove_unused_columns=False,
        logging_steps=10,
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=2,
        report_to="none",
        seed=cfg.seed,
    )
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=PosterDataset(train_rows, train_root),
        eval_dataset=PosterDataset(eval_rows, eval_root),
        data_collator=collate_vlm_batch,
    )
    trainer.train()
    model.save_pretrained(str(cfg.lora_dir))
    processor.save_pretrained(str(cfg.lora_dir))

    convert_cmd = build_cactus_convert_command(
        base_model=resolved_model_id,
        output_dir=cfg.export_dir,
        lora_dir=cfg.lora_dir,
        bits=cfg.quant_bits,
    )
    run_cactus_convert(convert_cmd)

    eval_report = finalize_held_out_eval(
        eval_file=cfg.eval_file,
        eval_rows=eval_rows,
        export_dir=cfg.export_dir,
        predictions_file=cfg.resolved_predictions_file,
        eval_output=cfg.resolved_eval_output,
        skip_eval=cfg.skip_eval,
        require_quantized_eval=cfg.require_quantized_eval,
        dataset_root=eval_root,
        peft_fallback_fn=lambda: _generate_vlm_predictions(
            model=model,
            processor=processor,
            eval_rows=eval_rows,
            dataset_root=eval_root,
            output_path=cfg.resolved_predictions_file,
            max_image_edge=cfg.max_image_edge,
        ),
    )

    plan["resolved_model_id"] = resolved_model_id
    plan["cactus_convert_command"] = convert_cmd
    return {"plan": plan, "eval_report": eval_report}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-id", type=str, default=DEFAULT_VLM_MODEL_ID)
    parser.add_argument("--fallback-model-id", type=str, default=DEFAULT_VLM_FALLBACK_MODEL_ID)
    parser.add_argument("--max-image-edge", type=int, default=DEFAULT_MAX_IMAGE_EDGE)
    parser.add_argument(
        "--target-modules",
        type=str,
        default="q_proj,k_proj,v_proj,o_proj",
        help="Comma-separated LoRA target module names.",
    )
    add_shared_training_args(
        parser,
        default_train_file=DEFAULT_DATASET_DIR / "train_vlm.jsonl",
        default_eval_file=DEFAULT_DATASET_DIR / "eval_vlm.jsonl",
        default_output_dir=DEFAULT_VLM_OUTPUT_ROOT,
        default_output_name=DEFAULT_VLM_OUTPUT_NAME,
        default_lr=1e-4,
        default_batch_size=2,
        default_grad_accum=8,
        default_bits=4,
    )
    return parser.parse_args(argv)


def config_from_args(args: argparse.Namespace) -> LFM25VLTrainConfig:
    modules = tuple(m.strip() for m in args.target_modules.split(",") if m.strip())
    return LFM25VLTrainConfig(
        model_id=args.model_id,
        fallback_model_id=args.fallback_model_id,
        train_file=args.train_file,
        eval_file=args.eval_file,
        output_dir=args.output_dir,
        output_name=args.output_name,
        lora_r=args.lora_r,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        learning_rate=args.lr,
        epochs=args.epochs,
        batch_size=args.batch_size,
        grad_accum_steps=args.grad_accum,
        max_seq_len=args.max_seq_len,
        max_image_edge=args.max_image_edge,
        quant_bits=args.bits,
        target_modules=modules,
        seed=args.seed,
        predictions_file=args.predictions_file,
        eval_output=args.eval_output,
        skip_eval=args.skip_eval,
        require_quantized_eval=args.require_quantized_eval,
    )


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = config_from_args(args)
    try:
        if args.dry_run:
            plan = build_vlm_plan(cfg, require_data=args.require_data)
            if args.config_out:
                args.config_out.parent.mkdir(parents=True, exist_ok=True)
                args.config_out.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(plan, indent=2))
            return 0
        result = run_vlm_training(cfg)
    except (ValueError, FileNotFoundError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    if args.config_out:
        args.config_out.parent.mkdir(parents=True, exist_ok=True)
        args.config_out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
