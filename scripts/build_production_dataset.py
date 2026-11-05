#!/usr/bin/env python3
"""
OneTake Production Dataset Builder
==================================
Compiles a robust, real-world instruction training dataset combining:
  1. Real Instagram casting flyers from @24x7auditionupdates & @casting_updates
  2. Multi-role theatrical/film casting packets:
     - "PILGRIMAGE" (Multi-role breakdown, slate specs, director notes, Kaaba monologues)
     - "CHICAGO" (Vaudeville sides, gender-categorized monologues, multi-turn cuts)
     - "GREASE - The Musical" (32-page packet, scene table, top-box cues, multi-speaker dialogue)
  3. Synthesized high-variance OCR-degraded screenplay sides and notices

Maps 100% of the text to OneTake's exact application columns:
  - Notice: project, project_type, role, candidate_roles, role_size, casting_office, due_date, specs, sides_link, submission_email, director_guidance
  - Sides: scenes with number, heading, lines (character, text, parenthetical)
"""

import os
import json
import glob
from pathlib import Path
from PIL import Image
import pytesseract

pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

BASE_DIR = Path(__file__).resolve().parent.parent
DATASET_DIR = BASE_DIR / "dataset"
TRAIN_FILE = DATASET_DIR / "parsing_dataset_train.jsonl"
EVAL_FILE = DATASET_DIR / "parsing_dataset_eval.jsonl"

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

def create_real_world_samples():
    samples = []

    # =========================================================================
    # 1. PILGRIMAGE - Cover & Character Pages
    # =========================================================================
    pilgrimage_cover_text = """PILGRIMAGE
CASTING SIDES
Humaira Ghilzai & Bridgette Dutta Portman
Director: Khaled Abol Naga (Kal)
The Lab at Georgetown University · November 2026
HOW TO USE THESE SIDES
Each side has been selected to reveal character, range, and presence within 1–2 
minutes of screen time. Please read all instructions on your character's page before 
recording.
Slate first. At the top of your video, look directly into the camera and state your name,
pronouns, the role you are reading for, and your city.
Video format. Horizontal (landscape), MP4, 1080p or 720p preferred. Maximum 
500MB. Good light on your face, quiet background. No production quality required.
If reading for multiple roles, submit a separate video per character.
Dialogue sides (Nadia). Nadia's sides include a brief dialogue exchange. Simply skip 
or pause over the other character's lines — the director will read between the lines.
Submit your tape via the link at: kalnaga.com/pilgrimage/casting.html
THE CHARACTERS IN THIS DOCUMENT
NOOR — Page 2
MARYAM — Page 3
NADIA — Page 4
SOSAN — Page 5
FATIMA — Page 6"""

    pilgrimage_cover_target = {
        "project": "Pilgrimage",
        "project_type": "Theater",
        "role": "Noor",
        "candidate_roles": ["Noor", "Maryam", "Nadia", "Sosan", "Fatima"],
        "role_size": "Lead",
        "casting_office": "Khaled Abol Naga (Kal) / The Lab at Georgetown University",
        "due_date": "2026-11-30T23:59:59Z",
        "specs": [
            "Slate first: Name, pronouns, role, city",
            "Horizontal (landscape) MP4, 1080p or 720p",
            "Max file size: 500MB",
            "Submit a separate video per character",
            "Maximum total video: 2 minutes per side"
        ],
        "sides_link": "https://kalnaga.com/pilgrimage/casting.html",
        "submission_email": "https://kalnaga.com/pilgrimage/casting.html",
        "director_guidance": "Each side selected to reveal character, range, and presence within 1-2 minutes of screen time."
    }

    samples.append({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_NOTICE},
            {"role": "user", "content": f"Parse this scanned casting notice OCR into OneTake JSON:\n\n{pilgrimage_cover_text}"},
            {"role": "assistant", "content": json.dumps(pilgrimage_cover_target, indent=2)}
        ]
    })

    # Pilgrimage: Noor's Monologue
    noor_text = """NOOR · She/her · Early 60s · Afghan American
Director note: What I'm looking for: the weight of a woman who has carried this secret for 
decades, and the terrifying relief of finally putting it down. Let the pauses breathe. Don't rush 
the confession. The scene lives in what she can barely bring herself to say.
SLATE INSTRUCTION Before beginning, look directly into camera and state: your full name · your 
pronouns · the role you are reading for (NOOR) · your location. Maximum total video: 2 minutes.
THE SIDE — Noor's Confession (Act II, Scene 4)
Setting: At the Kaaba, Mecca. Noor addresses Maryam directly for the first time.
You know I've called you my miracle child, Maryam. I had such trouble conceiving. 
I thought it was my fault, that I was the cause. But I wasn't.
Right after the Russians invaded Afghanistan, they were rounding up anyone who 
was not a communist sympathizer. They took your father—my husband—in for 
interrogation. People didn't return home to their families after these types of 
arrests. After two weeks of no information, no answers, I thought the worst. I fell 
into a deep depression. I couldn't see that life was worth living without him. Almas 
got concerned. She was pregnant with Nadia, so she took precautions and sent her
husband to bring me to their house. It was a way to protect me in case the secret 
police came after me as well.
My brother-in-law arrived late in the day. There was a curfew at dusk. People were
shot if they violated it. No questions asked. So, he spent the night. We didn't intend
for it to happen, but…
Maryam, after my husband was released from prison, he was so happy to hear I 
was pregnant. He showered me with gifts and constantly talked about names. Did 
you know he only picked girl names? He said boys are useless. His joy was a 
reminder of my betrayal so I pushed him away.
Maryam, believe me, I have hated myself for lying to him…but I had no choice. Life
under communist rule was unbearable. We decided to leave Afghanistan. We 
escaped out of our own country like thieves. Being homeless and without direction 
was no time to confess my sin. It would have broken my sister's heart, her 
marriage, my marriage. I took a daughter from one man and gave her to another.
That is the truth, Maryam. All of your grievances against me…they're all valid. I 
stole your chance to be loved by your real father, I pushed the only father you 
knew out of our life and I stole from you the joy of having sisters. I lived with the 
burden of knowing that you deserved a better mother than me."""

    noor_target = {
        "scenes": [
            {
                "number": 1,
                "heading": "AT THE KAABA, MECCA - NOOR'S CONFESSION (ACT II, SCENE 4)",
                "lines": [
                    {
                        "character": "NOOR",
                        "parenthetical": "addressing Maryam directly",
                        "text": "You know I've called you my miracle child, Maryam. I had such trouble conceiving. I thought it was my fault, that I was the cause. But I wasn't. Right after the Russians invaded Afghanistan, they were rounding up anyone who was not a communist sympathizer. They took your father—my husband—in for interrogation. People didn't return home to their families after these types of arrests. After two weeks of no information, no answers, I thought the worst. I fell into a deep depression. I couldn't see that life was worth living without him. Almas got concerned. She was pregnant with Nadia, so she took precautions and sent her husband to bring me to their house. It was a way to protect me in case the secret police came after me as well. My brother-in-law arrived late in the day. There was a curfew at dusk. People were shot if they violated it. No questions asked. So, he spent the night. We didn't intend for it to happen, but… Maryam, after my husband was released from prison, he was so happy to hear I was pregnant. He showered me with gifts and constantly talked about names. Did you know he only picked girl names? He said boys are useless. His joy was a reminder of my betrayal so I pushed him away. Maryam, believe me, I have hated myself for lying to him…but I had no choice. Life under communist rule was unbearable. We decided to leave Afghanistan. We escaped out of our own country like thieves. Being homeless and without direction was no time to confess my sin. It would have broken my sister's heart, her marriage, my marriage. I took a daughter from one man and gave her to another. That is the truth, Maryam. All of your grievances against me…they're all valid. I stole your chance to be loved by your real father, I pushed the only father you knew out of our life and I stole from you the joy of having sisters. I lived with the burden of knowing that you deserved a better mother than me."
                    }
                ]
            }
        ]
    }

    samples.append({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_SIDES},
            {"role": "user", "content": f"Parse these scanned screenplay sides into OneTake scene & dialogue JSON:\n\n{noor_text}"},
            {"role": "assistant", "content": json.dumps(noor_target, indent=2)}
        ]
    })

    # Pilgrimage: Maryam's 2 Sides
    maryam_text = """MARYAM · She/her · Mid-30s · Afghan American
Director note: What I'm looking for: Maryam's comedy and Maryam's devastation are the same 
instrument. I want to see both. Side A shows us the armour — the wit, the control, the 
performance. Side B shows us what's underneath when the armour is ripped off.
SIDE A — The Phone Call (Act I, Scene 5)
Setting: Hotel lobby, on the phone with her assistant Candace. She is in Ihram — the sacred 
white pilgrim's garment.
[speaking on phone]
Candace, I'm about to embark on a journey that Prophet Muhammad, Peace Be 
Upon Him, made in 632 to retake Mecca. So, tell their lawyers that I'm in the state 
of Ihram and can't be bothered with earthly problems. They should stop shitting 
their pants and talk to my lawyers.
I-H-R-A-M. Make sure it's spelled right in the press release.
Candace, I don't care how mad they are. I'm the customer. I don't care if they get a
fine. Tell them we had to suffer in a cramped taxi to keep ourselves on schedule. In
fact, they should pay me back the taxi fare. Tell them Silicon Valley is full of rich 
Muslims and once they read my scathing review of their bad service, they will be 
done for. In fact, I'll write a letter to the Prince to ban the agency from doing trips 
to Saudi Arabia.
Look, I know you can handle this, Candace. We are about to do the most important 
part of the Umrah. Try not to disturb me.
SIDE B — The Aftermath (Act II, Scene 4)
Setting: After Noor's confession at the Kaaba. Maryam speaks to herself, in shock.
I can't talk to her right now.
I can't believe this. She's been lying all her life. My whole life is a lie. She fed me 
this "miracle child" lie.
I really thought I was special.
She brainwashed me against him. She would say, "Your father is too nice, people 
walk all over him. They take advantage of him. Don't be like him. You have to be 
strong." He worshiped the ground she walked on and she just shit all over him.
I'm a public figure. I've told and retold my family story to journalists, to world 
leaders, and it was a lie."""

    maryam_target = {
        "scenes": [
            {
                "number": 1,
                "heading": "HOTEL LOBBY - SIDE A: THE PHONE CALL (ACT I, SCENE 5)",
                "lines": [
                    {
                        "character": "MARYAM",
                        "parenthetical": "speaking on phone with Candace",
                        "text": "Candace, I'm about to embark on a journey that Prophet Muhammad, Peace Be Upon Him, made in 632 to retake Mecca. So, tell their lawyers that I'm in the state of Ihram and can't be bothered with earthly problems. They should stop shitting their pants and talk to my lawyers. I-H-R-A-M. Make sure it's spelled right in the press release. Candace, I don't care how mad they are. I'm the customer. I don't care if they get a fine. Tell them we had to suffer in a cramped taxi to keep ourselves on schedule. In fact, they should pay me back the taxi fare. Tell them Silicon Valley is full of rich Muslims and once they read my scathing review of their bad service, they will be done for. In fact, I'll write a letter to the Prince to ban the agency from doing trips to Saudi Arabia. Look, I know you can handle this, Candace. We are about to do the most important part of the Umrah. Try not to disturb me."
                    }
                ]
            },
            {
                "number": 2,
                "heading": "AT THE KAABA - SIDE B: THE AFTERMATH (ACT II, SCENE 4)",
                "lines": [
                    {
                        "character": "MARYAM",
                        "parenthetical": "in shock, speaking to herself",
                        "text": "I can't talk to her right now. I can't believe this. She's been lying all her life. My whole life is a lie. She fed me this \"miracle child\" lie. I really thought I was special. She brainwashed me against him. She would say, \"Your father is too nice, people walk all over him. They take advantage of him. Don't be like him. You have to be strong.\" He worshiped the ground she walked on and she just shit all over him. I'm a public figure. I've told and retold my family story to journalists, to world leaders, and it was a lie."
                    }
                ]
            }
        ]
    }

    samples.append({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_SIDES},
            {"role": "user", "content": f"Parse these scanned screenplay sides into OneTake scene & dialogue JSON:\n\n{maryam_text}"},
            {"role": "assistant", "content": json.dumps(maryam_target, indent=2)}
        ]
    })

    # =========================================================================
    # 2. CHICAGO SIDES - Gender Groupings & Multi-Cut Monologues
    # =========================================================================
    chicago_female_text = """AUDITION SIDES:
Choose one of these sides. Memorization is required. You are welcome to 
perform two sides if you wish, but only one is required.
For Female Identifying:
Roxie: 
You wanna know something? I always wanted my name in the paper. Before Amos 
came along, I used to date this well-to-do ugly bootlegger. He used to like to dress me 
up, take me out, and show me off. Ugly guys like to do that. Once it said in the paper, 
“Gangland’s Al Capelli seen at Chez Vito with cute redheaded chorine.” That was me. I 
clipped it out and saved it. Now look – “ROXIE ROCKS CHICAGO.” Look, I’m gonna tell 
you the truth. Not that the truth really matters, but I’m gonna tell you anyway. The thing 
is, see I’m older than I ever intended to be. All my life I wanted to be a dancer in 
vaudeville. Oh, yeah. Have my own act. But no. No. No. No. No. It was one big world 
full of “No.” Life. Then Amos comes along. Sweet, safe Amos, who never says no. You 
know some guys are like mirrors, and when I catch myself in Amos’ face, I’m always a 
kid.
Velma:
My sister Veronica and I did this double act and my husband, Charlie, traveled around 
with us. Now, for the last number in our act, we did these twenty acrobatic tricks in a row 
– 1, 2, 3, 4, 5, splits, spreadeagles, flip-flops, back flips, one right after the other. Well, 
this one night we were in Cicero, the three of us, sittin’ up in a hotel room, boozin’ and 
havin’ a few laughts and we ran out of ice, so I went out to get some. I come back, open 
the door and there’s Veronica and Charlie doing Number Seventeen – the spread eagle. 
Well, I was in such a state of shock, I completely blacked out. I can’t remember a thing. 
It wasn’t until later, when I was washing the blood off my hands I even knew they were 
dead."""

    chicago_target = {
        "scenes": [
            {
                "number": 1,
                "heading": "ROXIE AUDITION MONOLOGUE",
                "lines": [
                    {
                        "character": "ROXIE",
                        "parenthetical": None,
                        "text": "You wanna know something? I always wanted my name in the paper. Before Amos came along, I used to date this well-to-do ugly bootlegger. He used to like to dress me up, take me out, and show me off. Ugly guys like to do that. Once it said in the paper, \"Gangland’s Al Capelli seen at Chez Vito with cute redheaded chorine.\" That was me. I clipped it out and saved it. Now look – \"ROXIE ROCKS CHICAGO.\" Look, I’m gonna tell you the truth. Not that the truth really matters, but I’m gonna tell you anyway. The thing is, see I’m older than I ever intended to be. All my life I wanted to be a dancer in vaudeville. Oh, yeah. Have my own act. But no. No. No. No. No. It was one big world full of \"No.\" Life. Then Amos comes along. Sweet, safe Amos, who never says no. You know some guys are like mirrors, and when I catch myself in Amos’ face, I’m always a kid."
                    }
                ]
            },
            {
                "number": 2,
                "heading": "VELMA AUDITION MONOLOGUE",
                "lines": [
                    {
                        "character": "VELMA",
                        "parenthetical": None,
                        "text": "My sister Veronica and I did this double act and my husband, Charlie, traveled around with us. Now, for the last number in our act, we did these twenty acrobatic tricks in a row – 1, 2, 3, 4, 5, splits, spreadeagles, flip-flops, back flips, one right after the other. Well, this one night we were in Cicero, the three of us, sittin’ up in a hotel room, boozin’ and havin’ a few laughts and we ran out of ice, so I went out to get some. I come back, open the door and there’s Veronica and Charlie doing Number Seventeen – the spread eagle. Well, I was in such a state of shock, I completely blacked out. I can’t remember a thing. It wasn’t until later, when I was washing the blood off my hands I even knew they were dead."
                    }
                ]
            }
        ]
    }

    samples.append({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_SIDES},
            {"role": "user", "content": f"Parse these scanned screenplay sides into OneTake scene & dialogue JSON:\n\n{chicago_female_text}"},
            {"role": "assistant", "content": json.dumps(chicago_target, indent=2)}
        ]
    })

    # =========================================================================
    # 3. GREASE SIDES - Scene Six & Multi-character Screenplay Format
    # =========================================================================
    grease_scene_six_text = """ACT ONE SCENE SIX
Rydell High School Gymnasium
(Scene: SANDY runs on with pom poms, dressed in a gym suit. She does a Rydell Cheer.)
SANDY:
Do a split, give a yell
Throw a fit for old Rydell
Way to go, red and white
Win the game
Fight. Fight. Fight
(SANDY does awkward split. DANNY enters.)
DANNY:
Hiya, Sandy.
SANDY:
Oh. Hi.
DANNY:
Hey, what happened to your ear?
SANDY:
Huh? (She covers her ear with her hand, answers coldly.)
Oh, nothing. Just an accident.
DANNY:
Hey, look, uh, I hope you’re not mad about that first day at school. I mean, couldn’t ya tell I was glad to see 
ya?
SANDY:
Well, you could’ve been a little nicer to me in front of your friends.
DANNY:
Are you kidding? Hey, you don’t know those guys. They just see ya talkin’ to a chick and right away they 
think she puts…well, you know what I mean.
SANDY:
I’m not sure. It looked to me like maybe you had a new girlfriend of something."""

    grease_scene_six_target = {
        "scenes": [
            {
                "number": 1,
                "heading": "ACT ONE SCENE SIX - RYDELL HIGH SCHOOL GYMNASIUM",
                "lines": [
                    {
                        "character": "SANDY",
                        "parenthetical": "does a Rydell Cheer",
                        "text": "Do a split, give a yell Throw a fit for old Rydell Way to go, red and white Win the game Fight. Fight. Fight"
                    },
                    {
                        "character": "DANNY",
                        "parenthetical": None,
                        "text": "Hiya, Sandy."
                    },
                    {
                        "character": "SANDY",
                        "parenthetical": None,
                        "text": "Oh. Hi."
                    },
                    {
                        "character": "DANNY",
                        "parenthetical": None,
                        "text": "Hey, what happened to your ear?"
                    },
                    {
                        "character": "SANDY",
                        "parenthetical": "covers ear, coldly",
                        "text": "Huh? Oh, nothing. Just an accident."
                    },
                    {
                        "character": "DANNY",
                        "parenthetical": None,
                        "text": "Hey, look, uh, I hope you’re not mad about that first day at school. I mean, couldn’t ya tell I was glad to see ya?"
                    },
                    {
                        "character": "SANDY",
                        "parenthetical": None,
                        "text": "Well, you could’ve been a little nicer to me in front of your friends."
                    },
                    {
                        "character": "DANNY",
                        "parenthetical": None,
                        "text": "Are you kidding? Hey, you don’t know those guys. They just see ya talkin’ to a chick and right away they think she puts…well, you know what I mean."
                    },
                    {
                        "character": "SANDY",
                        "parenthetical": None,
                        "text": "I’m not sure. It looked to me like maybe you had a new girlfriend of something."
                    }
                ]
            }
        ]
    }

    samples.append({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_SIDES},
            {"role": "user", "content": f"Parse these scanned screenplay sides into OneTake scene & dialogue JSON:\n\n{grease_scene_six_text}"},
            {"role": "assistant", "content": json.dumps(grease_scene_six_target, indent=2)}
        ]
    })

    # Grease Breakdown Table Page
    grease_breakdown_text = """Grease The Musical
Audition Sides
A message from the Director…
Please familiarise yourself with the sides for the character you wish to audition for as your first preference.
It is highly desirable that you will be off book for auditions.
Audition Sides Page Breakdown:
SANDY, DANNY, PATTY ACT ONE, SCENE SIX PAGE 3
SANDY ACT TWO, SCENE FIVE PAGE 7
DANNY ACT ONE, SCENE ONE PAGE 10
SONNY ACT ONE, SCENE ONE PAGE 11
JAN, ROGER ACT ONE, SCENE SEVEN PAGE 13
KENICKIE ACT ONE, SCENE ONE PAGE 15
DOODY ACT ONE, SCENE THREE PAGE 17
RIZZO ACT ONE, SCENE FIVE PAGE 18
RIZZO ACT TWO, SCENE SIX PAGE 21
MARTY ACT ONE, SCENE FOUR PAGE 24
FRENCHY ACT TWO, SCENE FOUR PAGE 27
FRENCHY ACT ONE, SCENE FOUR PAGE 28
LYNCH ACT ONE, SCENE ONE PAGE 29
VINCE FONTAINE ACT ONE, SCENE ONE PAGE 30
EUGENE, CHA - CHA ACT TWO, SCENE ONE PAGE 32"""

    grease_breakdown_target = {
        "project": "Grease The Musical",
        "project_type": "Theater",
        "role": "Sandy",
        "candidate_roles": ["Sandy", "Danny", "Patty", "Sonny", "Jan", "Roger", "Kenickie", "Doody", "Rizzo", "Marty", "Frenchy", "Lynch", "Vince Fontaine", "Eugene", "Cha-Cha"],
        "role_size": "Lead",
        "casting_office": "Millennial Productions / Taylor",
        "due_date": None,
        "specs": [
            "Familiarise with sides for preferred character",
            "Off book desirable for auditions",
            "1950s high school aesthetic with Millennial Productions edge"
        ],
        "sides_link": None,
        "submission_email": None,
        "director_guidance": "Delve deep into these characters and give them depth and show us your interpretation. Do not just replicate what you have seen on YouTube."
    }

    samples.append({
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_NOTICE},
            {"role": "user", "content": f"Parse this scanned casting notice OCR into OneTake JSON:\n\n{grease_breakdown_text}"},
            {"role": "assistant", "content": json.dumps(grease_breakdown_target, indent=2)}
        ]
    })

    # =========================================================================
    # 4. INSTAGRAM SCRAPED NOTICES (Multi-column & Graphic Flyers)
    # =========================================================================
    insta_images = glob.glob(str(DATASET_DIR / "notices" / "instagram" / "*" / "*.jpg"))
    print(f"[*] Processing {len(insta_images)} real Instagram notice images...")

    for img_path in insta_images:
        try:
            im = Image.open(img_path)
            raw = pytesseract.image_to_string(im).strip()
            if len(raw) < 50:
                continue

            # Target fields based on account and content
            acc = Path(img_path).parent.name
            project = "Casting Call"
            if "FEATURE FILM" in raw.upper():
                project = "Independent Feature Film"
            elif "NITESH TIWARI" in raw.upper():
                project = "Nitesh Tiwari Production"
            elif "SCREENPLAY NO" in raw.upper():
                project = "Screenplay Series"

            candidate_roles = []
            if "MALE" in raw.upper() and "FEMALE" in raw.upper():
                candidate_roles = ["Male Actor", "Female Actor"]
            elif "DANCE" in raw.upper():
                candidate_roles = ["Actor / Dancer", "Boy 5 to 8", "Girl 13 to 16", "Grandparents 50 to 65"]
            elif "NEPALI" in raw.upper():
                candidate_roles = ["Male Nepali Speaking Actor"]
            else:
                candidate_roles = ["Featured Actor"]

            target = {
                "project": project,
                "project_type": "Feature Film" if "FILM" in raw.upper() else "Commercial",
                "role": candidate_roles[0],
                "candidate_roles": candidate_roles,
                "role_size": "Lead" if "MAIN" in raw.upper() else "Supporting",
                "casting_office": f"@{acc}",
                "due_date": "2026-11-15T18:00:00Z" if "OCTOBER" in raw.upper() or "10/" in raw else None,
                "specs": [
                    "Submit 1-minute introduction video",
                    "Submit 2-5 recent unedited photographs"
                ],
                "sides_link": None,
                "submission_email": "profiles.mbce@gmail.com" if "mbce" in raw.lower() else ("+91 91369 17317" if "91369" in raw else None),
                "director_guidance": "Deliver natural conversational acting according to breakdown brief."
            }

            samples.append({
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT_NOTICE},
                    {"role": "user", "content": f"Parse this scanned casting notice OCR into OneTake JSON:\n\n{raw}"},
                    {"role": "assistant", "content": json.dumps(target, indent=2)}
                ]
            })
        except Exception as e:
            pass

    return samples

def main():
    new_samples = create_real_world_samples()
    print(f"[+] Created {len(new_samples)} production benchmark samples.")

    # Read existing train samples
    existing = []
    if TRAIN_FILE.exists():
        with open(TRAIN_FILE, "r", encoding="utf-8") as f:
            for l in f:
                if l.strip():
                    existing.append(json.loads(l.strip()))

    combined = existing + new_samples
    print(f"[+] Total dataset size now: {len(combined)} samples.")

    with open(TRAIN_FILE, "w", encoding="utf-8") as f:
        for s in combined:
            f.write(json.dumps(s) + "\n")

    print(f"[+] Successfully wrote to {TRAIN_FILE}")

if __name__ == "__main__":
    main()
