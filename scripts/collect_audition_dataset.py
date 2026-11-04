#!/usr/bin/env python3
"""
Audition & Headshot Dataset Collector for OneTake
=================================================
Automates collection and generation of:
1. Audition sides (PDFs & text files with Courier screenplay formatting).
2. Photographed script pages (augmented with skew, lighting shadows, and mobile camera noise).
3. Casting call notices (flyers, breakdowns, multi-role packets).
4. Headshot pose datasets (Front, Left Profile, Right Profile) with ground-truth yaw angles.
"""

import os
import sys
import json
import math
import random
import argparse
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas
except ImportError as e:
    print(f"Missing dependency: {e}. Run in the virtual environment: scripts/.venv/bin/python")
    sys.exit(1)

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
SIDES_DIR = DATASET_DIR / "sides"
NOTICES_DIR = DATASET_DIR / "notices"
HEADSHOTS_DIR = DATASET_DIR / "headshots"

# Realistic Sample Casting Notices for Training/Evaluation
SAMPLE_NOTICES = [
    {
        "project": "Shadows of Manhattan",
        "project_type": "Feature Film",
        "roles": ["Detective Miller", "Sarah Cole", "Julian Vance"],
        "due_date": "November 25, 2026",
        "deadline_raw": "Submission Deadline: November 25, 2026 by 6:00 PM EST",
        "specs": "Landscape / horizontal framing only. Slate at the start (Name, Location, Height).",
        "email": "casting@shadowsmanhattan.com",
        "office": "Bespoke Casting NYC"
    },
    {
        "project": "The Quiet Horizon",
        "project_type": "Independent Feature",
        "roles": ["Elena Gomez", "Dr. Marcus Brody"],
        "due_date": "December 2, 2026",
        "deadline_raw": "Tapes Due: Dec 2, 2026",
        "specs": "1080p MP4 or MOV. Include full slate + both scenes in order.",
        "email": "submissions@quiethorizonfilm.org",
        "office": ""
    },
    {
        "project": "Crossroads Chronicle",
        "project_type": "Mini-Series",
        "roles": ["Father Thomas", "Maya Lin", "Officer Davies", "Amir Khan"],
        "due_date": "October 30, 2026",
        "deadline_raw": "Submit by October 30, 2026",
        "specs": "Horizontal orientation. Max file size 500MB.",
        "email": "tapes@crossroads-series.com",
        "office": "Apex Casting Worldwide"
    }
]

# Realistic Multi-Scene Audition Sides
SAMPLE_SIDES = [
    {
        "filename": "Shadows_Of_Manhattan_Miller_Sides.pdf",
        "project": "Shadows of Manhattan",
        "character": "DETECTIVE MILLER",
        "scenes": [
            {
                "heading": "SCENE 1 - INT. PRECINCT INTERROGATION ROOM - NIGHT",
                "dialogue": [
                    ("DETECTIVE MILLER", "Sit down, Julian. We've got camera footage from 47th Street."),
                    ("JULIAN", "You don't have anything that holds up in court, Miller."),
                    ("DETECTIVE MILLER", "(leaning in, steady)\nThe watchman identified your coat. You've got five minutes before the DA walks in here.")
                ]
            },
            {
                "heading": "SCENE 2 - EXT. ALLEYWAY - DAWN",
                "dialogue": [
                    ("DETECTIVE MILLER", "Don't run! Hands where I can see them!"),
                    ("SARAH", "Miller, drop the weapon! He's unarmed!"),
                    ("DETECTIVE MILLER", "Step aside, Sarah. He isn't walking out of here this time.")
                ]
            }
        ]
    },
    {
        "filename": "Quiet_Horizon_Elena_Sides.pdf",
        "project": "The Quiet Horizon",
        "character": "ELENA GOMEZ",
        "scenes": [
            {
                "heading": "SCENE 1 - INT. HOSPITAL OBSERVATORY - DUSK",
                "dialogue": [
                    ("ELENA GOMEZ", "The readouts don't make sense, Marcus. Look at the orbital fluctuation."),
                    ("DR. MARCUS", "Could be sensor calibration error."),
                    ("ELENA GOMEZ", "(whispering)\nIt's not calibration. It happened twice before the transmission went dark.")
                ]
            }
        ]
    }
]

def init_directories():
    """Ensure dataset directories exist."""
    for d in [SIDES_DIR, NOTICES_DIR, HEADSHOTS_DIR]:
        d.mkdir(parents=True, exist_ok=True)
    for angle in ["front", "left_profile", "right_profile"]:
        (HEADSHOTS_DIR / angle).mkdir(parents=True, exist_ok=True)
    print(f" Dataset structure initialized under: {DATASET_DIR}")

def generate_screenplay_pdf(sides_def, output_path):
    """Generates an industry-standard Courier screenplay sides PDF."""
    c = canvas.Canvas(str(output_path), pagesize=letter)
    width, height = letter

    # Standard Hollywood Screenplay Geometry (Points)
    # Left margin: 1.5 in (108 pt), Top margin: 1.0 in (72 pt)
    c.setFont("Courier-Bold", 12)
    c.drawString(108, height - 72, f"AUDITION SIDES — {sides_def['project'].upper()}")
    c.setFont("Courier", 10)
    c.drawString(108, height - 88, f"Character: {sides_def['character']}")
    c.setLineWidth(0.5)
    c.line(108, height - 94, width - 72, height - 94)

    y = height - 120
    for scene in sides_def["scenes"]:
        # Scene Slugline
        c.setFont("Courier-Bold", 10)
        c.drawString(108, y, scene["heading"])
        y -= 22

        for speaker, line in scene["dialogue"]:
            # Character Cue (centered around 270 pt)
            c.setFont("Courier-Bold", 10)
            c.drawString(252, y, speaker)
            y -= 14

            # Dialogue lines (indented 180 pt to 430 pt)
            c.setFont("Courier", 10)
            for part in line.split("\n"):
                c.drawString(180, y, part)
                y -= 14
            y -= 8

            if y < 100:
                c.showPage()
                y = height - 72

        y -= 16

    c.save()
    print(f" Generated PDF sides: {output_path.name}")

def generate_augmented_photo(source_pdf_path, output_image_path):
    """
    Renders screenplay page into a simulated mobile camera photograph:
    adds perspective tilt, paper texture gradient, shadow falloff, and slight lens blur.
    """
    # Create high-res white page
    page_w, page_h = 1650, 2200
    img = Image.new("RGB", (page_w, page_h), color=(248, 247, 244))
    draw = ImageDraw.Draw(img)

    # Simulated script typography
    text_lines = [
        "AUDITION SIDES — SCENE 1",
        "INT. WAREHOUSE - NIGHT",
        "",
        "             DETECTIVE MILLER",
        "    The door was unlocked when you got here?",
        "",
        "             JULIAN",
        "    I told you three times already.",
        "",
        "             DETECTIVE MILLER",
        "    (stepping forward)",
        "    Then tell me a fourth time, and make it match.",
        "",
        "[END OF SIDE]"
    ]

    y = 200
    for line in text_lines:
        draw.text((220, y), line, fill=(35, 35, 40))
        y += 60

    # Add lighting gradient / shadow falloff
    gradient = Image.new("L", (page_w, page_h), color=255)
    g_draw = ImageDraw.Draw(gradient)
    for i in range(page_h):
        shade = int(255 - (i / page_h) * 45)
        g_draw.line([(0, i), (page_w, i)], fill=shade)
    
    img = Image.composite(img, Image.new("RGB", (page_w, page_h), color=(180, 175, 170)), gradient)

    # Slight rotation / perspective tilt (simulating hand-held phone camera)
    img = img.rotate(random.uniform(-1.5, 1.5), resample=Image.BICUBIC, expand=True, fillcolor=(230, 228, 224))
    # Subtle blur
    img = img.filter(ImageFilter.GaussianBlur(radius=0.4))

    img.save(str(output_image_path), "JPEG", quality=90)
    print(f" Generated photographed script mock: {output_image_path.name}")

def generate_casting_flyer(notice_def, output_path):
    """Renders a realistic social/online casting call flyer graphic."""
    w, h = 1080, 1350
    img = Image.new("RGB", (w, h), color=(18, 18, 22))
    draw = ImageDraw.Draw(img)

    # Header Accent bar
    draw.rectangle([(0, 0), (w, 16)], fill=(224, 76, 56))

    # Badge
    draw.rounded_rectangle([(60, 50), (320, 95)], radius=12, fill=(40, 40, 48), outline=(60, 60, 72))
    draw.text((80, 62), "OFFICIAL CASTING CALL", fill=(224, 76, 56))

    # Project Title & Type
    draw.text((60, 120), notice_def["project"], fill=(255, 255, 255))
    draw.text((60, 190), f"Format: {notice_def['project_type']}", fill=(180, 180, 195))

    # Divider
    draw.line([(60, 250), (w - 60, 250)], fill=(50, 50, 60), width=2)

    # Roles section
    draw.text((60, 280), "CHARACTER BREAKDOWNS", fill=(255, 255, 255))
    y = 330
    for role in notice_def["roles"]:
        draw.text((80, y), f"• {role}", fill=(220, 220, 230))
        y += 45

    # Submission & Deadline
    y += 40
    draw.text((60, y), "SUBMISSION GUIDELINES", fill=(255, 255, 255))
    y += 50
    draw.text((80, y), notice_def["deadline_raw"], fill=(255, 180, 80))
    y += 50
    draw.text((80, y), f"Specifications: {notice_def['specs']}", fill=(180, 180, 195))
    y += 50
    draw.text((80, y), f"Contact: {notice_def['email']}", fill=(100, 180, 255))
    if notice_def["office"]:
        y += 50
        draw.text((80, y), f"Casting Office: {notice_def['office']}", fill=(160, 160, 170))

    img.save(str(output_path), "JPEG", quality=92)
    print(f" Generated casting flyer: {output_path.name}")

def generate_headshot_pose_samples():
    """
    Synthesizes normalized headshot samples across the 3 target yaw poses:
    1. Front (0° yaw)
    2. Left Profile (+90° yaw)
    3. Right Profile (-90° yaw)
    Includes ground-truth JSON metadata for model training and verification.
    """
    w, h = 512, 640
    poses = [
        ("front", 0.0, "Direct front-facing eye line, square shoulders"),
        ("left_profile", 1.45, "Head turned 90 degrees left, side silhouette visible"),
        ("right_profile", -1.45, "Head turned 90 degrees right, side silhouette visible")
    ]

    for angle_key, yaw_radians, description in poses:
        img = Image.new("RGB", (w, h), color=(30, 32, 38))
        draw = ImageDraw.Draw(img)

        # Studio softbox backdrop gradient
        for i in range(h):
            shade = int(32 + (i / h) * 16)
            draw.line([(0, i), (w, i)], fill=(shade, shade, shade + 6))

        # Face outline representation based on yaw angle
        center_x = w // 2
        center_y = h // 2 - 30

        if angle_key == "front":
            # Oval symmetrical head
            draw.ellipse([(center_x - 110, center_y - 140), (center_x + 110, center_y + 140)], fill=(80, 85, 95), outline=(140, 145, 160), width=3)
            # Eyes line
            draw.line([(center_x - 60, center_y - 20), (center_x - 20, center_y - 20)], fill=(200, 205, 215), width=4)
            draw.line([(center_x + 20, center_y - 20), (center_x + 60, center_y - 20)], fill=(200, 205, 215), width=4)
            # Nose & Mouth
            draw.line([(center_x, center_y - 10), (center_x, center_y + 30)], fill=(160, 165, 175), width=3)
            draw.line([(center_x - 30, center_y + 60), (center_x + 30, center_y + 60)], fill=(180, 185, 195), width=3)
        elif angle_key == "left_profile":
            # Left profile silhouette (shifted right facing left)
            draw.polygon([
                (center_x + 50, center_y - 140),
                (center_x - 70, center_y - 40),
                (center_x - 100, center_y - 10),  # Nose
                (center_x - 60, center_y + 20),
                (center_x - 80, center_y + 50),   # Chin
                (center_x + 40, center_y + 130),
                (center_x + 90, center_y)
            ], fill=(80, 85, 95), outline=(140, 145, 160))
        else: # right profile
            # Right profile silhouette (shifted left facing right)
            draw.polygon([
                (center_x - 50, center_y - 140),
                (center_x + 70, center_y - 40),
                (center_x + 100, center_y - 10),  # Nose
                (center_x + 60, center_y + 20),
                (center_x + 80, center_y + 50),   # Chin
                (center_x - 40, center_y + 130),
                (center_x - 90, center_y)
            ], fill=(80, 85, 95), outline=(140, 145, 160))

        target_file = HEADSHOTS_DIR / angle_key / f"sample_{angle_key}_01.jpg"
        img.save(str(target_file), "JPEG", quality=92)

        meta = {
            "angle": angle_key,
            "yaw_radians": yaw_radians,
            "yaw_degrees": round(yaw_radians * 180 / math.pi, 1),
            "description": description,
            "filename": target_file.name
        }
        meta_file = HEADSHOTS_DIR / angle_key / f"sample_{angle_key}_01.json"
        with open(meta_file, "w") as f:
            json.dump(meta, f, indent=2)

        print(f" Generated {angle_key} headshot: {target_file.name} (yaw: {meta['yaw_degrees']}°)")

def main():
    parser = argparse.ArgumentParser(description="Collect and generate audition & headshot training datasets.")
    parser.add_argument("--all", action="store_true", help="Generate complete dataset corpus")
    parser.add_argument("--sides", action="store_true", help="Generate audition sides PDFs and photo mocks")
    parser.add_argument("--notices", action="store_true", help="Generate casting notices and flyers")
    parser.add_argument("--headshots", action="store_true", help="Generate headshot pose samples")
    args = parser.parse_args()

    run_all = args.all or (not args.sides and not args.notices and not args.headshots)

    init_directories()

    if run_all or args.sides:
        for side in SAMPLE_SIDES:
            pdf_path = SIDES_DIR / side["filename"]
            generate_screenplay_pdf(side, pdf_path)
            photo_path = SIDES_DIR / f"{pdf_path.stem}_photographed.jpg"
            generate_augmented_photo(pdf_path, photo_path)

    if run_all or args.notices:
        for idx, notice in enumerate(SAMPLE_NOTICES):
            filename = f"notice_{idx+1}_{notice['project'].replace(' ', '_').lower()}.jpg"
            generate_casting_flyer(notice, NOTICES_DIR / filename)

    if run_all or args.headshots:
        generate_headshot_pose_samples()

    print("\n Dataset collection & generation complete!")
    print(f"Sides location:     {SIDES_DIR}")
    print(f"Notices location:   {NOTICES_DIR}")
    print(f"Headshots location: {HEADSHOTS_DIR}")

if __name__ == "__main__":
    main()
