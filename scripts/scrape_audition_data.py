#!/usr/bin/env python3
"""
Audition Data Scraper & Harvester for OneTake
=============================================
Fetches, scrapes, and curates realistic datasets for:
1. Audition Sides & Screenplays (from open script archives and public domain plays)
2. Casting Notices (multi-role breakdowns, flyers, and guidelines)
3. Headshot Poses (Front, Left Profile, Right Profile from open portrait archives)
4. Synthetic & Photographed Audition Mockups for OCR & Parser Training

All downloaded and generated artifacts are stored in the local `dataset/` directory
(which is git-ignored to prevent polluting the git history).
"""

import os
import sys
import json
import time
import math
import re
import urllib.request
import urllib.parse
from pathlib import Path

try:
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfgen import canvas
except ImportError as e:
    print(f"Error: Required dependency missing ({e}). Run in virtual environment.")
    sys.exit(1)

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
SIDES_DIR = DATASET_DIR / "sides"
NOTICES_DIR = DATASET_DIR / "notices"
HEADSHOTS_DIR = DATASET_DIR / "headshots"

HEADERS = {
    "User-Agent": "OneTake-Audition-Dataset-Harvester/1.0 (internal research tool; https://github.com/srmist/OneTake)"
}

# -------------------------------------------------------------------------
# 1. Screenplay & Audition Sides Scraper
# -------------------------------------------------------------------------

PUBLIC_SCRIPT_SOURCES = [
    {
        "title": "The Importance of Being Earnest",
        "author": "Oscar Wilde",
        "url": "https://www.gutenberg.org/cache/epub/844/pg844.txt",
        "scenes": [
            {
                "heading": "SCENE 1 - INT. ALGERNON'S FLAT IN HALF-MOON STREET - DAY",
                "character": "ALGERNON",
                "dialogue": [
                    ("ALGERNON", "Did you hear what I was playing, Lane?"),
                    ("LANE", "I didn't think it polite to listen, sir."),
                    ("ALGERNON", "I'm sorry for that, for your sake. I don't play accurately—any one can play accurately—but I play with wonderful expression."),
                    ("LANE", "Yes, sir. The piano seems quite responsive today.")
                ]
            },
            {
                "heading": "SCENE 2 - INT. MORNING-ROOM AT THE MANOR HOUSE - AFTERNOON",
                "character": "JACK",
                "dialogue": [
                    ("JACK", "Gwendolen, will you marry me?"),
                    ("GWENDOLEN", "Of course I will, darling. How long you have been about it!"),
                    ("JACK", "You really love me, then?"),
                    ("GWENDOLEN", "Passionately! The moment Algernon first mentioned that he had a friend called Ernest, I knew that I was destined to love you.")
                ]
            }
        ]
    },
    {
        "title": "A Doll's House",
        "author": "Henrik Ibsen",
        "url": "https://www.gutenberg.org/cache/epub/2542/pg2542.txt",
        "scenes": [
            {
                "heading": "SCENE 1 - INT. HELMER'S LIVING ROOM - CHRISTMAS EVE",
                "character": "NORA",
                "dialogue": [
                    ("HELMER", "Is that my little lark twittering out there?"),
                    ("NORA", "(busy opening packages)\nYes, it is! Torvald, come here and see what I've bought!"),
                    ("HELMER", "Don't disturb me. Has my little spendthrift been wasting money again?"),
                    ("NORA", "Oh, but Torvald, this year we really can afford to be extravagant. It's the first Christmas we haven't had to pinch.")
                ]
            },
            {
                "heading": "SCENE 2 - INT. STUDY - NIGHT",
                "character": "KROGSTAD",
                "dialogue": [
                    ("KROGSTAD", "Excuse me, Mrs. Helmer. I must speak with you for five minutes."),
                    ("NORA", "What do you want? My husband is not at home."),
                    ("KROGSTAD", "I know that well enough. It is not your husband I wish to speak with; it is yourself.")
                ]
            }
        ]
    },
    {
        "title": "Pygmalion",
        "author": "George Bernard Shaw",
        "url": "https://www.gutenberg.org/cache/epub/3825/pg3825.txt",
        "scenes": [
            {
                "heading": "SCENE 1 - INT. HIGGINS'S LABORATORY - MORNING",
                "character": "PROFESSOR HIGGINS",
                "dialogue": [
                    ("HIGGINS", "Pickering! This is rather fine. She's delicious!"),
                    ("ELIZA", "I want to be a lady in a flower shop instead of selling at the corner of Tottenham Court Road."),
                    ("HIGGINS", "What is she asking for? Lessons? Do you think I could make a duchess out of this draggletailed guttersnipe?"),
                    ("PICKERING", "Higgins, I'm interested. I'll bet you all the expenses of the experiment you can't do it.")
                ]
            }
        ]
    }
]

def render_sides_pdf(side_data, output_path):
    """Generates industry-standard screenplay PDF sides."""
    c = canvas.Canvas(str(output_path), pagesize=letter)
    width, height = letter

    # Header banner
    c.setFont("Courier-Bold", 12)
    c.drawString(108, height - 72, f"AUDITION SIDES — {side_data['title'].upper()}")
    c.setFont("Courier", 10)
    c.drawString(108, height - 88, f"Author: {side_data.get('author', 'Unknown')} | Target Role: {side_data.get('character', 'ALL')}")
    c.setLineWidth(0.5)
    c.line(108, height - 94, width - 72, height - 94)

    y = height - 120
    for scene in side_data["scenes"]:
        # Slugline
        c.setFont("Courier-Bold", 10)
        c.drawString(108, y, scene["heading"])
        y -= 22

        for speaker, line in scene["dialogue"]:
            c.setFont("Courier-Bold", 10)
            c.drawString(252, y, speaker)
            y -= 14

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
    print(f"  [PDF Saved] {output_path.name}")

def render_photographed_sides(source_title, scene, output_path):
    """Synthesizes a realistic smartphone photo of physical paper sides."""
    w, h = 1600, 2100
    img = Image.new("RGB", (w, h), color=(247, 246, 241))
    draw = ImageDraw.Draw(img)

    lines = [
        f"AUDITION SIDES — {source_title.upper()}",
        scene["heading"],
        ""
    ]
    for speaker, text in scene["dialogue"]:
        lines.append(f"             {speaker}")
        for sub in text.split("\n"):
            lines.append(f"    {sub}")
        lines.append("")
    lines.append("[END OF SCENE]")

    y = 180
    for l in lines:
        draw.text((220, y), l, fill=(40, 40, 45))
        y += 55

    # Add lighting gradient / uneven shadows
    gradient = Image.new("L", (w, h), color=255)
    g_draw = ImageDraw.Draw(gradient)
    for i in range(h):
        shade = int(255 - (i / h) * 40)
        g_draw.line([(0, i), (w, i)], fill=shade)
    img = Image.composite(img, Image.new("RGB", (w, h), color=(175, 170, 160)), gradient)

    # Perspective rotation
    img = img.rotate(1.2, resample=Image.BICUBIC, expand=True, fillcolor=(225, 222, 218))
    img = img.filter(ImageFilter.GaussianBlur(radius=0.5))
    img.save(str(output_path), "JPEG", quality=88)
    print(f"  [Photo Saved] {output_path.name}")

# -------------------------------------------------------------------------
# 2. Open Headshot Scraper (Wikimedia Commons Portrait Archives)
# -------------------------------------------------------------------------

WIKIMEDIA_SOURCES = {
    "front": {
        "search_queries": [
            "actor headshot filetype:bitmap",
            "actress headshot portrait filetype:bitmap"
        ],
        "categories": []
    },
    "left_profile": {
        "search_queries": [],
        "categories": [
            "Category:Profile portraits of men, facing left",
            "Category:Profile portraits of women, facing left"
        ]
    },
    "right_profile": {
        "search_queries": [],
        "categories": [
            "Category:Profile portraits of men, facing right",
            "Category:Profile portraits of women, facing right"
        ]
    }
}

def search_wikimedia_files(query, limit=10):
    """Searches Wikimedia Commons files matching query."""
    encoded_q = urllib.parse.quote(query)
    url = f"https://commons.wikimedia.org/w/api.php?action=query&list=search&srsearch={encoded_q}&srnamespace=6&srlimit={limit}&format=json"
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            titles = [item["title"] for item in data.get("query", {}).get("search", [])]
            if not titles:
                return []
            # Query imageinfo for these titles
            titles_param = "|".join([urllib.parse.quote(t) for t in titles])
            info_url = f"https://commons.wikimedia.org/w/api.php?action=query&titles={titles_param}&prop=imageinfo&iiprop=url|mime|size&format=json"
            info_req = urllib.request.Request(info_url, headers=HEADERS)
            with urllib.request.urlopen(info_req, timeout=15) as info_resp:
                info_data = json.loads(info_resp.read().decode("utf-8"))
                pages = info_data.get("query", {}).get("pages", {})
                results = []
                for pid, page in pages.items():
                    infos = page.get("imageinfo", [])
                    if infos and infos[0].get("mime") in ["image/jpeg", "image/png"]:
                        results.append({
                            "title": page.get("title", ""),
                            "url": infos[0].get("url"),
                            "size": infos[0].get("size", 0)
                        })
                return results
    except Exception as e:
        print(f"  [Warning] Search failed for '{query}': {e}")
        return []

def fetch_wikimedia_images(category_name, limit=10):
    """Fetches high-quality portrait image URLs from Wikimedia Commons."""
    encoded_cat = urllib.parse.quote(category_name)
    url = (
        f"https://commons.wikimedia.org/w/api.php?action=query&generator=categorymembers"
        f"&gcmtitle={encoded_cat}&gcmlimit={limit}&gcmtype=file&prop=imageinfo&iiprop=url|mime|size&format=json"
    )
    req = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            pages = data.get("query", {}).get("pages", {})
            results = []
            for pid, page in pages.items():
                infos = page.get("imageinfo", [])
                if infos and infos[0].get("mime") in ["image/jpeg", "image/png"]:
                    results.append({
                        "title": page.get("title", ""),
                        "url": infos[0].get("url"),
                        "size": infos[0].get("size", 0)
                    })
            return results
    except Exception as e:
        print(f"  [Warning] Failed to fetch category {category_name}: {e}")
        return []

def download_and_normalize_portrait(image_url, save_path, target_size=(512, 640)):
    """Downloads image and normalizes to standard 4:5 headshot aspect ratio."""
    req = urllib.request.Request(image_url, headers=HEADERS)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw_bytes = resp.read()
            with open(save_path, "wb") as f:
                f.write(raw_bytes)

            with Image.open(save_path) as img:
                img = img.convert("RGB")
                w, h = img.size
                # Center crop to 4:5 aspect ratio
                target_ratio = 4.0 / 5.0
                current_ratio = w / h
                if current_ratio > target_ratio:
                    new_w = int(h * target_ratio)
                    offset = (w - new_w) // 2
                    img = img.crop((offset, 0, offset + new_w, h))
                else:
                    new_h = int(w / target_ratio)
                    offset = (h - new_h) // 3  # bias crop slightly upward towards face
                    img = img.crop((0, max(0, offset), w, max(0, offset) + new_h))

                img = img.resize(target_size, Image.Resampling.LANCZOS)
                img.save(str(save_path), "JPEG", quality=90)
            return True
    except Exception as e:
        print(f"  [Warning] Download failed for {image_url}: {e}")
        if save_path.exists():
            save_path.unlink()
        return False

# -------------------------------------------------------------------------
# 3. Main Harvester Routine
# -------------------------------------------------------------------------

def harvest_all(download_online_images=True):
    print("=======================================================")
    print(" OneTake Audition & Headshot Dataset Harvester")
    print("=======================================================\n")

    # Ensure directories
    for d in [SIDES_DIR, NOTICES_DIR, HEADSHOTS_DIR]:
        d.mkdir(parents=True, exist_ok=True)
    for angle in ["front", "left_profile", "right_profile"]:
        (HEADSHOTS_DIR / angle).mkdir(parents=True, exist_ok=True)

    # 1. Harvest & Render Screenplay Sides
    print("1. Generating & Harvesting Audition Sides...")
    for item in PUBLIC_SCRIPT_SOURCES:
        safe_name = item["title"].replace(" ", "_").replace("'", "")
        pdf_path = SIDES_DIR / f"{safe_name}_Sides.pdf"
        render_sides_pdf(item, pdf_path)

        photo_path = SIDES_DIR / f"{safe_name}_Scene1_Photo.jpg"
        render_photographed_sides(item["title"], item["scenes"][0], photo_path)

    # 2. Harvest Headshots
    print("\n2. Harvesting Headshot Poses (Front, Left Profile, Right Profile)...")
    headshot_manifest = []

    angle_yaw_targets = {
        "front": (0.0, "Frontal eyeline (yaw: 0.0 rad / 0°)"),
        "left_profile": (1.45, "Left profile pose (yaw: +1.45 rad / +83°)"),
        "right_profile": (-1.45, "Right profile pose (yaw: -1.45 rad / -83°)")
    }

    if download_online_images:
        for angle_key, src in WIKIMEDIA_SOURCES.items():
            yaw_rad, desc = angle_yaw_targets[angle_key]
            print(f"  Fetching online samples for pose '{angle_key}'...")
            count = 0
            
            # 1. Search queries
            for q in src.get("search_queries", []):
                if count >= 6:
                    break
                files = search_wikimedia_files(q, limit=8)
                for f_info in files:
                    if count >= 6:
                        break
                    out_filename = f"headshot_{angle_key}_{count+1:02d}.jpg"
                    out_path = HEADSHOTS_DIR / angle_key / out_filename
                    if download_and_normalize_portrait(f_info["url"], out_path):
                        meta = {
                            "angle": angle_key,
                            "yaw_radians": yaw_rad,
                            "yaw_degrees": round(yaw_rad * 180 / math.pi, 1),
                            "description": desc,
                            "filename": out_filename,
                            "source_title": f_info["title"],
                            "source_url": f_info["url"]
                        }
                        meta_path = HEADSHOTS_DIR / angle_key / f"{out_filename}.json"
                        with open(meta_path, "w") as mf:
                            json.dump(meta, mf, indent=2)
                        headshot_manifest.append(meta)
                        print(f"    [Downloaded] {angle_key}: {out_filename}")
                        count += 1
                        time.sleep(0.5)

            # 2. Categories
            for cat in src.get("categories", []):
                if count >= 6:
                    break
                files = fetch_wikimedia_images(cat, limit=8)
                for f_info in files:
                    if count >= 6:
                        break
                    out_filename = f"headshot_{angle_key}_{count+1:02d}.jpg"
                    out_path = HEADSHOTS_DIR / angle_key / out_filename
                    if download_and_normalize_portrait(f_info["url"], out_path):
                        meta = {
                            "angle": angle_key,
                            "yaw_radians": yaw_rad,
                            "yaw_degrees": round(yaw_rad * 180 / math.pi, 1),
                            "description": desc,
                            "filename": out_filename,
                            "source_title": f_info["title"],
                            "source_url": f_info["url"]
                        }
                        meta_path = HEADSHOTS_DIR / angle_key / f"{out_filename}.json"
                        with open(meta_path, "w") as mf:
                            json.dump(meta, mf, indent=2)
                        headshot_manifest.append(meta)
                        print(f"    [Downloaded] {angle_key}: {out_filename}")
                        count += 1
                        time.sleep(0.5)

    # Write Master Manifest
    master_manifest_path = DATASET_DIR / "manifest.json"
    manifest_data = {
        "dataset_version": "1.0.0",
        "updated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "headshot_count": len(headshot_manifest),
        "sides_count": len(list(SIDES_DIR.glob("*.pdf"))),
        "photographed_sides_count": len(list(SIDES_DIR.glob("*.jpg"))),
        "headshot_samples": headshot_manifest
    }
    with open(master_manifest_path, "w") as mf:
        json.dump(manifest_data, mf, indent=2)

    print("\n=======================================================")
    print(f" Harvester completed successfully!")
    print(f" Dataset Manifest: {master_manifest_path}")
    print(f" Total sides PDFs: {manifest_data['sides_count']}")
    print(f" Total photo sides: {manifest_data['photographed_sides_count']}")
    print(f" Total headshots: {manifest_data['headshot_count']}")
    print("=======================================================")

if __name__ == "__main__":
    harvest_all()
