OneTake / Pilgrimage Research Report
====================================

Research objective
------------------
Evaluate the public Pilgrimage casting materials as realistic input for
OneTake's PDF/OCR ingestion, NoticeParser, ScriptParser, and Foundation Model
enrichment. Prepare evidence and acceptance criteria for a separate
implementation tool.

Primary sources
---------------

Official casting page:
https://www.kalnaga.com/pilgrimage/casting.html

Project homepage:
https://www.kalnaga.com/

Public application form:
https://airtable.com/appirbnBwh72CqYVi/shr3xUTQOlbqllibP

Official sides PDF linked by the casting page:
https://www.kalnaga.com/pilgrimage/Pilgrimage_Casting_Sides.pdf

Local test copy:
/Users/user76/Downloads/Pilgrimage_Casting_Sides.pdf

Source reliability
------------------

The casting page and homepage are first-party sources maintained on the
director's domain. They are high-confidence evidence for the project's own
advertised details, but not independent confirmation of compensation,
schedule, deadline, or casting claims.

The public Airtable form was identified from the official page. Its contents
were not treated as ground truth because the browser response exposed only a
browser-compatibility shell.

Instagram profiles were checked without login, private access, or
anti-automation bypass:

- https://www.instagram.com/kalnaga/
- https://www.instagram.com/humairaghilzai/
- https://www.instagram.com/bridgetteduttaportman/

The profiles were reachable or returned Instagram shell/error content, but no
publicly readable post that independently verified Pilgrimage was available.
No Instagram URL or embedded Instagram post was found in the official casting
page HTML. Instagram is therefore an unresolved source, not a test fixture.

Search engines were also checked for combinations of Pilgrimage, the
playwrights, director, venue, and Instagram. Results were noisy and mostly
unrelated generic pages; no independent social result was accepted.

Confirmed project facts
-----------------------

- Title: Pilgrimage
- Format: new play / stage reading
- Playwrights: Humaira Ghilzai and Bridgette Dutta Portman
- Director: Khaled Abol Naga (Kal)
- Venue: The Lab at Georgetown University
- Address advertised on casting page: 1801 35th St NW, Washington, DC 20007
- Publicly advertised compensation: $350 for the reading
- Roles: Noor, Maryam, Nadia, Sosan, Fatima
- Cultural setting: Afghan American Muslim women and Islamic ritual/cultural
  context associated with Mecca and the Kaaba
- Official sides: one PDF covering all five roles

Role facts
----------

Noor:
- She/her
- Early 60s
- Afghan American
- Afghan dialect in spoken English is important
- Islamic prayer gestures and Dari familiarity are listed as advantages

Maryam:
- She/her
- Mid-30s
- Afghan American
- American English with some Dari
- Afghan family-dynamics fluency is an advantage

Nadia:
- She/her
- Mid-30s
- Afghan American
- American English with some Dari
- Afghan family-dynamics fluency is an advantage

Sosan:
- She/her
- Early 30s
- Afghan American
- American English with some Dari
- Afghan family-dynamics knowledge is preferred

Fatima:
- She/her
- Mid-30s
- Black American
- Muslim convert
- No accent required
- Familiarity with Islamic practices and convert experience is an advantage

Submission requirements confirmed on the casting page
------------------------------------------------------

- MP4/H.264
- Horizontal/landscape only
- 1080p preferred
- 720p minimum
- Maximum 500 MB
- Maximum 2 minutes including slate
- Filename pattern: LASTNAME_FIRSTNAME_ROLE.mp4
- Slate must state name, pronouns, role, and city
- Upload options: YouTube (unlisted accepted), Vimeo, or Google Drive
- Applications reviewed on a rolling basis
- Deadline: October 15, 2026
- Contact: kal@kalnaga.com
- Separate video per character when reading for multiple roles

Schedule discrepancy requiring product-safe handling
-----------------------------------------------------

The casting page advertises the stage reading as November 13-16, 2026.
The project homepage's Now/Next section independently says November 11-16,
2026. This is a real source conflict.

The parser must not silently choose the stage-reading dates as the
self-tape deadline. The correct audition due date from the casting page is
October 15, 2026. Stage/rehearsal/reading dates should be ignored by
NoticeParser.detectDate unless the product has a separate event-date field.

Local PDF evidence
------------------

The local PDF has 6 pages and approximately 12,530 characters when extracted
with pypdf. It includes a character index and role-specific sides.

Expected ScriptParser results from the local PDF:

    Noor: 1 scene
    Maryam: 2 scenes
    Nadia: 2 scenes
    Sosan: 1 scene
    Fatima: 2 scenes

The PDF contains role-specific headings such as:

    THE SIDE — Noor's Confession
    SIDE A — The Phone Call
    SIDE B — The Aftermath

It also contains screenplay-adjacent metadata:

- all-caps character headers
- pronouns and age ranges
- cultural/ethnicity descriptions
- director notes
- slate instructions
- setting/action descriptions
- bracketed performance instructions
- dialogue with curly punctuation and em dashes

Observed parser baseline
------------------------

Before the targeted fixes, parsing the official page visible text (~4,776
characters) produced:

- project: The World (wrong; expected Pilgrimage)
- role: This Role (wrong)
- candidate roles: This Role (wrong)
- deadline: missing
- casting office: inferred from venue/footer text (wrong)
- email: detected correctly
- landscape: detected correctly

The same project/role/deadline failures occurred at 2,500, 3,000, and full
page input sizes. This proves those failures were deterministic-parser
problems, not Foundation Model character caps.

After targeted parser changes, direct Swift compilation/testing produced:

Official page fixture:

- project: Pilgrimage
- candidate roles: Noor, Maryam, Nadia, Sosan, Fatima
- deadline: detected as October 15, 2026
- landscape: detected
- email: kal@kalnaga.com
- false casting-office inference: removed

PDF fixture:

- project: Pilgrimage
- candidate roles: Noor, Maryam, Nadia, Sosan, Fatima
- scenes: 8
- sides: detected

Foundation Model limit implications
------------------------------------

The app currently sends:

- first 2,500 characters to extractNoticeMetadata
- first 3,000 characters to refineDraftWithFoundationModel

The local PDF is ~12,530 characters. The first 2,500/3,000 characters include
the role index and early Noor/Maryam material, but exclude later role-specific
instructions and sides.

Do not increase the cap as the first response to the webpage failures: those
failures reproduced with full page text. If broader model coverage is desired,
implement explicit section-aware chunking or deterministic pre-extraction,
then send only relevant bounded sections to the model.

Recommended implementation contract
------------------------------------

NoticeParser should:

1. Prefer explicit project labels and web title patterns:
   "Casting Call — Pilgrimage"
   "Casting Call For The New Play" followed by "Pilgrimage".
2. Detect a webpage "The Characters" section containing standalone role names.
3. Keep the role blank when multiple roles are found.
4. Reject generic candidates:
   This Role, Cast, The Role, Your Role, Character, Setting, Casting Sides,
   Director Note, Slate Instruction, How To Use These Sides.
5. Parse labeled deadlines:
   Deadline: October 15, 2026
   Submission deadline - October 15, 2026
   Submit by October 15, 2026
6. Exclude event/rehearsal/shoot dates from audition due-date extraction.
7. Prefer explicit casting-office labels; do not infer an office from venue,
   footer, "Casting Call", "Casting Sides", or "Download Casting".
8. Classify the official sides PDF as sidesLink.
9. Classify Airtable/form/upload URLs as submission destination.
10. Preserve the existing context-aware URL classifier.

ScriptParser should:

1. Preserve the five-role index.
2. Keep role matching case-insensitive.
3. Attribute unlabeled dialogue after a role header to the active role.
4. Exclude Setting, Director note, slate instructions, and bracketed action.
5. Preserve side headings and normalize scene titles.
6. Handle all-caps, period, and colon cue styles.
7. Avoid treating Mecca, Kaaba, Hotel room, and prose nouns as characters.
8. Preserve dialogue punctuation and clean OCR line wraps.

Acceptance-test matrix
-----------------------

A separate implementation must pass these expected checks:

Notice page:

    project == "Pilgrimage"
    Set(candidateRoles) == {"Noor", "Maryam", "Nadia", "Sosan", "Fatima"}
    role == ""
    due == October 15, 2026
    asks contains "Slate first" when slate text is present
    asks contains "Landscape"
    destinationDetail contains "kal@kalnaga.com"
    castingOffice == "" unless explicitly labeled

PDF:

    project == "Pilgrimage"
    candidateRoles in document order
    scenes == 8
    hasSides == true

Role scene tests:

    Noor == 1
    Maryam == 2
    Nadia == 2
    Sosan == 1
    Fatima == 2

Negative cases:

- Do not use November 13-16 event dates as the self-tape deadline.
- Do not use homepage November 11-16 as the self-tape deadline.
- Do not return This Role or Cast as a candidate role.
- Do not return The World, The New Play, The Lab, or Georgetown as project.
- Do not return venue/footer text as casting office.
- Do not classify dialogue words such as landscape, city, picture, or role as
  requirements when they are not in an instruction context.

Suggested test fixtures
-----------------------

Use compact synthetic fixtures in committed XCTest files. Do not commit the
full copyrighted PDF or the full scraped page text without permission.

Keep the local PDF as a manual/uncommitted regression fixture:

    /Users/user76/Downloads/Pilgrimage_Casting_Sides.pdf

Suggested committed fixtures:

1. Web title + character section + labeled deadline + contact.
2. PDF-style character index + role headers + sides.
3. Conflicting event/rehearsal dates plus an explicit self-tape deadline.
4. Sides PDF URL plus Airtable submission URL.
5. Generic role labels ("This Role", "Cast") that must be rejected.

Validation limitations
----------------------

- Full XCTest execution was unavailable because the machine had Command Line
  Tools but not the full Xcode toolchain.
- Direct Swift compilation of the relevant model/parser sources succeeded.
- PDF extraction was validated locally with a temporary pypdf environment.
- No private or authenticated Instagram content was accessed.
- No anti-bot controls were bypassed.

Files for the next implementation tool
---------------------------------------

- Parser: /Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift
- Script parser: /Users/user76/Downloads/OneTake-iOS/OneTake/Models/ScriptParser.swift
- Foundation Model wrapper: /Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/OnDeviceIntelligence.swift
- Existing tests: /Users/user76/Downloads/OneTake-iOS/OneTakeTests/NoticeParserTests.swift
- Local PDF: /Users/user76/Downloads/Pilgrimage_Casting_Sides.pdf
