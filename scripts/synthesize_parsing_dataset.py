#!/usr/bin/env python3
"""
OneTake Parsing & Extraction Dataset Synthesizer
================================================
Generates instruction-tuning datasets (ChatML format) to fine-tune an LLM backend
to parse noisy, OCR-scanned audition materials into OneTake's exact JSON schemas:
  1. Casting Notice Breakdown -> NoticeParser.Draft schema
  2. Screenplay Sides -> [ScriptScene] & [ScriptLine] schema

Applies realistic mobile-scan OCR degradation:
  - Column merge & broken dialogue line wraps
  - Indentation and tab-stop loss
  - Case degradation (cues losing ALL-CAPS)
  - Character cue glued onto dialogue text
  - Optical character substitution (l/1/I, rn/m, cl/d, 0/O)
  - Random header/footer artifacts & page numbers
"""

import os
import sys
import json
import random
import re
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
DATASET_DIR.mkdir(parents=True, exist_ok=True)

OUTPUT_TRAIN_FILE = DATASET_DIR / "parsing_dataset_train.jsonl"
OUTPUT_EVAL_FILE = DATASET_DIR / "parsing_dataset_eval.jsonl"

# -------------------------------------------------------------------------
# 1. OCR Degradation & Noise Injection Engine
# -------------------------------------------------------------------------

GLYPH_SUBSTITUTIONS = {
    "l": "1",
    "I": "l",
    "O": "0",
    "0": "O",
    "rn": "m",
    "m": "rn",
    "cl": "d",
    "vv": "w",
    "'": "`",
    '"': "''"
}

HEADER_FOOTER_NOISE = [
    "Page {page} of {total}",
    "- {page} -",
    "CONFIDENTIAL CASTING MATERIAL",
    "DO NOT DISTRIBUTE - PROPERTY OF CASTING OFFICE",
    "Audition Sides | Draft v2.4",
    "Scanned with CamScanner",
    "WATERMARK - PROPERTY OF PRODUCTION",
    "Revised Draft {date}"
]

def inject_ocr_noise(text: str, severity: float = 0.5) -> str:
    """
    Simulates real smartphone camera OCR artifacts on physical script paper.
    """
    lines = text.split("\n")
    noisy_lines = []
    page = 1
    total_pages = max(1, len(lines) // 45 + 1)

    for idx, raw_line in enumerate(lines):
        line = raw_line
        r = random.random()

        # Randomly inject page headers / footers every ~40 lines
        if idx > 0 and idx % 42 == 0 and random.random() < 0.6 * severity:
            noise_template = random.choice(HEADER_FOOTER_NOISE)
            noisy_lines.append("")
            noisy_lines.append(noise_template.format(page=page, total=total_pages, date="11/2026"))
            noisy_lines.append("")
            page += 1

        # 1. Dropped leading indentation (most common OCR failure on screenplay margins)
        if random.random() < 0.35 * severity:
            line = line.lstrip()

        # 2. Case collapse (scene headings or character cues losing uppercase)
        if line.strip().isupper() and len(line.strip()) > 3:
            if random.random() < 0.20 * severity:
                line = line.capitalize()

        # 3. Broken line wraps inside narrow dialogue blocks
        if len(line) > 35 and random.random() < 0.25 * severity:
            split_idx = random.randint(15, len(line) - 10)
            noisy_lines.append(line[:split_idx])
            noisy_lines.append(line[split_idx:].lstrip())
            continue

        # 4. Character cue merged with dialogue (column OCR failure)
        # e.g. "DETECTIVE MILLER" + "What did you see?" -> "DETECTIVE MILLER What did you see?"
        if (line.strip().isupper() and 2 <= len(line.strip().split()) <= 4 and
                idx + 1 < len(lines) and lines[idx + 1].strip() and random.random() < 0.25 * severity):
            line = line.strip() + " " + lines[idx + 1].strip()

        # 5. Optical glyph substitutions
        if random.random() < 0.20 * severity:
            for target_char, sub_char in GLYPH_SUBSTITUTIONS.items():
                if target_char in line and random.random() < 0.35:
                    line = line.replace(target_char, sub_char, 1)
                    break

        # 6. Random punctuation artifacts or speckles
        if random.random() < 0.08 * severity:
            line = line + random.choice([".", ",", "'", " -", " ~"])

        noisy_lines.append(line)

    return "\n".join(noisy_lines)

# -------------------------------------------------------------------------
# 2. Clean Screenplay & Notice Seed Data
# -------------------------------------------------------------------------

BASE_NOTICES = [
    {
        "project": "Cold Harbor",
        "project_type": "Feature Film",
        "role": "Frank Vance",
        "candidate_roles": ["Frank Vance", "Agent Ortiz", "Mayor Hayes"],
        "role_size": "Lead",
        "casting_office": "Automatic Casting NYC",
        "due_date": "2026-11-20T18:00:00Z",
        "specs": ["Framing: Medium close-up, horizontal/landscape only", "Slate: Name, height, location at the top", "No props or costumes"],
        "sides_link": "https://drive.google.com/drive/folders/cold_harbor_sides",
        "submission_email": "tapes@coldharborfilm.com",
        "director_guidance": "Frank is weathered, morally conflicted, speaks deliberately."
    },
    {
        "project": "Sunset Meridian",
        "project_type": "TV Episodic",
        "role": "Dr. Claire Sterling",
        "candidate_roles": ["Dr. Claire Sterling", "Paramedic Reyes"],
        "role_size": "Series Regular",
        "casting_office": "Vanguard Casting Associates",
        "due_date": "2026-12-01T21:00:00Z",
        "specs": ["Framing: Eye-level chest up", "Upload format: MP4 or MOV max 400MB", "Include both scenes in a single video file"],
        "sides_link": "https://www.dropbox.com/s/sunset_sterling_sides.pdf",
        "submission_email": "submissions@vanguardcasting.la",
        "director_guidance": "High-functioning trauma surgeon, sharp cadence, hides exhaustion behind humor."
    },
    {
        "project": "Shadows in the Mist",
        "project_type": "Limited Series",
        "role": "Detective Alan Miller",
        "candidate_roles": ["Detective Alan Miller", "Chief Briggs", "Hannah Ross"],
        "role_size": "Lead",
        "casting_office": "London Bridge Casting",
        "due_date": "2026-11-18T17:00:00Z",
        "specs": ["Orientation: Horizontal only", "Audio: Ensure clear reader audio off-camera", "Slate: Full-length body shot first 5 seconds"],
        "sides_link": "https://wetransfer.com/downloads/shadows_sides",
        "submission_email": "alan-miller@londonbridgecasting.co.uk",
        "director_guidance": "Ex-Scotland Yard detective. Soft-spoken, observant, never raises his voice."
    }
]

BASE_SCENES = [
    {
        "title": "Scene 1 - Cold Harbor",
        "heading": "INT. WAREHOUSE OFFICE - NIGHT",
        "lines": [
            {"character": "FRANK VANCE", "text": "I checked the manifests twice. The crates never cleared customs at Pier 40."},
            {"character": "AGENT ORTIZ", "text": "They didn't clear because someone flagged the cargo codes an hour before arrival."},
            {"character": "FRANK VANCE", "parenthetical": "lighting a cigarette, steady", "text": "Who had access to that terminal besides Hayes?"},
            {"character": "AGENT ORTIZ", "text": "Nobody you want to pick a fight with, Frank. Walk away while you still have a badge."},
            {"character": "FRANK VANCE", "text": "I turned in the badge at six this morning. Now answer the question."}
        ]
    },
    {
        "title": "Scene 2 - Hospital Hallway",
        "heading": "INT. METRO GENERAL - TRAUMA CORRIDOR - DAWN",
        "lines": [
            {"character": "DR. CLAIRE STERLING", "text": "Page surgical floor four. If his blood pressure dips below ninety, start dopamine."},
            {"character": "PARAMEDIC REYES", "text": "His family is in waiting room B. They've been asking for an update since midnight."},
            {"character": "DR. CLAIRE STERLING", "parenthetical": "stopping, taking off surgical mask", "text": "Tell them we stabilized the bleed. He made it through the night. I'll be in to talk to them after morning rounds."},
            {"character": "PARAMEDIC REYES", "text": "Thank you, doctor. You should get some sleep."},
            {"character": "DR. CLAIRE STERLING", "text": "I'll sleep when the shift ends."}
        ]
    },
    {
        "title": "Scene 3 - Coastal Diner",
        "heading": "EXT. HIGHWAY DINER - DUSK",
        "lines": [
            {"character": "HANNAH ROSS", "text": "You shouldn't have contacted me here, Alan."},
            {"character": "DETECTIVE ALAN MILLER", "text": "Your brother sent me the ledger before he went missing."},
            {"character": "HANNAH ROSS", "parenthetical": "nervously checking the parking lot", "text": "Then you know what happens to anyone who reads those names."},
            {"character": "DETECTIVE ALAN MILLER", "text": "I've spent twenty years reading names like these. Get in the car."}
        ]
    }
]

# -------------------------------------------------------------------------
# 3. Generation of ChatML Instruction Samples
# -------------------------------------------------------------------------

SYSTEM_PROMPT_NOTICE = """You are OneTake's high-precision audition notice parsing engine.
Your task: Parse raw, OCR-scanned casting notices or email breakdowns into strict JSON matching OneTake's NoticeParser.Draft schema.
Extract:
- project: title of the project
- project_type: Feature Film, TV Episodic, Limited Series, Commercial, Theater, etc.
- role: primary character name being auditioned
- candidate_roles: list of all roles mentioned in the casting call
- role_size: Lead, Supporting, Series Regular, Guest Star, Day Player, etc.
- casting_office: casting agency or director
- due_date: ISO 8601 formatted timestamp or null
- specs: list of specific self-tape framing, slate, and format instructions
- sides_link: URL for script sides if present
- submission_email: email address or submission link
- director_guidance: character notes, tone, or director's vision

Respond with valid JSON only. Do not add markdown commentary outside the JSON block."""

SYSTEM_PROMPT_SIDES = """You are OneTake's screenplay sides parsing engine.
Your task: Parse messy, OCR-scanned screenplay audition sides into structured scene and dialogue objects.
Extract:
- scenes: array of scene objects, each containing:
  - number: integer scene index (1-based)
  - heading: scene slugline (e.g. INT. WAREHOUSE - NIGHT)
  - lines: array of spoken lines in chronological order:
    - character: uppercase speaker name
    - parenthetical: emotional or action direction (or null if none)
    - text: dialogue line spoken by the character

Respond with valid JSON only. Do not add commentary outside the JSON block."""

def format_notice_as_raw_text(notice: dict) -> str:
    """Formats a notice dictionary into standard raw breakdown copy."""
    lines = [
        "*** OFFICIAL CASTING CALL ***",
        f"PROJECT: {notice['project'].upper()}",
        f"FORMAT: {notice['project_type']}",
        f"CASTING OFFICE: {notice['casting_office']}",
        f"DEADLINE: {notice['due_date'].replace('T', ' ')}",
        "",
        "ROLES AVAILABLE:",
    ]
    for r in notice["candidate_roles"]:
        lines.append(f"• {r.upper()} ({notice['role_size'] if r == notice['role'] else 'Supporting'})")
    lines.append("")
    lines.append(f"AUDITION SIDES DOWNLOAD: {notice['sides_link']}")
    lines.append(f"SUBMISSION INSTRUCTIONS & CONTACT: {notice['submission_email']}")
    lines.append("")
    lines.append("SELF-TAPE SPECIFICATIONS:")
    for spec in notice["specs"]:
        lines.append(f"- {spec}")
    lines.append("")
    lines.append(f"DIRECTOR'S NOTE / CHARACTER BRIEF: {notice['director_guidance']}")
    return "\n".join(lines)

def format_scene_as_screenplay(scene: dict) -> str:
    """Formats a scene into standard Courier Hollywood script text."""
    lines = [
        f"AUDITION SIDES — {scene['title'].upper()}",
        "",
        scene["heading"],
        ""
    ]
    for line in scene["lines"]:
        lines.append(f"                   {line['character']}")
        if "parenthetical" in line and line["parenthetical"]:
            lines.append(f"                ({line['parenthetical']})")
        lines.append(f"         {line['text']}")
        lines.append("")
    lines.append("[END OF SCENE]")
    return "\n".join(lines)

def generate_dataset(num_samples: int = 150):
    print(f"[Synthesizer] Generating {num_samples} instruction-tuning samples...")
    samples = []

    for i in range(num_samples):
        # 50% Notice breakdowns, 50% Audition sides
        if i % 2 == 0:
            # Notice breakdown sample
            notice = random.choice(BASE_NOTICES).copy()
            # Randomize project and role details slightly
            raw_text = format_notice_as_raw_text(notice)
            noisy_text = inject_ocr_noise(raw_text, severity=random.uniform(0.3, 0.8))

            target_json = {
                "project": notice["project"],
                "project_type": notice["project_type"],
                "role": notice["role"],
                "candidate_roles": notice["candidate_roles"],
                "role_size": notice["role_size"],
                "casting_office": notice["casting_office"],
                "due_date": notice["due_date"],
                "specs": notice["specs"],
                "sides_link": notice["sides_link"],
                "submission_email": notice["submission_email"],
                "director_guidance": notice["director_guidance"]
            }

            sample = {
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT_NOTICE},
                    {"role": "user", "content": f"Parse this scanned casting notice OCR into OneTake JSON:\n\n{noisy_text}"},
                    {"role": "assistant", "content": json.dumps(target_json, indent=2)}
                ]
            }
        else:
            # Audition sides sample
            scene = random.choice(BASE_SCENES).copy()
            raw_script = format_scene_as_screenplay(scene)
            noisy_script = inject_ocr_noise(raw_script, severity=random.uniform(0.3, 0.8))

            target_json = {
                "scenes": [
                    {
                        "number": 1,
                        "heading": scene["heading"],
                        "lines": scene["lines"]
                    }
                ]
            }

            sample = {
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT_SIDES},
                    {"role": "user", "content": f"Parse these scanned screenplay sides into OneTake scene & dialogue JSON:\n\n{noisy_script}"},
                    {"role": "assistant", "content": json.dumps(target_json, indent=2)}
                ]
            }

        samples.append(sample)

    # 85% train, 15% eval split
    random.shuffle(samples)
    split = int(len(samples) * 0.85)
    train_samples = samples[:split]
    eval_samples = samples[split:]

    with open(OUTPUT_TRAIN_FILE, "w", encoding="utf-8") as f:
        for s in train_samples:
            f.write(json.dumps(s) + "\n")

    with open(OUTPUT_EVAL_FILE, "w", encoding="utf-8") as f:
        for s in eval_samples:
            f.write(json.dumps(s) + "\n")

    print(f" Dataset synthesized successfully!")
    print(f" Train File: {OUTPUT_TRAIN_FILE} ({len(train_samples)} samples)")
    print(f" Eval File:  {OUTPUT_EVAL_FILE} ({len(eval_samples)} samples)")

if __name__ == "__main__":
    generate_dataset(160)
