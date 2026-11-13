#!/usr/bin/env python3
"""
OneTake Offline Parser v2 Corpus & Synthetic Casting Poster Generator
====================================================================
Generates paired training and held-out adversarial evaluation corpora for:
  - LiquidAI/LFM2.5-VL-450M (poster PNG images -> 18-key SemanticNoticePayload)
  - Needle 3 (<= 1,024-token OCR-noisy notice slices -> 18-key SemanticNoticePayload)

Outputs inside --output-dir:
  - train_vlm.jsonl, eval_vlm.jsonl
  - train_needle.jsonl, eval_needle.jsonl
  - images/train/poster_*.png, images/eval/poster_*.png (768x960 RGB PNGs)
  - corpus_manifest.json (counts, layout distribution, read-only fixture inventory)

Rendering uses Pillow (`PIL`) when installed (e.g. Google Colab) and falls back
to a pure-stdlib (`zlib` + `struct`) PNG renderer locally on macOS so tests run
with zero third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import random
import re
import struct
import textwrap
from typing import Any
import zlib

try:
    from PIL import Image, ImageDraw, ImageFont  # type: ignore

    HAS_PIL = True
except ImportError:  # pragma: no cover - local macOS stdlib fallback
    Image = None  # type: ignore
    ImageDraw = None  # type: ignore
    ImageFont = None  # type: ignore
    HAS_PIL = False

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = REPO_ROOT / "dataset" / "offline_v2"

DEFAULT_IMAGE_WIDTH = 768
DEFAULT_IMAGE_HEIGHT = 960
MAX_NEEDLE_TOKENS = 1024
MAX_NEEDLE_WORDS = 750

# Canonical 18-key SemanticNoticePayload schema from the v2 design spec.
# Note: `specs` corresponds to `NoticeParser.Draft.asks` (`eval_offline_v2.py`
# accepts both `specs` and `asks` when scoring predictions).
CANONICAL_SCHEMA_KEYS: tuple[str, ...] = (
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
)

LAYOUT_VARIANTS: tuple[str, ...] = (
    "two_column_grid",
    "watermark_clapperboard",
    "low_contrast_footer",
    "regional_multilingual",
    "agency_logo_decoy",
    "gradient_editorial_card",
)

VLM_SYSTEM_PROMPT = (
    "You are OneTake's offline casting notice VLM parser. "
    "Extract all 18 SemanticNoticePayload JSON keys from the casting poster image. "
    "Return valid JSON only with keys: "
    + ", ".join(CANONICAL_SCHEMA_KEYS)
    + "."
)

NEEDLE_SYSTEM_PROMPT = (
    "You are OneTake's offline casting notice text parser. "
    "Extract all 18 SemanticNoticePayload JSON keys from the bounded notice text slice. "
    "Return valid JSON only with keys: "
    + ", ".join(CANONICAL_SCHEMA_KEYS)
    + "."
)

# Disjoint pools so train and held-out adversarial eval sets have zero overlap
# on projects, casting offices, or submission email domains.
TRAIN_POOLS: dict[str, Any] = {
    "projects": [
        ("Monsoon Express", "Feature Film"),
        ("Glass Harbor", "TV Episodic"),
        ("Saffron Kitchen", "Commercial"),
        ("Naya Savera", "Feature Film"),
        ("Silver Line", "Short Film"),
        ("Pind Diaries", "TV Episodic"),
        ("Velvet Curtain", "Theater"),
        ("Urban Pulse EV", "Commercial"),
        ("Chai & Rain", "Web Series"),
        ("Harbor Precinct", "TV Episodic"),
        ("Kite Runners of Jaipur", "Feature Film"),
        ("Night Shift 14", "Short Film"),
    ],
    "offices": [
        ("Bayshore Casting", "bayshorecasting.example", "Bayshore Talent Group", "info@bayshore-agency.invalid"),
        ("MCCC Casting Mumbai", "mccc-cast.example", "Metro Creative Collective", "hello@metrocreative.invalid"),
        ("Vanguard Talent LA", "vanguardtalent.example", "Vanguard Management", "desk@vanguard-mgmt.invalid"),
        ("Casting Bay India", "castingbay.example", "Bay Studio Brands", "brand@baystudio.invalid"),
        ("Northstar Casting", "northstarcast.example", "Northstar Productions", "press@northstarprod.invalid"),
        ("Anti-Casting House", "anticasting.example", "Anti-Casting Network", "team@anticastnet.invalid"),
    ],
    "locations": [
        "Mumbai, Maharashtra",
        "Los Angeles, CA",
        "New York, NY",
        "Chandigarh, Punjab",
        "London, UK",
        "Toronto, ON",
        "New Delhi, India",
        "Atlanta, GA",
    ],
    "roles": [
        ("Detective Maya Lin", ["Detective Maya Lin", "Officer Ortiz", "Chief Briggs"], "Lead"),
        ("Arjun Malhotra", ["Arjun Malhotra", "Ananya Verma", "Dadu"], "Lead"),
        ("Gurpreet Singh", ["Gurpreet Singh", "Simran Kaur", "Harbhajan"], "Supporting"),
        ("Dr. Claire Sterling", ["Dr. Claire Sterling", "Paramedic Reyes"], "Series Regular"),
        ("Rhea Kapoor", ["Rhea Kapoor", "Kabir Sen", "Mrs. Khanna"], "Lead"),
        ("Marcus Vance", ["Marcus Vance", "Elena Shaw"], "Co-Star"),
    ],
    "sides_hosts": [
        "https://sides.traincast.example/packets",
        "https://portal.tapereels.example/sides",
    ],
}

EVAL_POOLS: dict[str, Any] = {
    "projects": [
        ("Red Lanterns of Amritsar", "Feature Film"),
        ("Signal Nine", "TV Episodic"),
        ("Breeze Cola Festive", "Commercial"),
        ("Dhundh", "Short Film"),
        ("Third Bell", "Theater"),
        ("Coastline Motors", "Commercial"),
        ("Satluj Crossing", "Feature Film"),
        ("Midnight Triage", "TV Episodic"),
    ],
    "offices": [
        ("Crestline Casting Lab", "crestlinecast.example", "Crestline Media", "hello@crestlinemedia.invalid"),
        ("Katha Audition Studio", "katha-auditions.example", "Katha Films Banner", "banner@kathafilms.invalid"),
        ("Silverleaf Casting UK", "silverleafcast.example", "Silverleaf Artists", "office@silverleafartists.invalid"),
        ("Lotus Frame Casting", "lotusframe.example", "Lotus Brand Lab", "contact@lotusbrand.invalid"),
    ],
    "locations": [
        "Hyderabad, India",
        "Chicago, IL",
        "Vancouver, BC",
        "Jaipur, Rajasthan",
        "Manchester, UK",
        "Austin, TX",
    ],
    "roles": [
        ("Inspector Kavita Nair", ["Inspector Kavita Nair", "Rohan Bedi"], "Lead"),
        ("Harpreet Gill", ["Harpreet Gill", "Bebe Ji", "Taran"], "Supporting"),
        ("Sasha Vance", ["Sasha Vance", "Julian Cole", "Nurse Vega"], "Series Regular"),
        ("Devansh Joshi", ["Devansh Joshi", "Meera Patel"], "Principal"),
    ],
    "sides_hosts": [
        "https://eval-sides.holdoutcast.example/files",
        "https://scripts.auditionvault.example/s",
    ],
}

SPECS_BANK: tuple[tuple[str, ...], ...] = (
    ("Landscape", "Slate first", "Medium close-up", "Two takes"),
    ("Portrait", "Full body frame", "Introduction in Hindi & English", "No background music"),
    ("Landscape", "Chest-up framing", "Punjabi dialogue read", "Keep slate separate"),
    ("Portrait", "Natural lighting", "Mid-shot", "Show both profiles"),
    ("Landscape", "Wide to close", "Neutral wardrobe", "MP4 1080p"),
)

UNION_OPTIONS: tuple[str | None, ...] = (
    "SAG-AFTRA",
    "Non-Union",
    "CINTAA / Non-Union",
    "Equity",
    None,
)

PAY_OPTIONS: tuple[str | None, ...] = (
    "SAG Scale + 10%",
    "INR 45,000 / shoot day",
    "$850/day + buyout",
    "GBP 600 flat",
    None,
)

FILE_NAMING_TEMPLATES: tuple[str | None, ...] = (
    "{role}_{project}_FullName.mp4",
    "Name_Role_Age_City.mp4",
    "{project_slug}_{role_slug}_Tape.mov",
    None,
)

REGIONAL_NOTES: tuple[str, ...] = (
    "Fluent Hindi & Punjabi speaker (Hinglish natural tone, अमृतसर / दिल्ली accent welcome).",
    "Conversational Punjabi (ਪੰਜਾਬੀ) + English bilingual delivery; warm grounded energy.",
    "Native Hindi (हिंदी) diction with subtle Mumbai cadence; no theatrical over-projection.",
    "Bilingual Urdu/Hindi & English comfort; realistic understated reactions.",
)

GENERAL_NOTES: tuple[str, ...] = (
    "Naturalistic, lived-in stillness. Do not memorize word-for-word at expense of eye line.",
    "Quick comedic timing on the turn; keep eye-line just off camera left.",
    "High-stakes procedural tone; sharp listening beats between lines.",
    "Warm family chemistry; improvise a brief greeting at the top of take 2.",
)

# Compact 5x7 uppercase bitmap glyphs for pure-stdlib fallback PNG text rendering
_GLYPHS_5X7: dict[str, tuple[str, ...]] = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11100", "10010", "10001", "10001", "10001", "10010", "11100"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01110"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("01110", "00100", "00100", "00100", "00100", "00100", "01110"),
    "J": ("00111", "00010", "00010", "00010", "10010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
    "0": ("01110", "10011", "10101", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00110", "01000", "10000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("01110", "10000", "11110", "10001", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "@": ("01110", "10001", "10111", "10101", "10110", "10000", "01111"),
    ".": ("00000", "00000", "00000", "00000", "00000", "01100", "01100"),
    ":": ("00000", "01100", "01100", "00000", "01100", "01100", "00000"),
    "-": ("00000", "00000", "00000", "11111", "00000", "00000", "00000"),
    "_": ("00000", "00000", "00000", "00000", "00000", "00000", "11111"),
    "/": ("00001", "00010", "00010", "00100", "01000", "01000", "10000"),
    "|": ("00100", "00100", "00100", "00100", "00100", "00100", "00100"),
    " ": ("00000", "00000", "00000", "00000", "00000", "00000", "00000"),
}


def estimate_token_count(text: str) -> int:
    """
    Conservative token count estimator for Needle 3's 1,024-token context limit.
    Counts subword-like chunks (alphanumeric words + punctuation) with a 1.15x
    safety multiplier matching SentencePiece/BPE expansion on noisy OCR text.
    """
    stripped = text.strip()
    if not stripped:
        return 0
    chunks = re.findall(r"[A-Za-z0-9]+|[^\w\s]", stripped, flags=re.UNICODE)
    word_bound = math.ceil(len(stripped.split()) * 1.32)
    chunk_bound = math.ceil(len(chunks) * 1.15)
    return max(word_bound, chunk_bound)


def inspect_repo_fixtures(repo_root: Path = REPO_ROOT) -> list[dict[str, Any]]:
    """
    Inspect real repo casting fixtures in read-only mode (never modifying or
    requiring untracked root files to be present).
    """
    candidates = (
        repo_root / "OneTakeTests" / "Resources" / "flyer_test.jpg",
        repo_root / "OneTakeTests" / "Resources" / "Grease+Audition+Sides+V2.pdf",
        repo_root / "OneTakeTests" / "Resources" / "Pilgrimage_Casting_Sides.pdf",
    )
    found: list[dict[str, Any]] = []
    for path in candidates:
        if path.exists():
            found.append(
                {
                    "path": str(path.relative_to(repo_root)),
                    "byte_size": path.stat().st_size,
                    "kind": path.suffix.lower().lstrip("."),
                }
            )
    return found


def _slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", value.casefold()).strip("-") or "cast"


def build_notice_sample(
    index: int,
    split: str,
    layout: str,
    rng: random.Random,
) -> dict[str, Any]:
    """Build one canonical 18-key SemanticNoticePayload target plus layout metadata."""
    pool = TRAIN_POOLS if split == "train" else EVAL_POOLS
    project_title, project_type = pool["projects"][index % len(pool["projects"])]
    office_name, office_domain, agency_brand, decoy_email = pool["offices"][
        (index + rng.randint(0, 3)) % len(pool["offices"])
    ]
    role, candidate_roles, role_size = pool["roles"][
        (index + rng.randint(0, 2)) % len(pool["roles"])
    ]
    location = pool["locations"][(index + rng.randint(0, 4)) % len(pool["locations"])]
    specs = list(SPECS_BANK[(index + rng.randint(0, 2)) % len(SPECS_BANK)])
    orientation = "Portrait" if "Portrait" in specs else "Landscape"

    due_day = 10 + (index % 18)
    due_date_text = f"Nov {due_day}, 2026 6:00 PM"
    callback_dates_text = f"Nov {due_day + 5}, 2026" if (index % 4 != 3) else None
    shoot_dates_text = f"Dec {2 + (index % 15)}-{5 + (index % 15)}, 2026" if (index % 5 != 4) else None

    include_sides = (split == "eval") or (index % 3 != 2)
    sides_host = pool["sides_hosts"][index % len(pool["sides_hosts"])]
    sides_link = f"{sides_host}/{_slug(project_title)}-{index:04d}.pdf" if include_sides else None

    email_alias = f"cast-{_slug(project_title)[:12]}-{index % 97:02d}@{office_domain}"
    submission_email = email_alias if (split == "eval" or index % 7 != 6) else None

    union_status = UNION_OPTIONS[index % len(UNION_OPTIONS)]
    pay_terms = PAY_OPTIONS[index % len(PAY_OPTIONS)]
    naming_tmpl = FILE_NAMING_TEMPLATES[index % len(FILE_NAMING_TEMPLATES)]
    file_naming = (
        naming_tmpl.format(
            role=_slug(role).replace("-", "_"),
            project=_slug(project_title).replace("-", "_"),
            project_slug=_slug(project_title),
            role_slug=_slug(role),
        )
        if naming_tmpl
        else None
    )

    if layout == "regional_multilingual":
        casting_notes = REGIONAL_NOTES[index % len(REGIONAL_NOTES)]
    else:
        casting_notes = GENERAL_NOTES[index % len(GENERAL_NOTES)]

    target: dict[str, Any] = {
        "project": project_title,
        "project_type": project_type,
        "role": role,
        "candidate_roles": list(candidate_roles),
        "role_size": role_size,
        "casting_office": office_name,
        "due_date_text": due_date_text,
        "specs": specs,
        "sides_link": sides_link,
        "submission_email": submission_email,
        "location": location,
        "casting_notes": casting_notes,
        "union_status": union_status,
        "pay_terms": pay_terms,
        "callback_dates_text": callback_dates_text,
        "shoot_dates_text": shoot_dates_text,
        "orientation": orientation,
        "file_naming": file_naming,
    }
    return {
        "target": target,
        "layout": layout,
        "agency_brand": agency_brand,
        "decoy_email": decoy_email,
    }


def _apply_ocr_noise(line: str, rng: random.Random, severity: float, preserve_exact: bool = False) -> str:
    if preserve_exact or not line.strip():
        return line
    noisy = line
    if rng.random() < 0.25 * severity:
        noisy = noisy.lstrip()
    if rng.random() < 0.18 * severity:
        for src, dst in (("l", "1"), ("rn", "m"), ("O", "0")):
            if src in noisy and "@" not in noisy and "http" not in noisy:
                noisy = noisy.replace(src, dst, 1)
                break
    return noisy


def render_notice_text(
    sample: dict[str, Any],
    rng: random.Random,
    severity: float = 0.35,
) -> tuple[str, list[str]]:
    """
    Create realistic notice OCR text (and adversarial tags) for Needle 3,
    deterministically bounded to <= MAX_NEEDLE_WORDS (750) and <= MAX_NEEDLE_TOKENS (1024).
    """
    t = sample["target"]
    layout = sample["layout"]
    tags: list[str] = [layout]

    header_lines = [
        f"CASTING CALL: {t['project']} ({t['project_type']})",
        f"CASTING OFFICE: {t['casting_office']}",
    ]
    if layout == "agency_logo_decoy":
        header_lines.insert(0, f"[LOGO: {sample['agency_brand']} | Press/General: {sample['decoy_email']}]")
        tags.append("agency_decoy_email")
    if layout == "watermark_clapperboard":
        header_lines.insert(1, "=== CONFIDENTIAL SIDES & BREAKDOWN — DO NOT DISTRIBUTE ===")
        tags.append("watermark_clapperboard")

    role_lines = [
        f"PRIMARY ROLE: {t['role']} ({t['role_size']})",
        f"ALL ROLES: {', '.join(t['candidate_roles'])}",
        f"LOCATION: {t['location']}",
    ]
    schedule_lines = [
        f"DUE: {t['due_date_text']}",
        f"SPECS: {' | '.join(t['specs'])}",
        f"ORIENTATION: {t['orientation']}",
    ]
    if t["union_status"]:
        schedule_lines.append(f"UNION: {t['union_status']}")
    if t["pay_terms"]:
        schedule_lines.append(f"RATE / PAY: {t['pay_terms']}")
    if t["callback_dates_text"]:
        schedule_lines.append(f"CALLBACKS: {t['callback_dates_text']}")
    if t["shoot_dates_text"]:
        schedule_lines.append(f"SHOOT DATES: {t['shoot_dates_text']}")
    if t["file_naming"]:
        schedule_lines.append(f"FILE NAMING: {t['file_naming']}")
    if t["casting_notes"]:
        schedule_lines.append(f"CASTING NOTES: {t['casting_notes']}")

    # Include simulated sides/boilerplate middle lines on some records so
    # deterministic truncation is exercised without ever exceeding 1024 tokens.
    filler_lines: list[str] = []
    if rng.random() < 0.35:
        tags.append("multi_page_sides_trimmed")
        filler_lines = [
            f"SCENE {n} PREVIEW — INT. STUDIO CORRIDOR - NIGHT: {t['role']} checks the call sheet and steps onto the mark."
            for n in range(1, 32)
        ]

    footer_lines: list[str] = []
    if t["sides_link"]:
        footer_lines.append(f"DOWNLOAD SIDES: {t['sides_link']}")
    if t["submission_email"]:
        prefix = "WHITE-ON-TAN FOOTER — SEND SELF-TAPE TO:" if layout == "low_contrast_footer" else "SUBMIT TAPES TO:"
        footer_lines.append(f"{prefix} {t['submission_email']}")
        if layout == "low_contrast_footer":
            tags.append("low_contrast_footer")

    noisy_middle = [_apply_ocr_noise(line, rng, severity) for line in (role_lines + schedule_lines)]
    if layout == "two_column_grid" and len(noisy_middle) >= 4:
        # Simulate two-column OCR interleaving
        half = len(noisy_middle) // 2
        interleaved: list[str] = []
        for left, right in zip(noisy_middle[:half], noisy_middle[half:]):
            interleaved.append(f"{left}    ||    {right}")
        if len(noisy_middle) % 2:
            interleaved.append(noisy_middle[-1])
        noisy_middle = interleaved
        tags.append("two_column_interleave")

    bounded = bound_needle_text_slice(
        priority_header=header_lines,
        body_lines=noisy_middle + filler_lines,
        priority_footer=footer_lines,
        max_words=MAX_NEEDLE_WORDS - 30,
        max_tokens=MAX_NEEDLE_TOKENS - 60,
    )
    return bounded, tags


def bound_needle_text_slice(
    priority_header: list[str],
    body_lines: list[str],
    priority_footer: list[str],
    max_words: int = 700,
    max_tokens: int = 960,
) -> str:
    """
    Deterministically keep front-matter headers and footer submission lines
    inside the Needle 3 token/word envelope, trimming excess body lines.
    """
    header_footer = priority_header + priority_footer
    selected_body: list[str] = []

    for line in body_lines:
        candidate = "\n".join(priority_header + selected_body + [line] + priority_footer)
        if len(candidate.split()) <= max_words and estimate_token_count(candidate) <= max_tokens:
            selected_body.append(line)
        else:
            break

    result = "\n".join(priority_header + selected_body + priority_footer)
    if len(result.split()) <= max_words and estimate_token_count(result) <= max_tokens:
        return result

    # Hard fallback trim on header_footer only if even body-free text exceeds budget
    words = " ".join(header_footer).split()[:max_words]
    while words and estimate_token_count(" ".join(words)) > max_tokens:
        words.pop()
    return " ".join(words)


# ---------------------------------------------------------------------------
# Poster PNG Rendering (Pillow in Colab + fast pure-stdlib zlib/struct fallback)
# ---------------------------------------------------------------------------

def _ascii_safe(text: str) -> str:
    return text.encode("ascii", "replace").decode("ascii")


def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)


def _fill_rect_rgb(
    buf: bytearray,
    stride: int,
    width: int,
    height: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    color: tuple[int, int, int],
) -> None:
    cx0 = max(0, min(width, x0))
    cx1 = max(0, min(width, x1))
    cy0 = max(0, min(height, y0))
    cy1 = max(0, min(height, y1))
    span = cx1 - cx0
    if span <= 0 or cy1 <= cy0:
        return
    row_bytes = bytes(color) * span
    for y in range(cy0, cy1):
        start = y * stride + 1 + cx0 * 3
        buf[start : start + span * 3] = row_bytes


def _draw_bitmap_text_rgb(
    buf: bytearray,
    stride: int,
    width: int,
    height: int,
    x: int,
    y: int,
    text: str,
    color: tuple[int, int, int],
    scale: int = 2,
    max_x: int | None = None,
) -> None:
    cursor_x = x
    limit_x = (width - 16) if max_x is None else min(width, max_x)
    color_px = bytes(color) * scale
    for ch in _ascii_safe(text).upper():
        glyph = _GLYPHS_5X7.get(ch, _GLYPHS_5X7[" "])
        if cursor_x + 5 * scale > limit_x:
            break
        for gy, row_mask in enumerate(glyph):
            for sy in range(scale):
                py = y + gy * scale + sy
                if not (0 <= py < height):
                    continue
                row_offset = py * stride + 1
                for gx, bit in enumerate(row_mask):
                    if bit == "1":
                        px = cursor_x + gx * scale
                        if 0 <= px and px + scale <= width:
                            pos = row_offset + px * 3
                            buf[pos : pos + 3 * scale] = color_px
        cursor_x += 6 * scale


def _draw_wrapped_bitmap_text_rgb(
    buf: bytearray,
    stride: int,
    width: int,
    height: int,
    x: int,
    y: int,
    text: str,
    color: tuple[int, int, int],
    scale: int = 2,
    max_chars: int = 58,
    max_x: int | None = None,
    max_y: int | None = None,
    line_gap: int = 5,
) -> int:
    """Wrap `text` across multiple lines using `textwrap.wrap` and return next Y."""
    wrapped = textwrap.wrap(
        text,
        width=max_chars,
        break_long_words=True,
        break_on_hyphens=False,
    ) or [""]
    line_step = 7 * scale + line_gap
    cursor_y = y
    limit_x = (width - 16) if max_x is None else max_x
    for line in wrapped:
        if max_y is not None and cursor_y + 7 * scale > max_y:
            break
        _draw_bitmap_text_rgb(
            buf,
            stride,
            width,
            height,
            x,
            cursor_y,
            line,
            color,
            scale=scale,
            max_x=limit_x,
        )
        cursor_y += line_step
    return cursor_y


def _poster_field_groups(t: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Split canonical fields into primary breakdown lines and logistics/schedule lines."""
    left_lines = [
        f"ROLE: {t['role']} ({t['role_size']})",
        f"ROLES: {' / '.join(t['candidate_roles'])}",
        f"LOC: {t['location']}",
        f"SPECS: {' / '.join(t['specs'])}",
        f"NOTES: {t['casting_notes'] or 'None'}",
    ]
    right_lines = [
        f"DUE: {t['due_date_text']}",
        f"ORIENTATION: {t['orientation']}",
        f"UNION: {t['union_status'] or 'N/A'}",
        f"PAY: {t['pay_terms'] or 'TBD'}",
        f"CALLBACKS: {t['callback_dates_text'] or 'TBD'}",
        f"SHOOT: {t['shoot_dates_text'] or 'TBD'}",
        f"FILE: {t['file_naming'] or 'Standard'}",
    ]
    return left_lines, right_lines


def render_poster_png_fallback(
    sample: dict[str, Any],
    output_path: Path,
    width: int = DEFAULT_IMAGE_WIDTH,
    height: int = DEFAULT_IMAGE_HEIGHT,
) -> None:
    """Pure-stdlib RGB PNG renderer using `zlib` + `struct` when Pillow is absent."""
    t = sample["target"]
    layout = sample["layout"]

    bg_map: dict[str, tuple[int, int, int]] = {
        "two_column_grid": (246, 244, 239),
        "watermark_clapperboard": (238, 241, 246),
        "low_contrast_footer": (242, 236, 224),
        "regional_multilingual": (252, 245, 232),
        "agency_logo_decoy": (240, 244, 248),
        "gradient_editorial_card": (28, 33, 43),
    }
    bg = bg_map.get(layout, (244, 244, 244))
    is_dark = layout == "gradient_editorial_card"
    fg = (242, 245, 250) if is_dark else (28, 32, 40)
    accent = (214, 92, 52) if layout == "regional_multilingual" else (35, 92, 168)

    stride = 1 + width * 3
    single_row = b"\x00" + bytes(bg) * width
    buf = bytearray(single_row * height)

    # Top header banner
    _fill_rect_rgb(buf, stride, width, height, 0, 0, width, 136, accent)
    _draw_wrapped_bitmap_text_rgb(
        buf,
        stride,
        width,
        height,
        32,
        24,
        f"{t['project']} - {t['project_type']}",
        (255, 255, 255),
        scale=3,
        max_chars=38,
        max_x=width - 24,
        max_y=84,
        line_gap=4,
    )
    _draw_wrapped_bitmap_text_rgb(
        buf,
        stride,
        width,
        height,
        32,
        88,
        f"CASTING: {t['casting_office']}",
        (230, 238, 250),
        scale=2,
        max_chars=58,
        max_x=width - 24,
        max_y=130,
    )

    footer_top = height - 172
    body_y = 160
    left_lines, right_lines = _poster_field_groups(t)

    if layout == "two_column_grid":
        _fill_rect_rgb(buf, stride, width, height, 32, 160, 372, footer_top - 16, (255, 255, 255))
        _fill_rect_rgb(buf, stride, width, height, 396, 160, width - 32, footer_top - 16, (233, 238, 245))
        ly = 178
        for line in left_lines:
            ly = _draw_wrapped_bitmap_text_rgb(
                buf,
                stride,
                width,
                height,
                44,
                ly,
                line,
                fg,
                scale=2,
                max_chars=26,
                max_x=364,
                max_y=footer_top - 24,
                line_gap=4,
            ) + 8
        ry = 178
        for line in right_lines:
            ry = _draw_wrapped_bitmap_text_rgb(
                buf,
                stride,
                width,
                height,
                408,
                ry,
                line,
                fg,
                scale=2,
                max_chars=26,
                max_x=width - 40,
                max_y=footer_top - 24,
                line_gap=4,
            ) + 8
    else:
        if layout == "watermark_clapperboard":
            # Clapperboard diagonal stripes across middle watermark band
            for band in range(8):
                bx = 90 + band * 76
                stripe_color = (210, 214, 222) if band % 2 == 0 else (228, 232, 238)
                _fill_rect_rgb(buf, stride, width, height, bx, 300, bx + 54, 520, stripe_color)
            _draw_bitmap_text_rgb(buf, stride, width, height, 150, 410, "CONFIDENTIAL CASTING", (185, 190, 200), scale=3)
        elif layout == "agency_logo_decoy":
            _fill_rect_rgb(buf, stride, width, height, width - 340, 148, width - 24, 246, (24, 34, 52))
            _draw_wrapped_bitmap_text_rgb(
                buf,
                stride,
                width,
                height,
                width - 326,
                162,
                sample["agency_brand"],
                (255, 215, 110),
                scale=2,
                max_chars=24,
                max_x=width - 32,
                max_y=204,
            )
            _draw_wrapped_bitmap_text_rgb(
                buf,
                stride,
                width,
                height,
                width - 326,
                202,
                sample["decoy_email"],
                (210, 220, 235),
                scale=2,
                max_chars=24,
                max_x=width - 32,
                max_y=242,
            )
            body_y = 262

        cy = body_y
        for line in left_lines + right_lines:
            cy = _draw_wrapped_bitmap_text_rgb(
                buf,
                stride,
                width,
                height,
                36,
                cy,
                line,
                fg,
                scale=2,
                max_chars=58,
                max_x=width - 28,
                max_y=footer_top - 12,
                line_gap=4,
            ) + 6

    # Footer bar (white-on-tan low contrast for `low_contrast_footer`)
    if layout == "low_contrast_footer":
        footer_bg = (212, 186, 150)
        footer_fg = (248, 244, 236)
    else:
        footer_bg = (42, 50, 66)
        footer_fg = (240, 244, 250)

    _fill_rect_rgb(buf, stride, width, height, 0, footer_top, width, height, footer_bg)
    fy = footer_top + 18
    if t["submission_email"]:
        fy = _draw_wrapped_bitmap_text_rgb(
            buf,
            stride,
            width,
            height,
            32,
            fy,
            f"SUBMIT: {t['submission_email']}",
            footer_fg,
            scale=2,
            max_chars=58,
            max_x=width - 24,
            max_y=height - 12,
            line_gap=4,
        ) + 8
    if t["sides_link"]:
        _draw_wrapped_bitmap_text_rgb(
            buf,
            stride,
            width,
            height,
            32,
            fy,
            f"SIDES: {t['sides_link']}",
            footer_fg,
            scale=2,
            max_chars=58,
            max_x=width - 24,
            max_y=height - 10,
            line_gap=4,
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    idat = zlib.compress(bytes(buf), level=1)
    png_bytes = b"".join(
        [
            b"\x89PNG\r\n\x1a\n",
            _png_chunk(b"IHDR", ihdr),
            _png_chunk(b"IDAT", idat),
            _png_chunk(b"IEND", b""),
        ]
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(png_bytes)


def _load_pil_font(size: int = 18, prefer_indic: bool = False) -> Any:  # pragma: no cover
    """Locate a Unicode/Indic TTF font on Linux/Colab or macOS before falling back to Pillow default."""
    indic_candidates = (
        "/usr/share/fonts/truetype/noto/NotoSansDevanagari-Regular.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansGurmukhi-Regular.ttf",
        "/System/Library/Fonts/Kohinoor.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/Library/Fonts/Arial Unicode.ttf",
    )
    general_candidates = (
        "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
    )
    search_order = (indic_candidates + general_candidates) if prefer_indic else (general_candidates + indic_candidates)
    for font_path in search_order:
        if Path(font_path).exists():
            try:
                return ImageFont.truetype(font_path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def _draw_pil_text(draw: Any, xy: tuple[int, int], text: str, fill: tuple[int, int, int], font: Any) -> None:  # pragma: no cover
    """Render UTF-8 text directly when supported by the font, falling back per-character only if needed."""
    try:
        draw.text(xy, text, fill=fill, font=font)
    except UnicodeEncodeError:
        sanitized = "".join(ch if ord(ch) < 256 else "?" for ch in text)
        draw.text(xy, sanitized, fill=fill, font=font)


def _wrap_pil_lines(text: str, max_width_px: int, draw: Any, font: Any) -> list[str]:  # pragma: no cover
    """Wrap text to fit within `max_width_px` using Pillow font metrics when available."""
    words = text.split()
    if not words:
        return [""]
    if not hasattr(draw, "textlength"):
        approx_chars = max(16, max_width_px // 8)
        return textwrap.wrap(text, width=approx_chars, break_long_words=True, break_on_hyphens=False)

    lines: list[str] = []
    current = ""
    for word in words:
        candidate = f"{current} {word}".strip()
        try:
            width_px = draw.textlength(candidate, font=font)
        except UnicodeEncodeError:
            width_px = len(candidate) * 8
        if current and width_px > max_width_px:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def _draw_pil_wrapped_block(
    draw: Any,
    x: int,
    y: int,
    lines: list[str],
    fill: tuple[int, int, int],
    font: Any,
    max_width_px: int,
    max_y: int,
    line_step: int = 22,
    paragraph_gap: int = 8,
) -> int:  # pragma: no cover
    cursor_y = y
    for raw_line in lines:
        for wrapped in _wrap_pil_lines(raw_line, max_width_px=max_width_px, draw=draw, font=font):
            if cursor_y + line_step > max_y:
                return cursor_y
            _draw_pil_text(draw, (x, cursor_y), wrapped, fill=fill, font=font)
            cursor_y += line_step
        cursor_y += paragraph_gap
    return cursor_y


def render_poster_png_pil(
    sample: dict[str, Any],
    output_path: Path,
    width: int = DEFAULT_IMAGE_WIDTH,
    height: int = DEFAULT_IMAGE_HEIGHT,
) -> None:  # pragma: no cover - exercised in Colab with Pillow installed
    """Rich Pillow poster renderer for Google Colab training."""
    t = sample["target"]
    layout = sample["layout"]

    bg = (25, 30, 42) if layout == "gradient_editorial_card" else (246, 244, 239)
    fg = (242, 245, 250) if layout == "gradient_editorial_card" else (26, 30, 38)
    accent = (214, 92, 52) if layout == "regional_multilingual" else (34, 90, 165)

    img = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(img)
    prefer_indic = layout == "regional_multilingual"
    title_font = _load_pil_font(size=24, prefer_indic=prefer_indic)
    body_font = _load_pil_font(size=16, prefer_indic=prefer_indic)
    small_font = _load_pil_font(size=14, prefer_indic=prefer_indic)

    draw.rectangle([0, 0, width, 136], fill=accent)
    _draw_pil_text(draw, (32, 26), f"{t['project']} ({t['project_type']})", fill=(255, 255, 255), font=title_font)
    _draw_pil_text(draw, (32, 78), f"Casting Office: {t['casting_office']}", fill=(230, 238, 250), font=body_font)

    footer_top = height - 172
    left_lines, right_lines = _poster_field_groups(t)

    if layout == "two_column_grid":
        draw.rectangle([28, 164, 372, footer_top - 16], fill=(255, 255, 255), outline=(210, 214, 222))
        draw.rectangle([396, 164, width - 28, footer_top - 16], fill=(234, 239, 246), outline=(204, 212, 224))
        _draw_pil_wrapped_block(
            draw,
            x=40,
            y=180,
            lines=left_lines,
            fill=fg,
            font=body_font,
            max_width_px=324,
            max_y=footer_top - 24,
        )
        _draw_pil_wrapped_block(
            draw,
            x=408,
            y=180,
            lines=right_lines,
            fill=fg,
            font=body_font,
            max_width_px=324,
            max_y=footer_top - 24,
        )
    else:
        body_y = 164
        if layout == "watermark_clapperboard":
            for band in range(8):
                bx = 80 + band * 78
                draw.polygon([(bx, 280), (bx + 44, 280), (bx + 90, 520), (bx + 46, 520)], fill=(220, 224, 232))
            _draw_pil_text(draw, (170, 390), "CLAPPERBOARD WATERMARK // CASTING", fill=(165, 170, 180), font=body_font)
        elif layout == "agency_logo_decoy":
            draw.rectangle([width - 340, 148, width - 28, 244], fill=(24, 34, 52))
            _draw_pil_text(draw, (width - 324, 164), sample["agency_brand"], fill=(255, 215, 110), font=body_font)
            _draw_pil_text(draw, (width - 324, 200), sample["decoy_email"], fill=(210, 220, 235), font=small_font)
            body_y = 262

        _draw_pil_wrapped_block(
            draw,
            x=40,
            y=body_y,
            lines=left_lines + right_lines,
            fill=fg,
            font=body_font,
            max_width_px=width - 80,
            max_y=footer_top - 16,
        )

    if layout == "low_contrast_footer":
        footer_bg = (212, 186, 150)
        footer_fg = (250, 246, 240)
    else:
        footer_bg = (42, 50, 66)
        footer_fg = (240, 244, 250)

    draw.rectangle([0, footer_top, width, height], fill=footer_bg)
    footer_lines: list[str] = []
    if t["submission_email"]:
        footer_lines.append(f"Submit Tapes: {t['submission_email']}")
    if t["sides_link"]:
        footer_lines.append(f"Sides Link: {t['sides_link']}")
    _draw_pil_wrapped_block(
        draw,
        x=32,
        y=footer_top + 18,
        lines=footer_lines,
        fill=footer_fg,
        font=body_font,
        max_width_px=width - 64,
        max_y=height - 12,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(output_path, format="PNG")


def render_poster_png(
    sample: dict[str, Any],
    output_path: Path,
    width: int = DEFAULT_IMAGE_WIDTH,
    height: int = DEFAULT_IMAGE_HEIGHT,
) -> None:
    """Render a 768x960 RGB casting poster PNG using Pillow or stdlib fallback."""
    if HAS_PIL:
        render_poster_png_pil(sample, output_path, width=width, height=height)
    else:
        render_poster_png_fallback(sample, output_path, width=width, height=height)


def _write_split(
    split: str,
    count: int,
    output_dir: Path,
    rng: random.Random,
    image_width: int,
    image_height: int,
    skip_images: bool,
) -> dict[str, Any]:
    vlm_path = output_dir / f"{split}_vlm.jsonl"
    needle_path = output_dir / f"{split}_needle.jsonl"
    layout_counts: dict[str, int] = {name: 0 for name in LAYOUT_VARIANTS}
    max_words = 0
    max_tokens = 0

    with vlm_path.open("w", encoding="utf-8") as vlm_f, needle_path.open("w", encoding="utf-8") as needle_f:
        for idx in range(count):
            layout = LAYOUT_VARIANTS[idx % len(LAYOUT_VARIANTS)]
            layout_counts[layout] += 1

            sample = build_notice_sample(idx, split=split, layout=layout, rng=rng)
            target = sample["target"]
            target_json = json.dumps(target, ensure_ascii=False)
            record_id = f"{split}-{idx:05d}"

            severity = 0.55 if split == "eval" else 0.30
            needle_text, tags = render_notice_text(sample, rng=rng, severity=severity)
            word_count = len(needle_text.split())
            est_tokens = estimate_token_count(needle_text)
            if word_count > MAX_NEEDLE_WORDS or est_tokens > MAX_NEEDLE_TOKENS:
                raise ValueError(
                    f"Record {record_id} exceeded Needle budget: words={word_count}, tokens={est_tokens}"
                )
            max_words = max(max_words, word_count)
            max_tokens = max(max_tokens, est_tokens)

            rel_image = Path("images") / split / f"poster_{idx:05d}.png"
            if not skip_images:
                render_poster_png(
                    sample,
                    output_dir / rel_image,
                    width=image_width,
                    height=image_height,
                )

            vlm_row = {
                "id": record_id,
                "split": split,
                "layout": layout,
                "image": rel_image.as_posix(),
                "image_width": image_width,
                "image_height": image_height,
                "messages": [
                    {"role": "system", "content": VLM_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": "Extract the 18-key SemanticNoticePayload JSON from this casting poster image.",
                    },
                    {"role": "assistant", "content": target_json},
                ],
                "ocr_text": needle_text,
                "target": target,
                "metadata": {
                    "adversarial_tags": tags,
                    "renderer": "pillow" if HAS_PIL else "stdlib_png",
                },
            }
            needle_row = {
                "id": record_id,
                "split": split,
                "layout": layout,
                "messages": [
                    {"role": "system", "content": NEEDLE_SYSTEM_PROMPT},
                    {
                        "role": "user",
                        "content": f"Extract the 18-key SemanticNoticePayload JSON from this casting notice:\n\n{needle_text}",
                    },
                    {"role": "assistant", "content": target_json},
                ],
                "text": needle_text,
                "target": target,
                "metadata": {
                    "word_count": word_count,
                    "estimated_tokens": est_tokens,
                    "adversarial_tags": tags,
                },
            }

            vlm_f.write(json.dumps(vlm_row, ensure_ascii=False) + "\n")
            needle_f.write(json.dumps(needle_row, ensure_ascii=False) + "\n")

    return {
        "count": count,
        "vlm_jsonl": str(vlm_path),
        "needle_jsonl": str(needle_path),
        "layout_counts": layout_counts,
        "max_needle_words": max_words,
        "max_needle_tokens": max_tokens,
    }


def build_corpus(
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    train_count: int = 5000,
    eval_count: int = 500,
    seed: int = 42,
    image_width: int = DEFAULT_IMAGE_WIDTH,
    image_height: int = DEFAULT_IMAGE_HEIGHT,
    skip_images: bool = False,
) -> dict[str, Any]:
    """Build train/eval VLM and Needle 3 JSONL files + 768x960 poster PNGs."""
    output_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)

    train_stats = _write_split(
        split="train",
        count=train_count,
        output_dir=output_dir,
        rng=rng,
        image_width=image_width,
        image_height=image_height,
        skip_images=skip_images,
    )
    eval_stats = _write_split(
        split="eval",
        count=eval_count,
        output_dir=output_dir,
        rng=rng,
        image_width=image_width,
        image_height=image_height,
        skip_images=skip_images,
    )

    summary: dict[str, Any] = {
        "output_dir": str(output_dir),
        "train_count": train_count,
        "eval_count": eval_count,
        "image_dimensions": [image_width, image_height],
        "renderer": "pillow" if HAS_PIL else "stdlib_png",
        "canonical_keys": list(CANONICAL_SCHEMA_KEYS),
        "repo_fixtures": inspect_repo_fixtures(),
        "train": train_stats,
        "eval": eval_stats,
    }
    manifest_path = output_dir / "corpus_manifest.json"
    manifest_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--train-count", type=int, default=5000)
    parser.add_argument("--eval-count", type=int, default=500)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--image-width", type=int, default=DEFAULT_IMAGE_WIDTH)
    parser.add_argument("--image-height", type=int, default=DEFAULT_IMAGE_HEIGHT)
    parser.add_argument(
        "--skip-images",
        action="store_true",
        help="Skip rendering PNG files (JSONL metadata still references image paths).",
    )
    args = parser.parse_args(argv)

    summary = build_corpus(
        output_dir=args.output_dir,
        train_count=args.train_count,
        eval_count=args.eval_count,
        seed=args.seed,
        image_width=args.image_width,
        image_height=args.image_height,
        skip_images=args.skip_images,
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
