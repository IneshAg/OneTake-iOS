#!/usr/bin/env python3
"""Google Colab Needle 3 LoRA Trainer & Cactus CQ2 Exporter.

Consumes `train_needle.jsonl` and `eval_needle.jsonl` produced by
`scripts/colab/build_offline_v2_corpus.py`, LoRA fine-tunes Needle 3
(`max_seq_len=1024`), exports a 2-bit Cactus bundle (`needle3-onetake-cq2`,
~29 MB) via `cactus convert ... --lora ... --bits 2`, and runs held-out
evaluation via `scripts/colab/eval_offline_v2.py`.

Local macOS `--dry-run` mode requires Python stdlib only (no torch, peft,
cactus, or GPU required).
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DATASET_DIR = REPO_ROOT / "dataset" / "offline_v2"
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "artifacts" / "offline_v2" / "needle3"
DEFAULT_EVAL_SCRIPT = Path(__file__).resolve().with_name("eval_offline_v2.py")

DEFAULT_NEEDLE_BASE_MODEL = "cactus/needle-3"
DEFAULT_NEEDLE_OUTPUT_NAME = "needle3-onetake-cq2"
MAX_NEEDLE_SEQ_LEN = 1024
ALLOWED_QUANT_BITS: tuple[int, ...] = (2, 4, 8)
EVAL_SOURCE_CACTUS_QUANTIZED = "cactus_quantized"
EVAL_SOURCE_PEFT_PRE_QUANT = "peft_merged_pre_quant"


def build_cactus_convert_command(
    base_model: str,
    output_dir: Path,
    lora_dir: Path,
    bits: int,
) -> list[str]:
    """Build the canonical `cactus convert` CLI command for LoRA merge + quantization."""
    return [
        "cactus",
        "convert",
        base_model,
        str(output_dir),
        "--lora",
        str(lora_dir),
        "--bits",
        str(bits),
    ]


def build_eval_command(
    eval_file: Path,
    predictions_file: Path,
    output_file: Path,
) -> list[str]:
    """Build the `eval_offline_v2.py` CLI invocation for held-out scoring."""
    return [
        sys.executable,
        str(DEFAULT_EVAL_SCRIPT),
        "--eval-file",
        str(eval_file),
        "--predictions",
        str(predictions_file),
        "--output",
        str(output_file),
    ]


def validate_common_lora_hparams(
    *,
    lora_r: int,
    lora_alpha: int,
    lora_dropout: float,
    learning_rate: float,
    epochs: int,
    batch_size: int,
    grad_accum_steps: int,
    max_seq_len: int,
    quant_bits: int,
    max_allowed_seq_len: int = MAX_NEEDLE_SEQ_LEN,
    allowed_bits: tuple[int, ...] = ALLOWED_QUANT_BITS,
    skip_eval: bool = False,
    require_quantized_eval: bool = False,
) -> None:
    """Validate LoRA and quantization hyperparameters before training or dry-run."""
    if lora_r <= 0:
        raise ValueError(f"lora_r must be > 0, got {lora_r}")
    if lora_alpha <= 0:
        raise ValueError(f"lora_alpha must be > 0, got {lora_alpha}")
    if not (0.0 <= lora_dropout < 1.0):
        raise ValueError(f"lora_dropout must be in [0.0, 1.0), got {lora_dropout}")
    if learning_rate <= 0.0:
        raise ValueError(f"learning_rate must be > 0, got {learning_rate}")
    if epochs <= 0:
        raise ValueError(f"epochs must be > 0, got {epochs}")
    if batch_size <= 0:
        raise ValueError(f"batch_size must be > 0, got {batch_size}")
    if grad_accum_steps <= 0:
        raise ValueError(f"grad_accum_steps must be > 0, got {grad_accum_steps}")
    if not (1 <= max_seq_len <= max_allowed_seq_len):
        raise ValueError(
            f"max_seq_len must be in [1, {max_allowed_seq_len}], got {max_seq_len}"
        )
    if quant_bits not in allowed_bits:
        raise ValueError(f"quant_bits must be one of {allowed_bits}, got {quant_bits}")
    if require_quantized_eval and skip_eval:
        raise ValueError("Cannot combine --require-quantized-eval with --skip-eval")


def inspect_jsonl_dataset(
    path: Path,
    *,
    require_exists: bool,
) -> dict[str, Any]:
    """Validate JSONL rows when present and return dataset metadata."""
    if not path.exists():
        if require_exists:
            raise FileNotFoundError(f"Required dataset JSONL not found: {path}")
        return {"path": str(path), "exists": False, "rows": 0}

    row_count = 0
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON ({exc})") from exc
            if not isinstance(record, dict):
                raise ValueError(f"{path}:{line_number}: expected JSON object")
            if "messages" not in record and "target" not in record:
                raise ValueError(
                    f"{path}:{line_number}: row missing `messages` or `target`"
                )
            row_count += 1

    if require_exists and row_count == 0:
        raise ValueError(f"Dataset JSONL contains 0 rows: {path}")

    return {"path": str(path), "exists": True, "rows": row_count}


def add_shared_training_args(
    parser: argparse.ArgumentParser,
    *,
    default_train_file: Path,
    default_eval_file: Path,
    default_output_dir: Path,
    default_output_name: str,
    default_lr: float,
    default_batch_size: int,
    default_grad_accum: int,
    default_bits: int,
) -> None:
    """Register shared CLI options for Offline v2 LoRA trainers."""
    parser.add_argument("--train-file", type=Path, default=default_train_file)
    parser.add_argument("--eval-file", type=Path, default=default_eval_file)
    parser.add_argument("--output-dir", type=Path, default=default_output_dir)
    parser.add_argument("--output-name", type=str, default=default_output_name)
    parser.add_argument("--lora-r", type=int, default=16)
    parser.add_argument("--lora-alpha", type=int, default=32)
    parser.add_argument("--lora-dropout", type=float, default=0.05)
    parser.add_argument("--lr", type=float, default=default_lr)
    parser.add_argument("--epochs", type=int, default=3)
    parser.add_argument("--batch-size", type=int, default=default_batch_size)
    parser.add_argument("--grad-accum", type=int, default=default_grad_accum)
    parser.add_argument("--max-seq-len", type=int, default=MAX_NEEDLE_SEQ_LEN)
    parser.add_argument("--bits", type=int, default=default_bits)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--predictions-file", type=Path, default=None)
    parser.add_argument("--eval-output", type=Path, default=None)
    parser.add_argument("--skip-eval", action="store_true")
    parser.add_argument(
        "--require-quantized-eval",
        action="store_true",
        help="Fail unless held-out evaluation runs against the quantized Cactus bundle.",
    )
    parser.add_argument(
        "--require-data",
        action="store_true",
        help="Fail even during --dry-run if train/eval JSONL files are missing.",
    )
    parser.add_argument(
        "--config-out",
        type=Path,
        default=None,
        help="Optional path to write the resolved training/export plan JSON.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate config, inputs, and planned commands without GPU or third-party packages.",
    )


def run_cactus_convert(cmd: list[str]) -> None:
    """Execute `cactus convert` on Colab / host where Cactus CLI is installed."""
    if shutil.which(cmd[0]) is None:
        raise RuntimeError(
            "`cactus` CLI not found on PATH. Install `cactus-needle[train]` or Cactus CLI in Colab."
        )
    subprocess.run(cmd, check=True)


def load_jsonl_rows(path: Path) -> list[dict[str, Any]]:
    """Load all non-empty JSON objects from a JSONL file."""
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if line.strip():
                rows.append(json.loads(line))
    return rows


def unlink_if_exists(path: Path) -> None:
    """Remove a stale artifact file if present before regenerating."""
    if path.exists():
        path.unlink()


def run_held_out_eval(
    eval_file: Path,
    predictions_file: Path,
    output_file: Path,
) -> dict[str, Any]:
    """Run `eval_offline_v2.py` against real model predictions and return the report."""
    output_file.parent.mkdir(parents=True, exist_ok=True)
    cmd = build_eval_command(eval_file, predictions_file, output_file)
    subprocess.run(cmd, check=True)
    return json.loads(output_file.read_text(encoding="utf-8"))


def try_generate_cactus_predictions(
    *,
    export_dir: Path,
    eval_rows: list[dict[str, Any]],
    output_path: Path,
    dataset_root: Path | None = None,
) -> bool:
    """Attempt quantized bundle inference via Cactus Python bindings when available.

    Returns True only when valid predictions were generated for every eval row.
    """
    try:
        import cactus  # type: ignore
    except ImportError:
        return False

    has_c_api = all(
        hasattr(cactus, attr) for attr in ("cactus_init", "cactus_complete", "cactus_destroy")
    )
    model_cls = getattr(cactus, "CactusModel", None) or getattr(cactus, "Model", None)
    if not has_c_api and model_cls is None:
        return False

    output_path.parent.mkdir(parents=True, exist_ok=True)
    handle_obj = None
    model_obj = None
    try:
        if has_c_api:
            handle_obj = cactus.cactus_init(str(export_dir), 1024)
        else:
            model_obj = model_cls(str(export_dir))

        with output_path.open("w", encoding="utf-8") as out_f:
            for idx, row in enumerate(eval_rows):
                row_id = str(row.get("id", idx))
                prompt_messages = row["messages"][:2]
                image_rel = row.get("image")
                image_path = str((dataset_root or Path(".")) / image_rel) if image_rel else None

                if has_c_api:
                    kwargs: dict[str, Any] = {"max_tokens": 384, "temperature": 0.0}
                    if image_path:
                        kwargs["images"] = [image_path]
                    raw_out = cactus.cactus_complete(
                        handle_obj,
                        json.dumps(prompt_messages),
                        **kwargs,
                    )
                    if isinstance(raw_out, dict):
                        text = str(raw_out.get("response", raw_out.get("text", "")))
                    else:
                        text = str(raw_out)
                else:
                    if hasattr(model_obj, "complete"):
                        text = str(
                            model_obj.complete(
                                prompt_messages,
                                images=[image_path] if image_path else None,
                            )
                        )
                    else:
                        return False
                out_f.write(
                    json.dumps({"id": row_id, "prediction": text.strip()}, ensure_ascii=False)
                    + "\n"
                )
        return output_path.exists() and output_path.stat().st_size > 0
    except Exception:
        unlink_if_exists(output_path)
        return False
    finally:
        if handle_obj is not None and hasattr(cactus, "cactus_destroy"):
            cactus.cactus_destroy(handle_obj)


def try_generate_cactus_cli_predictions(
    *,
    export_dir: Path,
    eval_file: Path,
    output_path: Path,
) -> bool:
    """Attempt quantized bundle inference via Cactus CLI when available on PATH."""
    cactus_bin = shutil.which("cactus")
    if not cactus_bin:
        return False
    for subcommand in ("predict", "eval", "complete"):
        try:
            probe = subprocess.run(
                [cactus_bin, subcommand, "--help"],
                capture_output=True,
                text=True,
                check=False,
            )
            if probe.returncode == 0:
                cmd = [
                    cactus_bin,
                    subcommand,
                    str(export_dir),
                    "--eval-file",
                    str(eval_file),
                    "--output",
                    str(output_path),
                ]
                proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
                if (
                    proc.returncode == 0
                    and output_path.exists()
                    and output_path.stat().st_size > 0
                ):
                    return True
        except Exception:
            continue
    return False


def finalize_held_out_eval(
    *,
    eval_file: Path,
    eval_rows: list[dict[str, Any]],
    export_dir: Path,
    predictions_file: Path,
    eval_output: Path,
    skip_eval: bool,
    require_quantized_eval: bool,
    dataset_root: Path | None = None,
    custom_quantized_predict_fn: Any | None = None,
    peft_fallback_fn: Any | None = None,
) -> dict[str, Any] | None:
    """Generate predictions (preferring quantized Cactus bundle), score, and record `eval_source`."""
    if skip_eval:
        return None

    # Never read stale predictions or eval reports from a previous run.
    unlink_if_exists(predictions_file)
    unlink_if_exists(eval_output)

    quantized_ok = False
    if custom_quantized_predict_fn is not None:
        try:
            quantized_ok = bool(custom_quantized_predict_fn())
        except Exception:
            quantized_ok = False
    if not quantized_ok:
        quantized_ok = try_generate_cactus_predictions(
            export_dir=export_dir,
            eval_rows=eval_rows,
            output_path=predictions_file,
            dataset_root=dataset_root,
        )
    if not quantized_ok:
        quantized_ok = try_generate_cactus_cli_predictions(
            export_dir=export_dir,
            eval_file=eval_file,
            output_path=predictions_file,
        )

    if quantized_ok and predictions_file.exists() and predictions_file.stat().st_size > 0:
        eval_source = EVAL_SOURCE_CACTUS_QUANTIZED
    else:
        unlink_if_exists(predictions_file)
        if require_quantized_eval:
            raise RuntimeError(
                "--require-quantized-eval is set, but Cactus quantized inference is unavailable "
                f"or failed to produce predictions for {export_dir}."
            )
        if peft_fallback_fn is None:
            raise RuntimeError(
                "Quantized Cactus inference failed to produce held-out predictions and no "
                "PEFT fallback generator is available. Pass --skip-eval to skip evaluation."
            )
        print(
            "Warning: Cactus quantized runtime inference unavailable; evaluating pre-quantization "
            "PEFT weights (`eval_source='peft_merged_pre_quant'`).",
            file=sys.stderr,
        )
        peft_fallback_fn()
        eval_source = EVAL_SOURCE_PEFT_PRE_QUANT

    report = run_held_out_eval(eval_file, predictions_file, eval_output)
    report["eval_source"] = eval_source
    eval_output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def serialize_config(cfg: Any) -> dict[str, Any]:
    """Convert a dataclass config containing Path objects into JSON-safe dict."""
    raw = asdict(cfg)
    return {
        key: str(val) if isinstance(val, Path) else list(val) if isinstance(val, tuple) else val
        for key, val in raw.items()
    }


@dataclass
class Needle3TrainConfig:
    base_model: str = DEFAULT_NEEDLE_BASE_MODEL
    train_file: Path = DEFAULT_DATASET_DIR / "train_needle.jsonl"
    eval_file: Path = DEFAULT_DATASET_DIR / "eval_needle.jsonl"
    output_dir: Path = DEFAULT_OUTPUT_ROOT
    output_name: str = DEFAULT_NEEDLE_OUTPUT_NAME
    lora_r: int = 16
    lora_alpha: int = 32
    lora_dropout: float = 0.05
    learning_rate: float = 2e-4
    epochs: int = 3
    batch_size: int = 4
    grad_accum_steps: int = 4
    max_seq_len: int = MAX_NEEDLE_SEQ_LEN
    quant_bits: int = 2
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
        return self.predictions_file or (self.output_dir / "eval_needle_predictions.jsonl")

    @property
    def resolved_eval_output(self) -> Path:
        return self.eval_output or (self.output_dir / "eval_needle_report.json")


def validate_needle_config(cfg: Needle3TrainConfig) -> None:
    """Validate Needle 3 LoRA & CQ2 export configuration."""
    if not cfg.base_model.strip():
        raise ValueError("base_model must be non-empty")
    if not cfg.output_name.strip():
        raise ValueError("output_name must be non-empty")
    if not cfg.target_modules:
        raise ValueError("target_modules must be non-empty")
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
        max_allowed_seq_len=MAX_NEEDLE_SEQ_LEN,
        allowed_bits=ALLOWED_QUANT_BITS,
        skip_eval=cfg.skip_eval,
        require_quantized_eval=cfg.require_quantized_eval,
    )


def build_needle_plan(
    cfg: Needle3TrainConfig,
    *,
    require_data: bool = False,
) -> dict[str, Any]:
    """Validate config/data and construct the Needle 3 training/export/eval plan."""
    validate_needle_config(cfg)
    train_status = inspect_jsonl_dataset(cfg.train_file, require_exists=require_data)
    eval_status = inspect_jsonl_dataset(cfg.eval_file, require_exists=require_data)
    convert_cmd = build_cactus_convert_command(
        base_model=cfg.base_model,
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
        else ("quantized_required" if cfg.require_quantized_eval else "quantized_preferred_with_peft_fallback")
    )
    return {
        "trainer": "needle3_lora",
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
        "eval_command": eval_cmd,
    }


def _generate_needle_predictions(
    *,
    model: Any,
    tokenizer: Any,
    eval_rows: list[dict[str, Any]],
    output_path: Path,
    max_seq_len: int,
) -> Path:
    import torch  # type: ignore

    output_path.parent.mkdir(parents=True, exist_ok=True)
    model.eval()
    device = next(model.parameters()).device

    with output_path.open("w", encoding="utf-8") as handle:
        for idx, row in enumerate(eval_rows):
            row_id = str(row.get("id", idx))
            messages = row["messages"][:2]
            if hasattr(tokenizer, "apply_chat_template"):
                prompt = tokenizer.apply_chat_template(
                    messages,
                    tokenize=False,
                    add_generation_prompt=True,
                )
            else:
                prompt = "\n".join(f"{m['role']}: {m['content']}" for m in messages) + "\nassistant:"

            inputs = tokenizer(
                prompt,
                return_tensors="pt",
                truncation=True,
                max_length=max_seq_len,
            ).to(device)
            with torch.no_grad():
                generated = model.generate(
                    **inputs,
                    max_new_tokens=384,
                    do_sample=False,
                    pad_token_id=tokenizer.eos_token_id,
                )
            prompt_len = inputs["input_ids"].shape[-1]
            decoded = tokenizer.decode(generated[0][prompt_len:], skip_special_tokens=True).strip()
            handle.write(json.dumps({"id": row_id, "prediction": decoded}, ensure_ascii=False) + "\n")
    return output_path


def run_needle_training(cfg: Needle3TrainConfig) -> dict[str, Any]:
    """Execute Needle 3 LoRA fine-tuning, Cactus CQ2 export, and held-out eval on Colab GPU."""
    plan = build_needle_plan(cfg, require_data=True)
    cfg.output_dir.mkdir(parents=True, exist_ok=True)
    cfg.lora_dir.mkdir(parents=True, exist_ok=True)
    eval_rows = load_jsonl_rows(cfg.eval_file)

    # Lazy imports so local macOS `--dry-run` works with zero third-party packages.
    try:
        import cactus.needle.train as cactus_needle_train  # type: ignore
    except ImportError:
        cactus_needle_train = None

    if cactus_needle_train is not None and hasattr(cactus_needle_train, "run_lora_sft"):
        cactus_needle_train.run_lora_sft(
            base_model=cfg.base_model,
            train_file=str(cfg.train_file),
            eval_file=str(cfg.eval_file),
            output_dir=str(cfg.lora_dir),
            lora_r=cfg.lora_r,
            lora_alpha=cfg.lora_alpha,
            lora_dropout=cfg.lora_dropout,
            learning_rate=cfg.learning_rate,
            epochs=cfg.epochs,
            batch_size=cfg.batch_size,
            grad_accum_steps=cfg.grad_accum_steps,
            max_seq_len=cfg.max_seq_len,
            seed=cfg.seed,
        )
        run_cactus_convert(plan["cactus_convert_command"])

        def _needle_pkg_predict() -> bool:
            predict_fn = (
                getattr(cactus_needle_train, "generate_predictions", None)
                or getattr(cactus_needle_train, "predict", None)
                or getattr(cactus_needle_train, "run_eval", None)
            )
            if predict_fn is None:
                return False
            try:
                predict_fn(
                    model_dir=str(cfg.export_dir),
                    eval_file=str(cfg.eval_file),
                    output_file=str(cfg.resolved_predictions_file),
                )
            except Exception:
                return False
            return (
                cfg.resolved_predictions_file.exists()
                and cfg.resolved_predictions_file.stat().st_size > 0
            )

        eval_report = finalize_held_out_eval(
            eval_file=cfg.eval_file,
            eval_rows=eval_rows,
            export_dir=cfg.export_dir,
            predictions_file=cfg.resolved_predictions_file,
            eval_output=cfg.resolved_eval_output,
            skip_eval=cfg.skip_eval,
            require_quantized_eval=cfg.require_quantized_eval,
            custom_quantized_predict_fn=_needle_pkg_predict,
            peft_fallback_fn=None,
        )
        return {"plan": plan, "eval_report": eval_report}

    import torch  # type: ignore
    from datasets import Dataset  # type: ignore
    from peft import LoraConfig, get_peft_model  # type: ignore
    from transformers import (  # type: ignore
        AutoModelForCausalLM,
        AutoTokenizer,
        DataCollatorForLanguageModeling,
        Trainer,
        TrainingArguments,
    )

    torch.manual_seed(cfg.seed)
    tokenizer = AutoTokenizer.from_pretrained(cfg.base_model, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    dtype = torch.bfloat16 if torch.cuda.is_available() and torch.cuda.is_bf16_supported() else torch.float16
    model = AutoModelForCausalLM.from_pretrained(
        cfg.base_model,
        torch_dtype=dtype if torch.cuda.is_available() else torch.float32,
        trust_remote_code=True,
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

    train_rows = load_jsonl_rows(cfg.train_file)

    def format_example(row: dict[str, Any]) -> dict[str, Any]:
        messages = row["messages"]
        if hasattr(tokenizer, "apply_chat_template"):
            text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=False)
        else:
            text = "\n".join(f"{m['role']}: {m['content']}" for m in messages)
        encoded = tokenizer(
            text,
            truncation=True,
            max_length=cfg.max_seq_len,
            padding="max_length",
        )
        encoded["labels"] = encoded["input_ids"].copy()
        return encoded

    train_ds = Dataset.from_list([format_example(r) for r in train_rows])
    eval_ds = Dataset.from_list([format_example(r) for r in eval_rows])

    training_args = TrainingArguments(
        output_dir=str(cfg.output_dir / "checkpoints"),
        num_train_epochs=cfg.epochs,
        per_device_train_batch_size=cfg.batch_size,
        per_device_eval_batch_size=cfg.batch_size,
        gradient_accumulation_steps=cfg.grad_accum_steps,
        learning_rate=cfg.learning_rate,
        bf16=bool(torch.cuda.is_available() and torch.cuda.is_bf16_supported()),
        fp16=bool(torch.cuda.is_available() and not torch.cuda.is_bf16_supported()),
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
        train_dataset=train_ds,
        eval_dataset=eval_ds,
        data_collator=DataCollatorForLanguageModeling(tokenizer=tokenizer, mlm=False),
    )
    trainer.train()
    model.save_pretrained(str(cfg.lora_dir))
    tokenizer.save_pretrained(str(cfg.lora_dir))

    run_cactus_convert(plan["cactus_convert_command"])

    eval_report = finalize_held_out_eval(
        eval_file=cfg.eval_file,
        eval_rows=eval_rows,
        export_dir=cfg.export_dir,
        predictions_file=cfg.resolved_predictions_file,
        eval_output=cfg.resolved_eval_output,
        skip_eval=cfg.skip_eval,
        require_quantized_eval=cfg.require_quantized_eval,
        peft_fallback_fn=lambda: _generate_needle_predictions(
            model=model,
            tokenizer=tokenizer,
            eval_rows=eval_rows,
            output_path=cfg.resolved_predictions_file,
            max_seq_len=cfg.max_seq_len,
        ),
    )

    return {"plan": plan, "eval_report": eval_report}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-model", type=str, default=DEFAULT_NEEDLE_BASE_MODEL)
    parser.add_argument(
        "--target-modules",
        type=str,
        default="q_proj,k_proj,v_proj,o_proj",
        help="Comma-separated LoRA target module names.",
    )
    add_shared_training_args(
        parser,
        default_train_file=DEFAULT_DATASET_DIR / "train_needle.jsonl",
        default_eval_file=DEFAULT_DATASET_DIR / "eval_needle.jsonl",
        default_output_dir=DEFAULT_OUTPUT_ROOT,
        default_output_name=DEFAULT_NEEDLE_OUTPUT_NAME,
        default_lr=2e-4,
        default_batch_size=4,
        default_grad_accum=4,
        default_bits=2,
    )
    return parser.parse_args(argv)


def config_from_args(args: argparse.Namespace) -> Needle3TrainConfig:
    modules = tuple(m.strip() for m in args.target_modules.split(",") if m.strip())
    return Needle3TrainConfig(
        base_model=args.base_model,
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
            plan = build_needle_plan(cfg, require_data=args.require_data)
            if args.config_out:
                args.config_out.parent.mkdir(parents=True, exist_ok=True)
                args.config_out.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
            print(json.dumps(plan, indent=2))
            return 0
        result = run_needle_training(cfg)
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
