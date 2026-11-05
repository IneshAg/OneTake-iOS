#!/usr/bin/env python3
"""
OneTake Script & Notice Parser LoRA Fine-Tuner
=============================================
Fine-tunes a lightweight LLM (Qwen2.5-1.5B-Instruct) using 4-bit QLoRA with PEFT
on local NVIDIA GeForce RTX 4050 Laptop GPU (6GB VRAM).

Trains on:
  - dataset/parsing_dataset_train.jsonl (156 samples)
Outputs LoRA adapter to:
  - models/onetake-parser-lora/
"""

import os
import sys
import json
import argparse
from pathlib import Path

import torch
from torch.utils.data import Dataset
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    BitsAndBytesConfig,
    TrainingArguments,
    Trainer,
    DataCollatorForSeq2Seq
)
from peft import (
    prepare_model_for_kbit_training,
    LoraConfig,
    get_peft_model
)

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
TRAIN_FILE = DATASET_DIR / "parsing_dataset_train.jsonl"
DEFAULT_OUTPUT_DIR = BASE_DIR / "models" / "onetake-parser-lora"

DEFAULT_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"

class InstructionDataset(Dataset):
    def __init__(self, jsonl_path: Path, tokenizer, max_length: int = 1024):
        self.samples = []
        if not jsonl_path.exists():
            print(f"[!] Warning: File {jsonl_path} does not exist.")
            return

        with open(jsonl_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                data = json.loads(line)
                messages = data.get("messages", [])
                if len(messages) >= 3:
                    self.samples.append(messages)

        print(f"[*] Loaded {len(self.samples)} samples from {jsonl_path.name}")
        self.tokenizer = tokenizer
        self.max_length = max_length

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        messages = self.samples[idx]
        
        prompt_msgs = messages[:-1]
        prompt_str = self.tokenizer.apply_chat_template(
            prompt_msgs,
            tokenize=False,
            add_generation_prompt=True
        )
        full_str = self.tokenizer.apply_chat_template(
            messages,
            tokenize=False,
            add_generation_prompt=False
        )

        prompt_ids = self.tokenizer.encode(prompt_str, add_special_tokens=False)
        full_ids = self.tokenizer.encode(full_str, add_special_tokens=False)

        if len(full_ids) > self.max_length:
            full_ids = full_ids[:self.max_length]

        input_ids = torch.tensor(full_ids, dtype=torch.long)
        attention_mask = torch.ones_like(input_ids)
        labels = input_ids.clone()

        # Mask prompt tokens with -100 so loss is computed solely on the assistant JSON output
        prompt_len = min(len(prompt_ids), len(input_ids))
        labels[:prompt_len] = -100

        return {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
            "labels": labels
        }

def train(
    model_name: str = DEFAULT_MODEL,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    epochs: int = 1,
    batch_size: int = 2,
    grad_accum: int = 4,
    lr: float = 2e-4,
    max_length: int = 1024
):
    print("=" * 60)
    print(" OneTake LoRA Fine-Tuning Pipeline (RTX 4050)")
    print("=" * 60)
    print(f"CUDA Available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        print(f"GPU: {torch.cuda.get_device_name(0)}")
        print(f"Total VRAM: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n[*] Loading Tokenizer: {model_name}")
    tokenizer = AutoTokenizer.from_pretrained(model_name, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    print(f"[*] Preparing 4-bit QLoRA configuration...")
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_use_double_quant=True
    )

    print(f"[*] Loading Base Model in 4-bit: {model_name}")
    model = AutoModelForCausalLM.from_pretrained(
        model_name,
        quantization_config=bnb_config,
        device_map="auto",
        torch_dtype=torch.float16,
        trust_remote_code=True
    )
    model = prepare_model_for_kbit_training(model)

    print("[*] Configuring LoRA Adapter...")
    lora_config = LoraConfig(
        r=16,
        lora_alpha=32,
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"],
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM"
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    print("\n[*] Loading Training Dataset...")
    train_dataset = InstructionDataset(TRAIN_FILE, tokenizer, max_length=max_length)

    data_collator = DataCollatorForSeq2Seq(
        tokenizer=tokenizer,
        padding=True,
        pad_to_multiple_of=8,
        label_pad_token_id=-100
    )

    training_args = TrainingArguments(
        output_dir=str(output_dir),
        num_train_epochs=epochs,
        per_device_train_batch_size=batch_size,
        gradient_accumulation_steps=grad_accum,
        learning_rate=lr,
        fp16=True,
        logging_steps=5,
        save_strategy="no",
        eval_strategy="no",
        report_to="none",
        optim="paged_adamw_8bit"
    )

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_dataset,
        data_collator=data_collator
    )

    print("\n[*] Starting Training Run...")
    train_result = trainer.train()
    print(f"[+] Training completed. Final Loss: {train_result.training_loss:.4f}")

    print(f"\n[*] Saving fine-tuned LoRA weights & tokenizer to {output_dir}...")
    model.save_pretrained(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    print("[+] Model fine-tuning successfully saved to disk!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="OneTake LoRA Fine-Tuner")
    parser.add_argument("--epochs", type=int, default=1, help="Number of training epochs")
    parser.add_argument("--batch-size", type=int, default=2, help="Per-device batch size")
    parser.add_argument("--lr", type=float, default=2e-4, help="Learning rate")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Base model identifier")
    parser.add_argument("--output-dir", type=str, default=str(DEFAULT_OUTPUT_DIR), help="Output directory")

    args = parser.parse_args()
    train(
        model_name=args.model,
        output_dir=Path(args.output_dir),
        epochs=args.epochs,
        batch_size=args.batch_size,
        lr=args.lr
    )
