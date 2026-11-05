#!/usr/bin/env python3
"""
OneTake Commercial & Multi-Column Dataset Expander
=================================================
Expands the instruction training dataset with:
  1. Multi-column commercial casting notices (TVCs, digital brand campaigns, FMCG, banking, tech)
  2. Two-column Audio/Visual (AV) commercial sides with OCR-interleaved lines
  3. Tabular casting breakdown grids (Role | Age | Gender | Tier | Status)
  4. Call sheets with scene schedule columns
  5. Multi-speaker commercial sides with reader cue attribution

Outputs updated samples to: dataset/parsing_dataset_train.jsonl
"""

import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
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

SYSTEM_PROMPT_SIDES = """You are OneTake's screenplay sides parser.
Extract scenes and dialogue blocks from the raw text into JSON:
{
  "scenes": [
    {
      "number": 1,
      "heading": "INT. LOCATION - NIGHT",
      "lines": [
        {
          "character": "CHARACTER NAME",
          "parenthetical": "action or emotion or null",
          "text": "Spoken line text"
        }
      ]
    }
  ]
}
Output valid JSON only."""

def build_commercial_and_multicolumn_samples():
    samples = []

    def add_notice(raw_text, target):
        samples.append({
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT_NOTICE},
                {"role": "user", "content": f"Parse this scanned casting notice OCR into OneTake JSON:\n\n{raw_text.strip()}"},
                {"role": "assistant", "content": json.dumps(target, indent=2)}
            ]
        })

    def add_sides(raw_text, target):
        samples.append({
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT_SIDES},
                {"role": "user", "content": f"Parse these scanned screenplay sides into OneTake JSON:\n\n{raw_text.strip()}"},
                {"role": "assistant", "content": json.dumps(target, indent=2)}
            ]
        })

    # =========================================================================
    # 1. Multi-Column Brand Commercial (Cadbury Dairy Milk Diwali TVC)
    # =========================================================================
    cadbury_text = """CASTING CALL: CADBURY DIWALI FESTIVE TVC
Casting Agency: Mukesh Chhabra Casting Company (MCCC)
Shoot Location: Mumbai Film City | Shoot Dates: Dec 1-3, 2026
Submission Deadline: 18 NOVEMBER 2026 | Email: festive@mccc.in

BREAKDOWN GRID:
-----------------------------------------------------------------------------------------------------------------
ROLE               | AGE RANGE | GENDER | TIER      | COMP (PER DAY) | WARDROBE & BRIEF
-----------------------------------------------------------------------------------------------------------------
Arjun (Younger Bro)| 18 - 22   | Male   | Lead      | INR 65,000     | Playful, expressive eyes, warm smile
Ananya (Elder Sis) | 22 - 26   | Female | Lead      | INR 65,000     | Affectionate, teasing, grounded
Mrs. Sharma (Mom)  | 45 - 52   | Female | Supporting| INR 40,000     | Elegant, traditional, matriarchal
Dadu (Grandfather) | 70 - 80   | Male   | Supporting| INR 40,000     | Joyful, twinkle in his eyes
-----------------------------------------------------------------------------------------------------------------

SELF-TAPE INSTRUCTIONS:
- Slate first: state your full name, age, city, and agent representation.
- Framing: Horizontal (landscape) orientation only, medium close-up (chest up).
- Lighting: Natural front lighting, solid neutral backdrop.
- Include a full length profile turnaround at the end of the tape."""

    add_notice(cadbury_text, {
        "project": "Cadbury Diwali Festive Tvc",
        "project_type": "Commercial",
        "role": "",
        "candidate_roles": ["Arjun", "Ananya", "Mrs. Sharma", "Dadu"],
        "role_size": "Lead",
        "casting_office": "Mukesh Chhabra Casting Company (MCCC)",
        "due_date": "2026-11-18T23:59:59Z",
        "specs": ["Slate first", "Landscape", "Full length"],
        "sides_link": None,
        "submission_email": "festive@mccc.in",
        "director_guidance": "Warm, festive emotional tone. Playful sibling banter resolving in a heartfelt moment of sharing."
    })

    # =========================================================================
    # 2. Two-Column Audio/Visual Commercial Script (Tech Brand TVC)
    # =========================================================================
    av_script_text = """PROJECT: NEXUS AI SMARTPHONE
CLIENT: NEXUS MOBILITY
TITLE: "MORNING RUSH" (30 SEC TVC)
DIRECTOR: VIKRAMADITYA MOTWANE

[VISUAL / CAMERA]                             [AUDIO / DIALOGUE]
Wide shot of modern Bangalore apartment.      ALOK: (groans)
Alok (28) frantically looks for his keys.     Where did I put the car keys?!
Camera cuts to kitchen counter.               
Kavya (26) calmly sips her green tea.         KAVYA:
                                              Did you check inside your jacket?
Alok pats his chest pocket. Keys jingle.      ALOK:
He exhales with relief.                       Found them!
Kavya taps her Nexus phone screen.            KAVYA:
                                              Your meeting starts in fifteen minutes. Go!
Macro CU of Nexus screen glowing.             ALOK:
Alok dashes out the front door.               You're a lifesaver!"""

    add_sides(av_script_text, {
        "scenes": [
            {
                "number": 1,
                "heading": "INT. BANGALORE APARTMENT - MORNING",
                "lines": [
                    {"character": "ALOK", "parenthetical": "groans", "text": "Where did I put the car keys?!"},
                    {"character": "KAVYA", "parenthetical": None, "text": "Did you check inside your jacket?"},
                    {"character": "ALOK", "parenthetical": None, "text": "Found them!"},
                    {"character": "KAVYA", "parenthetical": None, "text": "Your meeting starts in fifteen minutes. Go!"},
                    {"character": "ALOK", "parenthetical": None, "text": "You're a lifesaver!"}
                ]
            }
        ]
    })

    # =========================================================================
    # 3. Nike Athletic Apparel Commercial Casting Notice (Multi-Column Format)
    # =========================================================================
    nike_notice = """NOW CASTING: NIKE "UNSTOPPABLE" DIGITAL CAMPAIGN
Casting Director: Telsey + Company | In association with Casting Collective London
Shoot Location: Barcelona & Valencia | Shoot Window: January 10-18, 2027
Deadline for Submissions: 25 NOVEMBER 2026
Upload Audition Reels to: https://dropbox.com/request/nike-unstoppable-2026

COLUMN A (TALENT SPECS)             | COLUMN B (ROLE TIERS & USAGE)
--------------------------------------------------------------------------------------
SPRINTER (20-28 yrs, Female)        | TIER: Principal Performer
Track athlete, explosive speed      | USAGE: Worldwide Digital + Theatrical (2 Years)
                                    | RATE: $2,500/shoot day + $10,000 buyout
BASKETBALL GUARD (18-24 yrs, Male)  | TIER: Principal Performer
Streetball handler, charismatic     | USAGE: Worldwide Digital + Theatrical (2 Years)
                                    | RATE: $2,500/shoot day + $10,000 buyout
MARATHON RUNNER (35-45 yrs, Any)    | TIER: Supporting Performer
Grit, endurance runner, real runner | RATE: $1,800/shoot day + $5,000 buyout
--------------------------------------------------------------------------------------

AUDITION REQUIREMENTS:
1. Slate first: Name, height, passport validity (must be valid through July 2027), primary sport.
2. Shoot in Landscape format at 1080p 60fps.
3. Perform a 30-second authentic athletic monologue: Describe the toughest race or game of your life.
4. Provide raw, non-color-graded footage with clear spoken audio."""

    add_notice(nike_notice, {
        "project": "Nike Unstoppable",
        "project_type": "Commercial",
        "role": "",
        "candidate_roles": ["Sprinter", "Basketball Guard", "Marathon Runner"],
        "role_size": "Lead",
        "casting_office": "Telsey + Company",
        "due_date": "2026-11-25T23:59:59Z",
        "specs": ["Slate first", "Landscape"],
        "sides_link": "https://dropbox.com/request/nike-unstoppable-2026",
        "submission_email": None,
        "director_guidance": "Authentic athlete emotion. Unfiltered determination, grit, and passion."
    })

    # =========================================================================
    # 4. Two-Column Split Screen Coffee Commercial (Starbucks / Blue Tokai)
    # =========================================================================
    coffee_sides = """BLUE TOKAI COFFEE ROASTERS
TVC: "FIRST SIP"
DRAFT: PRODUCTION FINAL

SCENE 1 - INT. ARTISAN CAFE - MORNING
[CAMERA ACTION]                           [SPOKEN DIALOGUE]
Rhea enters shaking umbrella.             RHEA:
Barista notices her soaked coat.          Is there anything hot enough to thaw out November?
Barista pours dark roast pour-over.       BARISTA:
Steam rises into lens.                    Single estate washed Arabica. Give it ten seconds.
Rhea cups the porcelain mug.              RHEA:
Smiles as warmth returns.                 (sighs with relief)
                                          That smells like heaven.
Barista winks.                            BARISTA:
                                          Better than heaven. It's freshly roasted."""

    add_sides(coffee_sides, {
        "scenes": [
            {
                "number": 1,
                "heading": "INT. ARTISAN CAFE - MORNING",
                "lines": [
                    {"character": "RHEA", "parenthetical": None, "text": "Is there anything hot enough to thaw out November?"},
                    {"character": "BARISTA", "parenthetical": None, "text": "Single estate washed Arabica. Give it ten seconds."},
                    {"character": "RHEA", "parenthetical": "sighs with relief", "text": "That smells like heaven."},
                    {"character": "BARISTA", "parenthetical": None, "text": "Better than heaven. It's freshly roasted."}
                ]
            }
        ]
    })

    # =========================================================================
    # 5. Tata Motors EV Commercial Call Sheet & Breakdown
    # =========================================================================
    tata_ev_notice = """PROJECT: TATA CURVV EV LAUNCH CAMPAIGN
PRODUCTION HOUSE: CHAI TEA FILMS MUMBAI
DIRECTOR: SHIMIT AMIN | CASTING: CASTING BAY
LAST DATE TO APPLY: 28 NOVEMBER 2026
SUBMISSION EMAIL: CURVV@CASTINGBAY.IN

CHARACTER BREAKDOWN TABLE:
-------------------------------------------------------------------------------------
ROLE NAME    | AGE   | GENDER | KEY ATTRIBUTES             | REMARKS
-------------------------------------------------------------------------------------
NEHA         | 28-34 | Female | EV Architect, visionary    | Confident, bilingual
KABIR        | 30-36 | Male   | Environmental journalist   | Thoughtful, sharp
TANYA        | 7-10  | Female | Neha's inquisitive daughter| Natural child actor
-------------------------------------------------------------------------------------

TAPE DELIVERABLES:
- Self-tape framing: Landscape horizontal.
- Slate video: Include full name, current city, and car driving license status.
- Sides available at: https://drive.google.com/drive/folders/tata-curvv-sides-2026
- No background noise, no music overlays."""

    add_notice(tata_ev_notice, {
        "project": "Tata Curvv Ev Launch Campaign",
        "project_type": "Commercial",
        "role": "",
        "candidate_roles": ["Neha", "Kabir", "Tanya"],
        "role_size": "Lead",
        "casting_office": "Casting Bay",
        "due_date": "2026-11-28T23:59:59Z",
        "specs": ["Landscape", "Slate first"],
        "sides_link": "https://drive.google.com/drive/folders/tata-curvv-sides-2026",
        "submission_email": "curvv@castingbay.in",
        "director_guidance": "Contemporary, confident, futuristic and sustainable lifestyle tone."
    })

    # =========================================================================
    # 6. Automobile Commercial Sides (Tata Curvv)
    # =========================================================================
    car_sides = """TATA CURVV EV - SIDES FOR "NEHA" & "KABIR"
SCENE 1 - EXT. HIGHWAY OVERLOOK - DUSK
NEHA and KABIR stand beside the sleek vehicle looking at the windmills in the valley.

NEHA:
You still worried about range?

KABIR:
(smiles, shaking his head)
We just drove three hundred kilometers through the Ghats and we have forty percent left.

NEHA:
I told you. The future doesn't wait for charging stations.

KABIR:
Where to next? Goa?

NEHA:
Let's keep going until the road runs out."""

    add_sides(car_sides, {
        "scenes": [
            {
                "number": 1,
                "heading": "EXT. HIGHWAY OVERLOOK - DUSK",
                "lines": [
                    {"character": "NEHA", "parenthetical": None, "text": "You still worried about range?"},
                    {"character": "KABIR", "parenthetical": "smiles, shaking his head", "text": "We just drove three hundred kilometers through the Ghats and we have forty percent left."},
                    {"character": "NEHA", "parenthetical": None, "text": "I told you. The future doesn't wait for charging stations."},
                    {"character": "KABIR", "parenthetical": None, "text": "Where to next? Goa?"},
                    {"character": "NEHA", "parenthetical": None, "text": "Let's keep going until the road runs out."}
                ]
            }
        ]
    })

    # =========================================================================
    # 7. E-Commerce / Quick Commerce Notice (Blinkit / Zepto Style)
    # =========================================================================
    qcommerce_notice = """CASTING NOTICE: QUICKDELIVERY DIWALI EXPRESS
Agency: Anti-Casting Mumbai
Production: Nirvana Films
Audition Deadline: 30 NOVEMBER 2026 | Send tapes to: tapes@anticasting.com

ROLES:
1. RAHUL (22-26, Male): Enthusiastic delivery champion. Warm, quick-witted, big smile.
2. POOJA (25-32, Female): Busy software team lead hosting family dinner. Stressed then relieved.
3. UNCLE JI (55-65, Male): Demanding traditional sweet lover who wants fresh Gulab Jamun.

Specs:
- Framing: Landscape orientation.
- Slate required: Name, age, height, languages spoken.
- Script sides link: https://anticasting.com/sides/quickdelivery-diwali.pdf"""

    add_notice(qcommerce_notice, {
        "project": "Quickdelivery Diwali Express",
        "project_type": "Commercial",
        "role": "",
        "candidate_roles": ["Rahul", "Pooja", "Uncle Ji"],
        "role_size": "Lead",
        "casting_office": "Anti-Casting",
        "due_date": "2026-11-30T23:59:59Z",
        "specs": ["Landscape", "Slate first"],
        "sides_link": "https://anticasting.com/sides/quickdelivery-diwali.pdf",
        "submission_email": "tapes@anticasting.com",
        "director_guidance": "High energy, relatable comedic timing, quick comedic beats."
    })

    # =========================================================================
    # 8. Streaming Platform Episodic Drama Notice (Netflix / Hotstar)
    # =========================================================================
    series_notice = """PROJECT: THE BOMBAY CARTEL (SEASON 2)
PRODUCER: EXCEL ENTERTAINMENT | PLATFORM: NETFLIX
CASTING DIRECTOR: MUKESH CHHABRA CASTING COMPANY (MCCC)
DUE DATE: 10 DECEMBER 2026 | SUBMIT VIA: cartel2@mccc.in

CHARACTER ROLES NEEDED:
-----------------------------------------------------------------------------
OFFICER TARA DESHMUKH | 32-38 yrs | Female | Series Regular | IPS Crime Branch
FARHAN SHEIKH         | 28-35 yrs | Male   | Series Regular | Undercover hacker
COMMISSIONER MENON    | 52-60 yrs | Male   | Supporting     | Stern bureaucrat
-----------------------------------------------------------------------------

INSTRUCTIONS:
- Self-tape must be strictly recorded in Landscape mode.
- Slate video first: Name, height, agent contact, city of residence.
- Memorization is mandatory. No off-camera script glancing.
- Full length profile turn at the end of the video."""

    add_notice(series_notice, {
        "project": "The Bombay Cartel",
        "project_type": "TV Episodic",
        "role": "",
        "candidate_roles": ["Officer Tara Deshmukh", "Farhan Sheikh", "Commissioner Menon"],
        "role_size": "Series Regular",
        "casting_office": "Mukesh Chhabra Casting Company (MCCC)",
        "due_date": "2026-12-10T23:59:59Z",
        "specs": ["Landscape", "Slate first", "Full length"],
        "sides_link": None,
        "submission_email": "cartel2@mccc.in",
        "director_guidance": "Gritty, realistic police procedural. Intense, controlled undercurrent of suspense."
    })

    # =========================================================================
    # 9. Episodic Sides (The Bombay Cartel - Tara & Farhan)
    # =========================================================================
    cartel_sides = """THE BOMBAY CARTEL - EPISODE 201 SIDES
SCENE 4 - INT. SAFE HOUSE - NIGHT
TARA stands over a desk scattered with surveillance photos. FARHAN types furiously on a battered laptop.

TARA:
Did you trace the IP from the offshore account?

FARHAN:
(without looking up)
I didn't just trace it. I mirrored their hard drives.

TARA:
Give me a name, Farhan.

FARHAN:
(stopping, looking up slowly)
You won't like it, Boss. The server is registered inside the Home Ministry.

TARA:
(beat, steely gaze)
Print everything. We have four hours before they realize we're inside."""

    add_sides(cartel_sides, {
        "scenes": [
            {
                "number": 4,
                "heading": "INT. SAFE HOUSE - NIGHT",
                "lines": [
                    {"character": "TARA", "parenthetical": None, "text": "Did you trace the IP from the offshore account?"},
                    {"character": "FARHAN", "parenthetical": "without looking up", "text": "I didn't just trace it. I mirrored their hard drives."},
                    {"character": "TARA", "parenthetical": None, "text": "Give me a name, Farhan."},
                    {"character": "FARHAN", "parenthetical": "stopping, looking up slowly", "text": "You won't like it, Boss. The server is registered inside the Home Ministry."},
                    {"character": "TARA", "parenthetical": "beat, steely gaze", "text": "Print everything. We have four hours before they realize we're inside."}
                ]
            }
        ]
    })

    # =========================================================================
    # 10. Healthcare & Pharma TVC (Multi-Column Format)
    # =========================================================================
    pharma_notice = """PROJECT: REVITAL LIFE WELLNESS CAMPAIGN
CASTING: CASTING BAY MUMBAI
DEADLINE: 22 NOVEMBER 2026 | SUBMISSIONS: WELLNESS@CASTINGBAY.IN

BREAKDOWN COLUMNS:
ROLE                  | DEMOGRAPHIC         | CHARACTER NOTES
-----------------------------------------------------------------------------
DR. ADITI             | 30-38 Female        | Compassionate pediatrician, authoritative
DEV                   | 40-48 Male          | Marathon runner & corporate father, energetic
GRANDMA KALPANA       | 65-75 Female        | Active yoga practitioner, vibrant
-----------------------------------------------------------------------------

SUBMISSION SPECS:
- Slate first: state name, age, city.
- Horizontal landscape video format.
- Sides packet: https://castingbay.in/sides/revital-life.pdf"""

    add_notice(pharma_notice, {
        "project": "Revital Life Wellness Campaign",
        "project_type": "Commercial",
        "role": "",
        "candidate_roles": ["Dr. Aditi", "Dev", "Grandma Kalpana"],
        "role_size": "Lead",
        "casting_office": "Casting Bay",
        "due_date": "2026-11-22T23:59:59Z",
        "specs": ["Slate first", "Landscape"],
        "sides_link": "https://castingbay.in/sides/revital-life.pdf",
        "submission_email": "wellness@castingbay.in",
        "director_guidance": "Vibrant, optimistic health & vitality messaging. Natural smiles, crisp delivery."
    })

    # =========================================================================
    # 11-20: Additional Diverse Commercial & Multi-Column Breakdown Samples
    # =========================================================================
    brands = [
        ("Zomato Late Night Cravings", "Commercial", "Mukesh Chhabra Casting Company (MCCC)", ["Host", "Gourmet Chef", "Late Night Student"], "zomato@mccc.in"),
        ("HDFC Bank Future First", "Commercial", "Anti-Casting", ["Young Entrepreneur", "Senior Advisor", "Daughter"], "hdfc@anticasting.com"),
        ("MakeMyTrip Vacation Tales", "Commercial", "Casting Bay", ["Rohan", "Simran", "Homestay Host"], "tours@castingbay.in"),
        ("Samsung Neo QLED Showcase", "Commercial", "Telsey + Company", ["Gamer", "Cinema Fanatic", "Architect"], "samsung@telsey.com"),
        ("Tanishq Festive Gold", "Commercial", "Mukesh Chhabra Casting Company (MCCC)", ["Bride Meera", "Mother", "Groom Kabir"], "tanishq@mccc.in"),
        ("Airtel 5G Ultra Connect", "Commercial", "Anti-Casting", ["Remote Surgeon", "Drone Pilot", "Granddaughter"], "airtel@anticasting.com"),
        ("Uber Intercity Stories", "Commercial", "Casting Bay", ["Driver Aslam", "Passenger Vikram", "Daughter Sanya"], "uber@castingbay.in"),
        ("Asian Paints Beautiful Homes", "Commercial", "Mukesh Chhabra Casting Company (MCCC)", ["Interior Designer", "Homeowner Raj", "Wife Priya"], "asianpaints@mccc.in"),
        ("Spotify Discover India", "Commercial", "Anti-Casting", ["Indie Singer", "Podcast Host", "Subway Commuter"], "music@anticasting.com"),
        ("Amazon Prime Video Promo", "Commercial", "Telsey + Company", ["Movie Buff", "Binge Watcher", "Critic"], "prime@telsey.com")
    ]

    for name, p_type, office, roles, email in brands:
        notice_body = f"""NOW CASTING: {name.upper()}
Casting Agency: {office}
Project Type: {p_type}
Deadline: 5 DECEMBER 2026 | Submission Email: {email}

ROLES BREAKDOWN TABLE:
---------------------------------------------------------------------
ROLE              | AGE       | ROLE TIER   | GENDER
---------------------------------------------------------------------
{roles[0]}       | 20-30 yrs | Lead        | Any
{roles[1]}       | 30-45 yrs | Supporting  | Any
{roles[2]}       | 18-28 yrs | Co-Star     | Any
---------------------------------------------------------------------

REQUIREMENTS:
- Record strictly in landscape orientation.
- Slate first with name, city, and height.
- Sides link: https://casting.io/sides/{name.lower().replace(' ', '-')}.pdf"""

        add_notice(notice_body, {
            "project": name.title(),
            "project_type": p_type,
            "role": "",
            "candidate_roles": roles,
            "role_size": "Lead",
            "casting_office": office,
            "due_date": "2026-12-05T23:59:59Z",
            "specs": ["Landscape", "Slate first"],
            "sides_link": f"https://casting.io/sides/{name.lower().replace(' ', '-')}.pdf",
            "submission_email": email,
            "director_guidance": "High engagement commercial performance. Engaging, expressive, relatable."
        })

        # Add corresponding commercial dialogue side
        sides_body = f"""PROJECT: {name.upper()}
SCENE 1 - INT. URBAN SPACE - DAY
{roles[0].upper()}:
Have you seen this before?

{roles[1].upper()}:
(smiling warmly)
I see it every single day. And it still amazes me.

{roles[0].upper()}:
Let's make sure everyone else sees it too."""

        add_sides(sides_body, {
            "scenes": [
                {
                    "number": 1,
                    "heading": "INT. URBAN SPACE - DAY",
                    "lines": [
                        {"character": roles[0].upper(), "parenthetical": None, "text": "Have you seen this before?"},
                        {"character": roles[1].upper(), "parenthetical": "smiling warmly", "text": "I see it every single day. And it still amazes me."},
                        {"character": roles[0].upper(), "parenthetical": None, "text": "Let's make sure everyone else sees it too."}
                    ]
                }
            ]
        })

    return samples

def main():
    print("[*] Generating rich multi-column & commercial samples...")
    new_samples = build_commercial_and_multicolumn_samples()
    print(f"[+] Generated {len(new_samples)} new multi-column & commercial samples.")

    existing_samples = []
    seen_prompts = set()

    if TRAIN_FILE.exists():
        with open(TRAIN_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    user_prompt = obj["messages"][1]["content"]
                    if user_prompt not in seen_prompts:
                        seen_prompts.add(user_prompt)
                        existing_samples.append(obj)
                except Exception:
                    pass

    print(f"[*] Found {len(existing_samples)} unique existing samples.")

    added_count = 0
    for s in new_samples:
        user_prompt = s["messages"][1]["content"]
        if user_prompt not in seen_prompts:
            seen_prompts.add(user_prompt)
            existing_samples.append(s)
            added_count += 1

    print(f"[+] Added {added_count} brand-new samples into training set.")
    print(f"[+] Total deduplicated dataset size: {len(existing_samples)} samples.")

    with open(TRAIN_FILE, "w", encoding="utf-8") as f:
        for s in existing_samples:
            f.write(json.dumps(s) + "\n")

    print(f"[OK] Successfully updated {TRAIN_FILE}.")

if __name__ == "__main__":
    main()
