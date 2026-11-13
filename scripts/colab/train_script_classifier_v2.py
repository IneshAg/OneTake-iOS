#!/usr/bin/env python3
"""
OneTake Contextual Script Element Classifier v2 Trainer (Colab + Local Dry-Run)
==============================================================================
Generates 25,000 contextual screenplay, stage-play, commercial, and multi-role
casting packet lines with layout geometry and neighbor context, then trains a
lightweight (<5 MB) hybrid text + tabular Core ML model:

Inputs:
  - text_tokens:     int32[1, 24]   FNV-1a hashed word & char-trigram token IDs
  - layout_features: float32[1, 13] [left_x, width_ratio, blank_before,
                                     blank_after, uppercase_ratio,
                                     line_length_norm, one_hot(prev_class, 7)]

Classes (matching Swift `ScriptElementClass`):
  0: scene_heading
  1: character_cue
  2: dialogue
  3: parenthetical
  4: action
  5: metadata

Usage:
  # Local smoke test (stdlib only, no torch/coremltools required):
  python3 scripts/colab/train_script_classifier_v2.py --dry-run

  # Full Colab training & Core ML export:
  python3 scripts/colab/train_script_classifier_v2.py --output OneTake/Core/Models/ScriptElementClassifierV2.mlpackage
"""

from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import dataclass, asdict
import json
from pathlib import Path
import random
import re
import sys
from typing import Iterable, List, Optional, Sequence, Tuple

CLASSES: Tuple[str, ...] = (
    "scene_heading",
    "character_cue",
    "dialogue",
    "parenthetical",
    "action",
    "metadata",
)

PREV_CLASSES: Tuple[str, ...] = ("none",) + CLASSES

VOCAB_SIZE = 4096
MAX_TOKENS = 24
NUM_LAYOUT_FEATURES = 6 + len(PREV_CLASSES)  # 13
MAX_MODEL_BYTES = 5 * 1024 * 1024  # 5 MB hard budget


def fnv1a_32(text: str) -> int:
    """Deterministic 32-bit FNV-1a hash matching CoreMLScriptParserRunner.swift."""
    h = 0x811C9DC5
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def tokenize_text(text: str, max_tokens: int = MAX_TOKENS, vocab_size: int = VOCAB_SIZE) -> List[int]:
    """
    Deterministic word + structural + character-trigram hashed tokenizer.
    Token 0 is reserved for padding; active tokens map to [1, vocab_size - 1].
    Must stay bit-identical to `CoreMLScriptParserRunner.tokenizeForV2(_:)`.
    """
    cleaned = text.strip().lower()
    if not cleaned:
        return [0] * max_tokens

    tokens: List[str] = []
    words = re.findall(r"[a-z0-9']+|[():.\-!?/]", cleaned)
    for word in words[:12]:
        tokens.append(f"w:{word}")
        if len(word) >= 3 and word.isalnum():
            for idx in range(len(word) - 2):
                tokens.append(f"c:{word[idx:idx + 3]}")

    # Structural hints help distinguish cues/parentheticals/headers with tiny vocab.
    if text.strip().endswith((".", "!")):
        tokens.append("s:end_period_bang")
    if text.strip().endswith("?"):
        tokens.append("s:end_question")
    if text.strip().endswith(":"):
        tokens.append("s:end_colon")
    if text.strip().startswith("(") and text.strip().endswith(")"):
        tokens.append("s:parens")

    ids = [((fnv1a_32(tok) % (vocab_size - 1)) + 1) for tok in tokens[:max_tokens]]
    if len(ids) < max_tokens:
        ids.extend([0] * (max_tokens - len(ids)))
    return ids


def compute_uppercase_ratio(text: str) -> float:
    letters = [ch for ch in text if ch.isalpha()]
    if not letters:
        return 0.0
    upper_count = sum(1 for ch in letters if ch.isupper())
    return upper_count / float(len(letters))


@dataclass(frozen=True)
class ContextualScriptSample:
    text: str
    label: str
    archetype: str
    left_x: float
    width_ratio: float
    blank_before: int
    blank_after: int
    uppercase_ratio: float
    line_length: int
    prev_class: str

    def layout_vector(self) -> List[float]:
        prev_one_hot = [1.0 if self.prev_class == cls else 0.0 for cls in PREV_CLASSES]
        return [
            max(0.0, min(1.0, self.left_x)),
            max(0.0, min(1.0, self.width_ratio)),
            float(1 if self.blank_before else 0),
            float(1 if self.blank_after else 0),
            max(0.0, min(1.0, self.uppercase_ratio)),
            min(self.line_length, 120) / 120.0,
        ] + prev_one_hot

    def token_vector(self) -> List[int]:
        return tokenize_text(self.text)


# ---------------------------------------------------------------------------
# Synthetic Script Corpus Pools
# ---------------------------------------------------------------------------

CHARACTERS = [
    "MAYA", "ARJUN", "NOOR", "MARYAM", "NADIA", "SOSAN", "DANNY", "SANDY",
    "DETECTIVE MILLER", "DR. RAO", "SARAH", "CLAUDIUS", "HAMLET", "OPHELIA",
    "HORATIO", "OFFICER DAVIS", "NURSE KLINE", "ANNCR", "MAN", "WOMAN",
    "ROXIE", "VELMA", "BILLY", "KAT", "OSCAR", "TOM", "MAGGIE", "ALEX",
]

LOCATIONS = [
    "APARTMENT", "COFFEE SHOP", "STREET CORNER", "HOSPITAL ROOM", "DINER",
    "KITCHEN", "SUBWAY PLATFORM", "POLICE STATION", "ROOFTOP", "COURTYARD",
    "HOTEL LOBBY", "CAR", "PARKING GARAGE", "STAGE", "OFFICE", "ALLEYWAY",
]

TIMES = ["DAY", "NIGHT", "CONTINUOUS", "MORNING", "EVENING", "LATER", "DUSK"]

ACTION_TEMPLATES = [
    "{name} picks up the phone.",
    "{name} glances out the rain-streaked window.",
    "{name} sets the keys down on the counter.",
    "{name} steps back, startled by the noise.",
    "{name} checks the watch on {pronoun} wrist.",
    "{name} walks across the room and closes the door.",
    "{name} hesitates before opening the envelope.",
    "{name} looks up from the folded script pages.",
    "Silence hangs heavily in the small room.",
    "A distant siren wails outside.",
    "The door creaks open slowly.",
    "Rain taps steadily against the glass.",
    "Both of them stare at the unanswered phone.",
    "The lights flicker once before stabilizing.",
]

DIALOGUE_LINES = [
    "Are you still awake?",
    "I didn't think you'd come.",
    "Where were you last night?",
    "We need to leave before anyone checks the lobby.",
    "Look at me when I'm talking to you.",
    "I told you everything I know.",
    "Scene 2 was better, honestly.",
    "Int. was the word she used in her notes.",
    "Wait—did you hear that?",
    "Don't touch that file.",
    "Nobody else knows we're here.",
    "Why did you wait until midnight to call?",
    "It's not what you think.",
    "Please, just listen for thirty seconds.",
    "The morning commute just got an upgrade.",
    "Ask your doctor if this is right for you.",
    "I can't talk to her right now.",
    "Tell their lawyers I'll call them on Monday.",
    "Yes, I remember every single word.",
    "No. Not tonight.",
]

PARENTHETICALS = [
    "(whispering)",
    "(beat)",
    "(hesitates)",
    "(softly)",
    "(to Maya)",
    "(under her breath)",
    "(into phone)",
    "(laughing)",
    "(coldly)",
    "(overlapping)",
    "(sarcastic)",
    "(sighs)",
]

CUE_EXTENSIONS = ["", "", "", " (CONT'D)", " (V.O.)", " (O.S.)"]

WATERMARKS_AND_METADATA = [
    "CONFIDENTIAL",
    "DO NOT DISTRIBUTE",
    "PROPERTY OF CASTING OFFICE",
    "AUDITION SIDES ONLY",
    "REVISED SHOOTING DRAFT",
    "REQUIREMENT: MALE (30-55 YEARS)",
    "SUBMISSION DEADLINE: FRIDAY 5 PM",
    "CLIENT: ACME MOTORS",
    "CAMPAIGN: SPRING LAUNCH",
    "DIRECTOR NOTE: Keep the pacing tight and grounded.",
    "SLATE INSTRUCTION: Name, pronouns, and role before scene.",
]


def _make_sample(
    rng: random.Random,
    text: str,
    label: str,
    archetype: str,
    left_x: float,
    width_ratio: float,
    blank_before: int,
    blank_after: int,
    prev_class: str,
) -> ContextualScriptSample:
    jitter_x = max(0.02, min(0.92, left_x + rng.uniform(-0.02, 0.02)))
    jitter_w = max(0.05, min(0.95 - jitter_x, width_ratio + rng.uniform(-0.03, 0.03)))
    return ContextualScriptSample(
        text=text,
        label=label,
        archetype=archetype,
        left_x=round(jitter_x, 4),
        width_ratio=round(jitter_w, 4),
        blank_before=blank_before,
        blank_after=blank_after,
        uppercase_ratio=round(compute_uppercase_ratio(text), 4),
        line_length=len(text),
        prev_class=prev_class,
    )


def _generate_screenplay_block(rng: random.Random) -> List[ContextualScriptSample]:
    samples: List[ContextualScriptSample] = []
    prev = "none"

    prefix = rng.choice(["INT.", "EXT.", "INT./EXT."])
    loc = rng.choice(LOCATIONS)
    tod = rng.choice(TIMES)
    heading = f"{prefix} {loc} - {tod}"
    samples.append(_make_sample(rng, heading, "scene_heading", "screenplay", 0.15, 0.42, 1, 1, prev))
    prev = "scene_heading"

    if rng.random() < 0.35:
        page_num = rng.choice([f"PAGE {rng.randint(1, 45)}", f"{rng.randint(2, 60)}.", f"P. {rng.randint(1, 30)}"])
        samples.append(_make_sample(rng, page_num, "metadata", "screenplay", 0.84, 0.09, 1, 1, prev))
        prev = "metadata"

    # Left-aligned action that starts with an uppercase character name (critical disambiguation case)
    if rng.random() < 0.75:
        actor = rng.choice(CHARACTERS)
        act_text = rng.choice(ACTION_TEMPLATES).format(name=actor, pronoun=rng.choice(["her", "his", "their"]))
        samples.append(_make_sample(rng, act_text, "action", "screenplay", 0.15, 0.62, 1, 1, prev))
        prev = "action"

    turns = rng.randint(2, 4)
    for _ in range(turns):
        cue_base = rng.choice(CHARACTERS)
        if rng.random() < 0.18:
            cue_base = cue_base.title()  # mixed-case indented cue
        cue = f"{cue_base}{rng.choice(CUE_EXTENSIONS)}"
        samples.append(_make_sample(rng, cue, "character_cue", "screenplay", 0.42, 0.15, 1, 0, prev))
        prev = "character_cue"

        if rng.random() < 0.35:
            paren = rng.choice(PARENTHETICALS)
            samples.append(_make_sample(rng, paren, "parenthetical", "screenplay", 0.34, 0.18, 0, 0, prev))
            prev = "parenthetical"

        num_lines = rng.randint(1, 3)
        for idx in range(num_lines):
            d_line = rng.choice(DIALOGUE_LINES)
            is_last = idx == num_lines - 1
            samples.append(
                _make_sample(
                    rng,
                    d_line,
                    "dialogue",
                    "screenplay",
                    0.28,
                    min(0.45, max(0.14, len(d_line) / 95.0)),
                    0,
                    1 if is_last else 0,
                    prev,
                )
            )
            prev = "dialogue"

        if rng.random() < 0.25:
            actor = rng.choice(CHARACTERS)
            beat = rng.choice(ACTION_TEMPLATES).format(name=actor, pronoun="her")
            samples.append(_make_sample(rng, beat, "action", "screenplay", 0.15, 0.58, 1, 1, prev))
            prev = "action"

    if rng.random() < 0.20:
        samples.append(_make_sample(rng, rng.choice(WATERMARKS_AND_METADATA[:5]), "metadata", "screenplay", 0.15, 0.30, 1, 1, prev))

    return samples


def _generate_stage_play_block(rng: random.Random) -> List[ContextualScriptSample]:
    samples: List[ContextualScriptSample] = []
    prev = "none"

    act_heading = rng.choice([
        f"ACT {rng.choice(['I', 'II', 'III'])}, SCENE {rng.randint(1, 6)}",
        f"SCENE {rng.randint(1, 12)}: THE PARLOR",
        f"SC. {rng.randint(1, 15)} - COURTYARD",
    ])
    samples.append(_make_sample(rng, act_heading, "scene_heading", "stage_play", 0.12, 0.35, 1, 1, prev))
    prev = "scene_heading"

    if rng.random() < 0.6:
        sd = f"({rng.choice(['Lights up on a sparse stage.', 'Enter MAYA and ARJUN from stage left.', 'A heavy silence.'])})"
        samples.append(_make_sample(rng, sd, "parenthetical", "stage_play", 0.18, 0.50, 1, 1, prev))
        prev = "parenthetical"

    for _ in range(rng.randint(2, 3)):
        speaker = rng.choice(CHARACTERS).split()[0]
        style = rng.choice(["colon", "period", "bracket", "indented"])
        if style == "colon":
            line = f"{speaker}: {rng.choice(DIALOGUE_LINES)}"
            samples.append(_make_sample(rng, line, "dialogue", "stage_play", 0.12, 0.65, 1, 0, prev))
            prev = "dialogue"
        elif style == "period":
            line = f"{speaker}. {rng.choice(DIALOGUE_LINES)}"
            samples.append(_make_sample(rng, line, "dialogue", "stage_play", 0.12, 0.65, 1, 0, prev))
            prev = "dialogue"
        elif style == "bracket":
            samples.append(_make_sample(rng, f"[{speaker}]", "character_cue", "stage_play", 0.35, 0.12, 1, 0, prev))
            prev = "character_cue"
            samples.append(_make_sample(rng, rng.choice(DIALOGUE_LINES), "dialogue", "stage_play", 0.18, 0.50, 0, 1, prev))
            prev = "dialogue"
        else:
            samples.append(_make_sample(rng, speaker, "character_cue", "stage_play", 0.38, 0.11, 1, 0, prev))
            prev = "character_cue"
            if rng.random() < 0.4:
                samples.append(_make_sample(rng, rng.choice(PARENTHETICALS), "parenthetical", "stage_play", 0.30, 0.16, 0, 0, prev))
                prev = "parenthetical"
            samples.append(_make_sample(rng, rng.choice(DIALOGUE_LINES), "dialogue", "stage_play", 0.18, 0.52, 0, 1, prev))
            prev = "dialogue"

    return samples


def _generate_commercial_block(rng: random.Random) -> List[ContextualScriptSample]:
    samples: List[ContextualScriptSample] = []
    prev = "none"

    samples.append(_make_sample(rng, rng.choice(["COMMERCIAL COPY — 30 SEC", "TV SPOT — :15", "RADIO SCRIPT — :30"]), "metadata", "commercial", 0.10, 0.40, 1, 0, prev))
    prev = "metadata"
    samples.append(_make_sample(rng, rng.choice(["CLIENT: ACME MOTORS", "PRODUCT: HORIZON APP"]), "metadata", "commercial", 0.10, 0.34, 0, 1, prev))
    prev = "metadata"

    for _ in range(rng.randint(2, 3)):
        vis = rng.choice([
            "VIDEO: Hero shot of car cruising along coastal highway.",
            "VISUAL: Close-up on parent pouring morning coffee.",
            "SUPER: Offer ends Friday. Terms apply.",
            "SFX: Gentle chime followed by upbeat acoustic guitar.",
        ])
        samples.append(_make_sample(rng, vis, "action" if vis.startswith(("VIDEO:", "VISUAL:")) else "metadata", "commercial", 0.08, 0.38, 1, 0, prev))
        prev = "action" if vis.startswith(("VIDEO:", "VISUAL:")) else "metadata"

        speaker = rng.choice(["ANNCR", "WOMAN", "MAN", "V.O."])
        d_line = rng.choice(DIALOGUE_LINES)
        samples.append(_make_sample(rng, f"AUDIO: {speaker}: {d_line}", "dialogue", "commercial", 0.50, 0.42, 0, 1, prev))
        prev = "dialogue"

    return samples


def _generate_multi_role_packet_block(rng: random.Random) -> List[ContextualScriptSample]:
    samples: List[ContextualScriptSample] = []
    prev = "none"

    packet_headers = [
        "CASTING SIDES",
        "HOW TO USE THESE SIDES",
        "THE CHARACTERS IN THIS DOCUMENT",
        f"NOOR — Page {rng.randint(2, 6)}",
        f"MARYAM — Page {rng.randint(2, 6)}",
    ]
    for hdr in rng.sample(packet_headers, k=2):
        samples.append(_make_sample(rng, hdr, "metadata", "multi_role", 0.10, 0.35, 1, 0, prev))
        prev = "metadata"

    role = rng.choice(["NOOR", "MARYAM", "NADIA", "SOSAN", "MAYA", "ARJUN"])
    samples.append(_make_sample(rng, f"{role} · She/her · Early 30s", "metadata", "multi_role", 0.10, 0.42, 1, 0, prev))
    prev = "metadata"

    side_label = rng.choice([
        f"THE SIDE — {role.title()}'s Confession (Act II, Scene 4)",
        f"SIDE {rng.choice(['A', 'B'])} — The Phone Call (Act I, Scene 5)",
        "START",
    ])
    samples.append(_make_sample(rng, side_label, "scene_heading", "multi_role", 0.10, 0.48, 1, 0, prev))
    prev = "scene_heading"

    samples.append(_make_sample(rng, "Setting: Hotel lobby, late evening.", "action", "multi_role", 0.10, 0.40, 0, 1, prev))
    prev = "action"

    if rng.random() < 0.5:
        samples.append(_make_sample(rng, "[speaking on phone]", "parenthetical", "multi_role", 0.14, 0.25, 0, 0, prev))
        prev = "parenthetical"

    for idx in range(rng.randint(2, 4)):
        d_line = rng.choice(DIALOGUE_LINES)
        samples.append(_make_sample(rng, d_line, "dialogue", "multi_role", 0.12, 0.65, 0, 1 if idx == 3 else 0, prev))
        prev = "dialogue"

    # Also include adversarial notice bullets labeled metadata
    if rng.random() < 0.35:
        samples.append(_make_sample(rng, rng.choice(WATERMARKS_AND_METADATA), "metadata", "multi_role", 0.10, 0.45, 1, 1, prev))

    return samples


def generate_dataset(count: int = 25000, seed: int = 20261113) -> List[ContextualScriptSample]:
    rng = random.Random(seed)
    generators = (
        (_generate_screenplay_block, 0.45),
        (_generate_stage_play_block, 0.20),
        (_generate_commercial_block, 0.15),
        (_generate_multi_role_packet_block, 0.20),
    )
    funcs = [g[0] for g in generators]
    weights = [g[1] for g in generators]

    dataset: List[ContextualScriptSample] = []
    while len(dataset) < count:
        gen = rng.choices(funcs, weights=weights, k=1)[0]
        dataset.extend(gen(rng))
    return dataset[:count]


def validate_dataset(samples: Sequence[ContextualScriptSample]) -> dict:
    class_counts = Counter(s.label for s in samples)
    archetype_counts = Counter(s.archetype for s in samples)

    missing_classes = [cls for cls in CLASSES if class_counts[cls] == 0]
    if missing_classes:
        raise ValueError(f"Generated dataset missing classes: {missing_classes}")

    for s in samples[:2000]:
        vec = s.layout_vector()
        toks = s.token_vector()
        if len(vec) != NUM_LAYOUT_FEATURES:
            raise ValueError(f"Expected {NUM_LAYOUT_FEATURES} layout features, got {len(vec)}")
        if len(toks) != MAX_TOKENS:
            raise ValueError(f"Expected {MAX_TOKENS} text tokens, got {len(toks)}")
        if not (0.0 <= s.left_x <= 1.0 and 0.0 <= s.width_ratio <= 1.0 and 0.0 <= s.uppercase_ratio <= 1.0):
            raise ValueError(f"Feature out of [0, 1] bounds: {s}")

    return {
        "total": len(samples),
        "classes": dict(class_counts),
        "archetypes": dict(archetype_counts),
    }


def _path_size_bytes(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file())


def train_and_export(samples: Sequence[ContextualScriptSample], output_path: Path, epochs: int, batch_size: int, seed: int) -> None:
    try:
        import numpy as np
        import torch
        import torch.nn as nn
        from torch.utils.data import DataLoader, TensorDataset
        import coremltools as ct
    except ImportError as exc:
        raise RuntimeError(
            "Full training requires torch, numpy, and coremltools (run inside Colab or pass --dry-run locally)."
        ) from exc

    torch.manual_seed(seed)
    np.random.seed(seed)

    label_to_idx = {label: idx for idx, label in enumerate(CLASSES)}

    token_arr = np.array([s.token_vector() for s in samples], dtype=np.int32)
    layout_arr = np.array([s.layout_vector() for s in samples], dtype=np.float32)
    y_arr = np.array([label_to_idx[s.label] for s in samples], dtype=np.int64)

    perm = np.random.permutation(len(samples))
    split = int(len(samples) * 0.9)
    train_idx, val_idx = perm[:split], perm[split:]

    train_ds = TensorDataset(
        torch.from_numpy(token_arr[train_idx]),
        torch.from_numpy(layout_arr[train_idx]),
        torch.from_numpy(y_arr[train_idx]),
    )
    val_ds = TensorDataset(
        torch.from_numpy(token_arr[val_idx]),
        torch.from_numpy(layout_arr[val_idx]),
        torch.from_numpy(y_arr[val_idx]),
    )

    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)

    class ContextualScriptClassifierNet(nn.Module):
        def __init__(self) -> None:
            super().__init__()
            self.emb = nn.Embedding(VOCAB_SIZE, 32, padding_idx=0)
            self.mlp = nn.Sequential(
                nn.Linear(32 + NUM_LAYOUT_FEATURES, 64),
                nn.ReLU(),
                nn.Dropout(0.15),
                nn.Linear(64, 32),
                nn.ReLU(),
                nn.Linear(32, len(CLASSES)),
            )

        def forward(self, text_tokens: torch.Tensor, layout_features: torch.Tensor) -> torch.Tensor:
            embedded = self.emb(text_tokens.long())  # [B, T, 32]
            mask = (text_tokens > 0).float().unsqueeze(-1)  # [B, T, 1]
            denom = torch.clamp(mask.sum(dim=1), min=1.0)
            pooled = (embedded * mask).sum(dim=1) / denom  # [B, 32]
            combined = torch.cat([pooled, layout_features], dim=1)
            return self.mlp(combined)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = ContextualScriptClassifierNet().to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=2e-3, weight_decay=1e-4)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=max(1, epochs))
    criterion = nn.CrossEntropyLoss()

    for epoch in range(1, epochs + 1):
        model.train()
        total_loss = 0.0
        for tok_b, lay_b, y_b in train_loader:
            tok_b, lay_b, y_b = tok_b.to(device), lay_b.to(device), y_b.to(device)
            optimizer.zero_grad()
            logits = model(tok_b, lay_b)
            loss = criterion(logits, y_b)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.item()) * len(y_b)
        scheduler.step()

        model.eval()
        correct = 0
        with torch.no_grad():
            for tok_b, lay_b, y_b in val_loader:
                tok_b, lay_b, y_b = tok_b.to(device), lay_b.to(device), y_b.to(device)
                preds = model(tok_b, lay_b).argmax(dim=1)
                correct += int((preds == y_b).sum().item())
        val_acc = correct / max(1, len(val_ds))
        print(f"Epoch {epoch:02d}/{epochs:02d} | train_loss={total_loss / len(train_ds):.4f} | val_acc={val_acc:.4f}")

    model_cpu = model.to("cpu").eval()
    example_tokens = torch.zeros((1, MAX_TOKENS), dtype=torch.int32)
    example_layout = torch.zeros((1, NUM_LAYOUT_FEATURES), dtype=torch.float32)
    traced = torch.jit.trace(model_cpu, (example_tokens, example_layout))

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.TensorType(name="text_tokens", shape=(1, MAX_TOKENS), dtype=np.int32),
            ct.TensorType(name="layout_features", shape=(1, NUM_LAYOUT_FEATURES), dtype=np.float32),
        ],
        classifier_config=ct.ClassifierConfig(list(CLASSES)),
        minimum_deployment_target=ct.target.iOS18,
    )
    mlmodel.short_description = (
        "Contextual geometry-aware script element classifier (v2) using hashed token "
        "embeddings + normalized layout indentation and neighbor class context."
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))
    size_bytes = _path_size_bytes(output_path)
    print(f"Saved Core ML package to {output_path} ({size_bytes / 1024.0:.1f} KB)")
    if size_bytes >= MAX_MODEL_BYTES:
        raise RuntimeError(f"Exported model exceeds 5 MB budget: {size_bytes} bytes")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Train ScriptElementClassifierV2 (contextual geometry + text hybrid)")
    parser.add_argument("--dry-run", "--generate-only", action="store_true", dest="dry_run",
                        help="Generate and validate the 25k dataset using stdlib only without exporting Core ML.")
    parser.add_argument("--count", type=int, default=25000, help="Number of synthetic training lines to generate.")
    parser.add_argument("--seed", type=int, default=20261113, help="Deterministic RNG seed.")
    parser.add_argument("--epochs", type=int, default=12, help="Training epochs for PyTorch model.")
    parser.add_argument("--batch-size", type=int, default=128, help="Mini-batch size.")
    parser.add_argument("--output", type=Path, default=Path("OneTake/Core/Models/ScriptElementClassifierV2.mlpackage"),
                        help="Output .mlpackage directory path.")
    parser.add_argument("--save-dataset", type=Path, default=None,
                        help="Optional JSONL path to write generated samples.")
    args = parser.parse_args(argv)

    samples = generate_dataset(count=args.count, seed=args.seed)
    stats = validate_dataset(samples)

    if args.save_dataset is not None:
        args.save_dataset.parent.mkdir(parents=True, exist_ok=True)
        with args.save_dataset.open("w", encoding="utf-8") as fp:
            for sample in samples:
                fp.write(json.dumps(asdict(sample), ensure_ascii=False) + "\n")

    print(json.dumps({
        "mode": "dry-run" if args.dry_run else "train",
        "stats": stats,
        "feature_dims": {"text_tokens": MAX_TOKENS, "layout_features": NUM_LAYOUT_FEATURES},
        "vocab_size": VOCAB_SIZE,
    }, indent=2))

    if args.dry_run:
        return 0

    train_and_export(samples, output_path=args.output, epochs=args.epochs, batch_size=args.batch_size, seed=args.seed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
