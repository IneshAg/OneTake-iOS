#!/usr/bin/env python3
"""
OneTake Scraped Instagram Notice Ingestion Script
=================================================
Processes scraped real-world Instagram casting notices from @24x7auditionupdates
and @casting_updates.
Performs OCR via Tesseract, structures the noisy text into OneTake's exact NoticeParser.Draft
JSON format, and enriches the instruction fine-tuning dataset (parsing_dataset_train.jsonl).
"""

import os
import glob
import json
import re
from pathlib import Path
from PIL import Image
import pytesseract

pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
NOTICES_DIR = DATASET_DIR / "notices" / "instagram"
TRAIN_FILE = DATASET_DIR / "parsing_dataset_train.jsonl"

SYSTEM_PROMPT_NOTICE = """You are OneTake's audition notice parser.
Extract the casting details from the provided text into JSON:
{
  "project": "Title",
  "project_type": "Feature Film / TV Episodic / Short Film / Commercial / Theater",
  "role": "Target Character Name",
  "candidate_roles": ["Role 1", "Role 2"],
  "role_size": "Lead / Supporting / Series Regular / Co-Star",
  "casting_office": "Casting Director / Agency",
  "due_date": "ISO8601 string or null",
  "specs": ["Framing", "Slate", "Specs"],
  "sides_link": "URL or null",
  "submission_email": "email or null",
  "director_guidance": "Notes on character or tone"
}
Output valid JSON only."""

def clean_ocr(text: str) -> str:
    # Remove weird non-ascii garbage while keeping useful punctuation
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]', '', text)
    return text.strip()

def parse_notice_fields(ocr_text: str, filename: str, account: str) -> dict:
    lines = [l.strip() for l in ocr_text.split('\n') if l.strip()]
    full_text = " ".join(lines)
    
    # 1. Project Type
    project_type = "Feature Film"
    if re.search(r'\b(SERIES|WEB SERIES|EPISODIC)\b', full_text, re.I):
        project_type = "TV Episodic"
    elif re.search(r'\b(SHORT FILM|SHORT)\b', full_text, re.I):
        project_type = "Short Film"
    elif re.search(r'\b(COMMERCIAL|AD FILM|TVC)\b', full_text, re.I):
        project_type = "Commercial"
    elif re.search(r'\b(THEATER|PLAY)\b', full_text, re.I):
        project_type = "Theater"
    elif re.search(r'\b(CREATIVE PROJECT|MUSIC VIDEO)\b', full_text, re.I):
        project_type = "Creative Project"

    # 2. Project Title
    project_match = re.search(r'PROJECT\s*:\s*([^.\n]+)', ocr_text, re.I)
    if project_match:
        project = project_match.group(1).strip()
    elif "NITESH TIWARI" in ocr_text.upper():
        project = "Nitesh Tiwari Production"
    elif "FEATURE FILM" in ocr_text.upper():
        project = "Untitled Feature Film"
    elif "SCREENPLAY NO" in ocr_text.upper():
        m = re.search(r'SCREENPLAY NO\.?\s*(\d+)', ocr_text, re.I)
        project = f"Screenplay Series #{m.group(1)}" if m else "Screenplay Series"
    else:
        project = f"Casting Call Project ({account})"

    # 3. Roles
    candidate_roles = []
    # Search for role blocks: "Male Actors", "Female Actors", "Boy 5 to 8", "Looking for..."
    role_patterns = [
        r'(?:Looking for|Seeking)\s+([^.,\n]+)',
        r'([A-Za-z0-9 ]+Speaking Actor[s]?)',
        r'((?:Male|Female)\s+Actors?\s*(?:\([^)]+\)|Age Group\s*:\s*[^.\n]+)?)',
        r'((?:BOY|GIRL)\s+\d+\s+TO\s+\d+\s+YEAR\s+OLD)',
        r'((?:MALE|FEMALE)\s+\d+\s+TO\s+\d+)',
        r'(GRAND PARENTS\s+\d+\s+TO\s+\d+)'
    ]
    for pat in role_patterns:
        for m in re.finditer(pat, ocr_text, re.I):
            role_str = m.group(1).strip()
            if len(role_str) > 3 and role_str not in candidate_roles:
                candidate_roles.append(role_str)
                
    if not candidate_roles:
        candidate_roles = ["Featured Actor / Performer"]
    target_role = candidate_roles[0]

    # 4. Role Size
    role_size = "Supporting"
    if re.search(r'\b(MAIN PARTS?|LEAD|PRIMARY)\b', full_text, re.I):
        role_size = "Lead"
    elif re.search(r'\b(BACKGROUND|EXTRA)\b', full_text, re.I):
        role_size = "Background"

    # 5. Casting Office
    casting_office = f"@{account}"
    if "Casting Bay" in ocr_text:
        casting_office = "Casting Bay"
    elif "FastCast" in ocr_text:
        casting_office = "FastCast Talent Discovery"
    elif "Mukesh Chhabra" in ocr_text or "MCCC" in ocr_text:
        casting_office = "Mukesh Chhabra Casting"

    # 6. Due Date
    due_date = None
    date_match = re.search(r'(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})', ocr_text)
    if date_match:
        due_date = f"2026-11-{int(date_match.group(1).split('/')[0]):02d}T18:00:00Z"

    # 7. Specs
    specs = []
    if re.search(r'introduction video', full_text, re.I):
        specs.append("Submit 1-minute introduction video")
    if re.search(r'photograph|picture|headshot', full_text, re.I):
        specs.append("Submit 2-5 recent unedited photographs")
    if re.search(r'hindi|english|punjabi|nepali', full_text, re.I):
        lang_match = re.findall(r'\b(Hindi|English|Punjabi|Nepali)\b', full_text, re.I)
        if lang_match:
            specs.append(f"Language requirements: {', '.join(set(m.title() for m in lang_match))}")
    if re.search(r'dance|rhythm', full_text, re.I):
        specs.append("Dance performance reel / natural sense of rhythm")

    # 8. Contact & Links
    email_match = re.search(r'([a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)', ocr_text)
    phone_match = re.search(r'(\+?\d[\d -]{8,}\d)', ocr_text)
    contact = email_match.group(1) if email_match else (phone_match.group(1) if phone_match else None)

    # 9. Director guidance
    guidance = []
    if "comic timing" in full_text.lower():
        guidance.append("Requires strong comedic timing.")
    if "swaggering" in full_text.lower() or "charismatic" in full_text.lower():
        guidance.append("Charismatic, swaggering presence.")
    if "glamorous" in full_text.lower():
        guidance.append("Glamorous, fashionable aesthetic.")
    guidance_str = " ".join(guidance) if guidance else "Deliver natural, conversational performance according to character breakdown."

    return {
        "project": project,
        "project_type": project_type,
        "role": target_role,
        "candidate_roles": candidate_roles,
        "role_size": role_size,
        "casting_office": casting_office,
        "due_date": due_date,
        "specs": specs if specs else ["Standard self-tape framing with headshots"],
        "sides_link": None,
        "submission_email": contact,
        "director_guidance": guidance_str
    }

def main():
    print("[*] Ingesting scraped Instagram casting notices...")
    images = glob.glob(str(NOTICES_DIR / "*" / "*.jpg"))
    print(f"[*] Found {len(images)} notice images")

    new_samples = []
    for img_path in sorted(images):
        p = Path(img_path)
        account = p.parent.name
        img = Image.open(p)
        raw_ocr = pytesseract.image_to_string(img)
        cleaned = clean_ocr(raw_ocr)
        
        # Only ingest if we have substantial notice text (at least 50 chars)
        if len(cleaned) < 50:
            continue
            
        parsed_fields = parse_notice_fields(cleaned, p.name, account)
        
        sample = {
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT_NOTICE},
                {"role": "user", "content": f"Parse this scanned casting notice OCR into OneTake JSON:\n\n{cleaned}"},
                {"role": "assistant", "content": json.dumps(parsed_fields, indent=2)}
            ]
        }
        new_samples.append(sample)
        print(f"  [+] Ingested notice from {p.name}: Role='{parsed_fields['role']}' Project='{parsed_fields['project']}'")

    print(f"\n[+] Created {len(new_samples)} new real-world training instances from Instagram notices.")
    
    # Append to parsing_dataset_train.jsonl
    with open(TRAIN_FILE, "a", encoding="utf-8") as f:
        for s in new_samples:
            f.write(json.dumps(s) + "\n")

    print(f"[+] Appended to {TRAIN_FILE}")

if __name__ == "__main__":
    main()
