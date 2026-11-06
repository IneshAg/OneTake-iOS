# OneTake-iOS: Structure and Working

## 1. Product architecture

OneTake is a fully local iOS self-tape workflow:

```text
Casting notice
   ↓
OCR / PDF / pasted text / Share extension
   ↓
NoticeParser.Draft
   ↓
User review and correction
   ↓
Persisted Audition
   ↓
Learn lines → Record slate/headshots/scenes
   ↓
Select takes
   ↓
Tape Check
   ↓
Preview and package
   ↓
MP4 / ZIP / Photos
   ↓
Share Sheet or iCloud download link
```

The app has no normal backend. Structured data is saved as JSON on-device, recordings are stored in the app’s Documents directory, and iCloud is used only when the user explicitly chooses link delivery.

---

## 2. Repository and build structure

The Xcode project is generated from `project.yml`.

### Main targets

#### Main application
`OneTake/`

Contains:
- SwiftUI screens
- domain models
- parsing
- camera capture
- OCR
- line-learning
- media analysis
- export and packaging
- account authentication
- reminders
- persistence

#### Widget extension
`OneTakeWidgets/`

Provides:
- Home Screen widget
- Lock Screen widget
- Live Activity
- Dynamic Island countdown
- iCloud upload progress display

#### Share extension
`OneTakeShare/`

Accepts shared:
- text
- URLs
- images
- PDFs

It cannot directly open the main application, so it saves the shared content into the shared App Group inbox.

#### Shared code
`Shared/`

Contains code compiled into both the app and extensions:
- `ShareInbox.swift`
- `WidgetSnapshot.swift`
- `AuditionActivity.swift`

#### Tests
`OneTakeTests/`

Tests cover:
- model behavior
- notice parsing
- script parsing
- persistence recovery
- camera/image helpers
- media export
- ZIP archives
- tape-check filtering
- package/sent behavior
- tape preview behavior

---

## 3. Application startup and navigation

The entry point is `OneTakeApp.swift`.

### Startup sequence

`OneTakeApp`:
1. Creates one shared `AppStore`.
2. Loads persisted state through `AppStore.init()`.
3. Shows onboarding if `isOnboarded == false`.
4. Shows the main tab interface otherwise.
5. Applies the selected appearance:
   - system
   - light
   - dark
6. Validates stored Apple authentication state.
7. Handles deep links.
8. Flushes persistence when the app becomes inactive or enters the background.
9. Checks the Share Inbox when returning to the foreground.
10. Refreshes widgets and Live Activities.

The central state object is `AppStore` in `AppStore.swift`.

It owns:
```text
auditions
takes
practice pieces
profile/slate information
account
navigation paths
current tab
camera flow
add-audition state
share-inbox state
```

### Navigation model

Routes are represented by the `Route` enum. Important routes include:
- audition detail
- prepare lines
- practice options (full-scene practice, prompts, cold read, audio gap, audio walk)
- record reader
- shoot setup
- takes
- tape check
- package
- preview
- headshots
- profile
- practice
- privacy
- notifications

Camera-related flows use a separate `CameraFlow` enum because recording screens are presented as full-screen covers rather than normal navigation destinations.

This separation prevents camera capture from becoming entangled with the tab navigation stack.

---

## 4. Core data model

The main data structures are in `Models.swift`.

### `Audition`
An audition contains:
- project title
- project type
- role
- role size
- casting office
- due date
- notice requirements
- checklist pieces
- parsed script scenes
- original script text
- submission destination
- selected package format
- status
- slate video
- requested full-body shot video
- export URLs
- ZIP archive URL
- iCloud share link
- callback round
- casting notes
- private actor notes
- optional structured notice details, role breakdowns, dates, side materials, source references,
  evidence excerpts, and submission instructions

Its state is:
```text
due → ready → sent
```
`ready` means all required pieces are complete. Optional pieces do not block packaging.

### Structured casting-notice records

The optional notice metadata types in `Models.swift` keep useful casting information separate
without breaking older saved `Audition` records:

| Model | Stored information |
| --- | --- |
| `AuditionProjectDetails` | Synopsis, production company/team, pay and union terms, NDA, casting/production locations, travel notes |
| `AuditionDate` | Typed submission, audition, callback, rehearsal, production, or performance dates, with source page/text when found |
| `AuditionRoleBreakdown` | Role description, age/gender wording when explicitly present, eligibility notes, and linked side IDs |
| `AuditionSideMaterial` | Side title/number, associated role, page/source reference, and extracted text |
| `AuditionSource` | Imported document or page identity, kind, URL, page count, and parent document reference |
| `AuditionFieldEvidence` | Field name, source page, and a short surrounding excerpt |
| `AuditionSubmissionInstructions` | Slate directions, orientation, video/take counts, accepted formats, submission route, and filename rule/template |

`NoticeParser` fills these records from OCR/PDF, pasted text, scans, and shared files. Page records
retain their parent document ID so a multi-file share can distinguish a notice from its sides. The
records are evidence-oriented: demographic fields are only populated from explicit text; this parser
does not infer ethnicity, skills, or missing requirements. The actor's editable review fields remain
the source of truth for the main project, role, and deadline.

Apple Foundation Models are a secondary refinement step for supported devices. After refinement,
the structured records and evidence are rebuilt from the grounded draft so they stay in sync with
the selected role and source. The production notice path does not route notice text to Gemini or
Ollama, and it does not use a Core ML notice parser.

### `Piece`
A `Piece` represents one checklist item:
- headshot
- slate
- full-body shot (only when requested separately)
- scene

Each piece has:
- title
- detail
- completion state
- optional/required state

The audition’s `nextPiece` drives the “Next” experience throughout the app. It follows the stored
piece order; new auditions default to **Headshots → Slate → Scenes**, inserting a separate **Full-body shot** only when the notice asks for a separate head-to-toe clip. If the notice includes full-body framing in the slate, it stays within the slate. Legacy full-length pieces are migrated to the new label.
Actors can change that order in Edit Details by tapping **Edit** in Flow Order and dragging pieces.
Optional work can appear in the chosen order while required work remains, but optional pieces do not
prevent preview once all required pieces are complete.

### `ScriptScene`
A scene contains:
- scene number
- title
- slugline/heading
- script lines
- estimated duration

### `ScriptLine`
Each line contains:
- character
- text
- `isMine`

The actor’s role determines which lines are marked as the actor’s own lines.

### `Take`
A take contains:
- take number
- duration
- timestamp
- selected/circled state
- private notes
- media URL
- audition ID
- scene index

Only one take per audition/scene is normally circled for delivery.

### `PracticePiece`
A practice piece stores a reusable rehearsal scene, including:
- title
- character
- script scene
- lines learned
- total actor lines
- recorded practice count

---

## 5. Persistence and file storage

Persistence is intentionally split into structured state and media files.

### Structured state
`Persistence.swift` stores a `PersistedState` object as JSON:
```text
Application Support/OneTake/state.json
```

The JSON contains:
- auditions
- takes
- practice pieces
- slate/profile data
- onboarding state
- account data

Media files are not embedded into JSON. The JSON stores URLs pointing to files.

### Resilient decoding
Persistence uses lossy per-record decoding.

If one audition is corrupted:
```text
Good audition
Damaged audition
Another audition
```
the good records still load. The damaged record is dropped and the original unreadable JSON is preserved as:
```text
state-unreadable-<timestamp>.json
```
This prevents one malformed record from destroying all application state.

### Debounced writes
`AppStore` observes data mutations through `didSet` and schedules a delayed save.

This avoids writing to disk for every keystroke while editing fields.

When the application backgrounds, `flushPersistence()` cancels the delayed save and writes immediately.

### Media storage
`MediaStore` stores recordings under the app’s Documents directory.

Typical folders include:
```text
Documents/
├── takes/
├── headshots/
├── Exports/
├── reader-tracks/
├── audition-<uuid>/
└── practice-<uuid>/
```

Temporary camera recordings are moved into permanent storage after capture.

The app also rebases stored Documents URLs after reinstall or container relocation so old absolute paths can still work inside the new app container.

---

## 6. Adding an audition

The primary flow is implemented in `AddAuditionFlow.swift`.

The user can import a notice through:
- clipboard paste
- Photos
- camera scan
- PDF
- plain text
- RTF
- Share extension content
- manual entry

### OCR pipeline
`NoticeOCR.swift` handles:
- Vision text recognition
- PDFKit extraction
- scanned-PDF rendering
- RTF conversion
- security-scoped file access
- image normalization
- grayscale with sampled luminance-range normalization
- dark-background detection and a separate inverted-text retry when the first pass is unreadable
- English and Hindi recognition
- readability validation

The OCR process is:
```text
Image/PDF
   ↓
Normalize orientation and size
   ↓
Enhance contrast and sharpness
   ↓
Vision OCR
   ↓
Layout reconstruction
   ↓
Plain text
```

### OCR layout reconstruction
`OCRLayoutReconstructor.swift` uses Vision bounding boxes to restore reading order.

It handles:
- vertical ordering
- horizontal ordering
- table-like key/value rows
- two-column casting breakdowns when both columns share a vertical band and have a clear center gutter
- centered uppercase screenplay cues, whose measured left margin is preserved for script parsing

If text crosses the center gutter through the body of a page, the reconstructor keeps the normal
row-order fallback instead of moving that text to the end of a column. This avoids manufacturing a
false reading order from a weak column guess.

For example:
```text
Role        Lead
Deadline    25 Nov
```
can become:
```text
Role: Lead
Deadline: 25 Nov
```
This is important because naive OCR often returns columns in the wrong order.

### Notice parsing
`NoticeParser` is currently defined inside `AddAuditionFlow.swift`.

It produces a `Draft`, not an `Audition`, so incomplete or incorrectly detected data can still be corrected.

The draft can identify:
- project
- project type
- role
- candidate roles
- role size
- casting office
- due date
- requirements
- destination
- email
- scene count
- sides
- script text
- casting notes

The draft is shown in a review screen before committing.

The OCR review is an editable checkpoint, not a read-only extraction report. Its labels separate
production/project facts, role and character information, casting notes, actor notes, delivery
requirements, and practice cue audio. The original notice image can be opened beside the extracted
values. Notice-only headings and submission checklists are excluded from script parsing unless
actual side/scene structure is found. Scene selection is consequently omitted when no sides exist.
The parser also recognizes whether slate, headshots, scenes, or résumé are optional when the notice
states that explicitly. These are still extraction suggestions; the actor can correct them before
saving.

Casting notices and script sides are represented as distinct source kinds. The actor can add or
replace sides after the notice through the Add/Replace Sides route. The current intake does not yet
present a dedicated two-step wizard that requires two separately labeled PDFs.

### Résumé handling
`ResumeStore` copies the selected file into app-owned Profile storage. Profile can hold a reusable
résumé; the OCR review can include or omit it for each audition and can replace the profile copy.
Supported imports are PDF, DOC, DOCX, RTF and plain text. A résumé becomes a blocking requirement
only when the source notice indicates it is required; “optional” wording stays optional.

### Parser refinement strategy
The production notice path has two layers:
1. deterministic on-device OCR/text extraction and rule-based notice/script parsing
2. optional Apple Foundation Models refinement on supported devices; deterministic values are retained unless a missing value can be grounded in the source

The refinement prompt includes the first-page/header text, bounded excerpts for detected roles, and
later-page windows for production and submission details. Returned pay, union, location, date,
orientation, and file-naming values must match a relevant source section before they are added.
Imprecise milestone phrases are not stored with the current date as a stand-in. The separate Core ML
notice parser helper is not connected to the production intake route; its field mapping applies the
same source checks if that experimental helper is invoked.

When Apple Foundation Models are unavailable, `ScriptParser.divideIntoThoughtUnits` provides an
offline deterministic beat split for long dialogue. OCR-recognized centered cues retain their
relative indentation through text cleanup so the script parser has both capitalization and layout
to distinguish cues from short all-caps dialogue.

OCR text, page boundaries, and deterministic parser output remain available for review. A failed or
unavailable Foundation Model pass does not block notice parsing. The research scripts under
`scripts/` are experiments and evaluation tools; they are not the app's runtime parser.

---

## 7. Script parsing

Script parsing is implemented in `ScriptParser.swift`.

### Supported dialogue formats
The parser recognizes:
```text
MAYA
Hello.

JOHN
Hi.
```
and:
```text
Maya: Hello.
John: Hi.
```

It also handles:
- screenplay scene headings
- `INT.`
- `EXT.`
- `INT/EXT`
- `SCENE 2`
- multi-role casting packets
- commercial scripts
- stage-play structures
- character descriptions
- OCR-damaged punctuation
- split contractions
- hyphenated word wrapping
- parentheticals
- watermarks and notice headers

### Scene splitting
Scenes are split when a heading is found.

Each scene receives:
- a number
- a heading
- a title
- parsed dialogue
- estimated duration

When the actor changes their role later, `AppStore.reclassifyRole()` can re-run classification from the original `scriptText`, rather than permanently relying on earlier guesses.

---

## 8. Learning lines and practice

The line-learning UI is distributed across:
- `PrepareViews.swift`
- `LineLearningViews.swift`
- `PracticeViews.swift`

The actor can use:
- full text
- first-letter prompts
- hidden actor lines
- mask-and-reveal
- meaningful-word gaps (tap a masked word to reveal a clue)
- audio gap
- audio walk
- reader playback
- speech recognition

### Speech matching
`SpokenLineMatcher` in `Models.swift` compares the recognized transcript with the expected line.

It supports:
- punctuation normalization
- contractions
- number/word equivalence
- minor pronunciation endings
- skipped filler words
- repeated words
- forward-only matching

### Meaningful-word gaps
`RecallGapSelectionStore` caches a stable set of hidden word positions for each line. On iOS 26+, it asks Foundation Models on-device to select meaning-bearing words. If that model is unavailable or fails, a deterministic local word-ranking fallback is used. Selections are cached so a line does not reshuffle between practice attempts; tapping a gap reveals that word as a temporary clue.

The forward-monotonic matching prevents common words such as “you”, “the”, or “I” from being highlighted out of sequence.

### Voice-practice review
`VoicePracticeReviewAnalyzer` extracts the audio track from a saved voice-practice take and asks
Apple Speech for on-device transcription with word timestamps. It aligns recognized words to the
actor's script lines and surfaces per-line suggestions: Looks okay, Skipped, Forgot, Hesitated or
Not in Script. A pause of around 1.25 seconds between matched words is a hesitation suggestion.
The actor can change or dismiss a suggestion. This is not a performance score; recognition can
miss accents, paraphrases or intentional acting pauses. If on-device recognition is unavailable,
the app preserves the recording and offers manual review.

### Reader audio
Reader tracks are recorded line-by-line and stored locally. The reader audio is then played during rehearsal and shooting.

The app increments `readerTrackVersion` whenever reader recordings change so views backed by disk files refresh correctly.
Existing reader cues can be scrubbed and trimmed. The first unedited recording is retained as an
original copy, and the UI can restore it after confirmation. A failed trim leaves the currently
installed cue intact.

---

## 9. Camera and shooting

Camera functionality is in `CameraController.swift` and the large shooting UI is in `ShootViews.swift`.

### AVFoundation pipeline
`CameraController` manages:
- video permission
- microphone permission
- front/back camera selection
- 1080p capture
- movie output
- photo output
- preview session
- zoom
- orientation
- exposure
- focus
- white balance
- audio level
- recording state
- face guidance
- body-pose guidance
- open-palm detection

States include:
```text
idle
ready
recording
paused
failed
```

### Shooting sequence
The normal shoot flow is:
```text
Camera setup
   ↓
Camera check
   ↓
Slate
   ↓
Requested separate full-body shot
   ↓
Scene 1
   ↓
Scene 2
   ↓
...
```
The app can also open directly at a specific scene.

### Recording behavior
The app supports:
- front or rear camera
- pinch-to-zoom
- 1× / 1.5× / 2× zoom controls
- upright output orientation
- non-mirrored saved front-camera video
- optional countdown
- hold-to-stop recording
- volume button capture
- Camera Control capture
- AirPods stem capture
- voice “Action” and “Cut” commands
- prompter-following speech recognition
- reader audio playback

The saved camera output is moved from temporary storage into permanent Documents storage before being added to the app state.

Camera check shows preparation guidance before recording, including a notice-orientation warning
and live microphone activity when the audio connection exposes metering. Resolution choices use
the supported camera preset list. On Simulator, choosing a resolution only changes the app's
preference; it does not make simulator camera capture possible. Shoot setup does not display a
storage estimate.

---

## 10. Headshots

Headshots are separate from video takes.

They are stored through `HeadshotStore` in `Persistence.swift`.

Supported angles include:
- front
- left profile
- right profile

The app stores:
- original image
- cropped/framed image
- audition-specific headshots
- profile headshots

Headshot images are cached because repeatedly decoding JPEG files while scrolling would cause unnecessary file I/O.

After audition headshots are saved, the screen shows the saved set, thumbnails and the stored crop
ratio for each angle, with a clear next action to continue to slate. Completion is derived from
the actual saved angle files rather than the number of occupied slots.

The optional pose guide uses on-device Vision/Core ML logic and does not upload pose data.

---

## 11. Takes and selection

Take management is handled by `AppStore` and `TakesViews.swift`.

Important rules:
- every scene can have multiple takes
- take numbering never reuses a previous number
- the first take is automatically circled
- circling a take uncircles all other takes for that same audition and scene
- takes from other auditions are excluded
- trimming creates a replacement file
- modifying a take invalidates previous exports
- private take notes are never included in delivery

The selected take is identified by:
```text
auditionID + sceneIndex + isCircled
```

---

## 12. Tape Check

Tape analysis is implemented in `TapeAnalyzer.swift`.

It analyzes exactly the clips that will be delivered, using the same clip-selection logic as preview and export.

### Video checks
The analyzer uses:
- AVAssetImageGenerator
- Vision face detection
- Core Image brightness measurement
- preferred video transforms
- frame sampling

It checks:
- face presence
- framing
- headroom
- horizontal centering
- face size/distance
- head turn/yaw
- brightness
- landscape orientation
- HD dimensions
- clip readability

### Audio checks
It examines:
- audio presence
- volume level
- clipping
- quiet audio
- pauses
- possible clipped opening

### Package checks
It verifies:
- slate availability
- full-length availability when requested
- scene coverage
- total duration
- landscape requirement
- HD requirement
- file naming

The analyzer distinguishes:
```text
technical findings
optional timing prompts
passed checks
```

Optional timing prompts do not reduce the technical readiness score.

Analysis results are cached using the file path, modification date, file size, and label, so unchanged clips do not need to be analyzed again.

Tape Check also lists Slate, a requested separate Full-body shot, and each available scene as separate review entries.
Opening an entry plays that clip and limits the displayed technical findings to that clip; its
retake/edit action routes back to that element's capture or take-selection flow. The overall Tape
Check and full preview remain separate destinations.

---

## 13. Preview and export

### Preview
`TapePreviewView.swift` uses the same `MediaExporter.clips()` method used by Tape Check and final export.

This prevents a preview/export mismatch.

A tape consists of:
```text
Slate
Full-body shot (if separately requested)
Circled Scene 1 take
Circled Scene 2 take
...
```
The slate can be configured at the start or end.

### Media composition
`MediaExporter.swift` creates an `AVMutableComposition`.

It:
1. loads each clip
2. reads its duration
3. inserts video tracks
4. inserts audio tracks
5. preserves preferred transforms
6. fits portrait/landscape material into a common canvas
7. creates chapter metadata
8. exports an MP4

Orientation is explicitly reapplied because copying raw frames alone would lose the recorded transform.

### File naming
The final file name defaults to the actor profile and audition:
```text
LAST_FIRST_ROLE_PROJECT.mp4
```
For example:
```text
RAO_ASHA_MAYA_THELASTSUMMER.mp4
```
The generated name is sanitized to uppercase letters and numbers.

When a casting notice provides a recognizable naming rule, `NoticeParser` stores both the original
rule and a normalized template. `Audition.deliverableFileName` substitutes supported tokens
(`{name}`, `{firstName}`, `{lastName}`, `{role}`, `{project}`, `{side}`, `{scene}`, `{take}`,
`{song}`) when the required values are available, then sanitizes the result. Separate clip exports
add scene/side/take labels when the casting template does not contain those tokens. If a required
token is unavailable or no usable template was found, the app uses its existing default naming
pattern. A filename template can also be edited in Package.

### ZIP packaging
`ZipArchive.swift` implements a custom store-only ZIP writer.

The archive can contain:
```text
Videos/
Headshots/
```

It streams files rather than loading complete videos into memory.

It also validates extracted paths to prevent archive path traversal when restoring backups.

### Current package choices and recovery
Package format and destination are chosen in sheets. A compact submission check summarizes those
choices near the top, while filename, duration, size and slate details are collapsed under file
specifications. A detected required format may be preselected. If the notice does not specify a
format, the check asks the actor to choose one.

---

## 14. Sending

Package behavior is in `PackageViews.swift`.

The current format picker offers:
- combined MP4
- separate clips ZIP
- headshots only
- full package

The destination picker offers destinations such as:
- Actors Access
- Backstage
- Casting Networks
- Spotlight
- direct email
- Files/AirDrop
- email or link

The package UI includes sign-in entry from both Profile and destination selection. Apple and Google
providers are not configured in the current build, so hosted link creation is not verified or
available there. If packaging fails, the actor can return to package options or retry without being
trapped on the error screen. Combined video remains one of the current format choices; removing it
and reducing sharing to exactly two actions has not been implemented.

### Local delivery
For ordinary destinations, OneTake:
1. exports the MP4 and/or ZIP
2. builds share items
3. opens the iOS Share Sheet
4. marks the audition as sent only after the share completes successfully

The app does not pretend that a casting site accepted the submission.

### Hosted-link delivery status
`CloudLink.swift` contains the “Email or link” path. The app's current build does not have Apple or
Google sign-in providers configured, so hosted-link delivery must be treated as unavailable until
provider setup and a successful end-to-end upload test are completed. The flow below describes the
intended implementation, not a verified capability in this build.

The sequence is:
```text
Sign in if necessary
   ↓
Copy export into iCloud Drive container
   ↓
Wait for upload completion
   ↓
Ask iCloud to publish the file
   ↓
Store public link and expiration
   ↓
Show link in Sent screen
```

The local export remains intact because iCloud receives a copy.

---

## 15. Authentication

`AccountAuth.swift` supports:
- Apple authentication
- Google authentication

The app is guest-first:
- recording works without an account
- parsing works without an account
- export works without an account
- sharing through AirDrop/Files/Mail works without an account

Authentication is only required when publishing an iCloud link.

The current open configuration disables Apple Sign In and uses placeholder Google credentials until configured in `project.yml`.

---

## 16. Widgets, reminders, and Live Activity

### Widgets
The app writes a compact snapshot through `WidgetSnapshot.swift`.

The widget does not read the full app state. It only receives:
- audition ID
- project
- role
- due date
- checklist statuses

`NextAuditionWidget.swift` displays:
- nearest upcoming audition
- time remaining
- readiness dots
- next piece
- following audition

### Reminders
`Reminders.swift` schedules local notifications for:
- morning of deadline
- two hours before deadline
- optional daily practice reminder

Reminders are fully rebuilt whenever auditions change, preventing stale alerts after deletion, completion, or deadline edits.

### Live Activity
`AuditionActivity.swift` defines the Live Activity data.

`AuditionLiveActivity.swift` shows:
- countdown
- project and role
- checklist progress
- upload progress during iCloud sending
- Dynamic Island status

Deep links use:
```text
onetake://audition/<uuid>
```

---

## 17. End-to-end example

A typical user journey is:
1. User shares a PDF casting notice to OneTake.
2. `ShareViewController.swift` copies the PDF into the shared inbox.
3. The app returns to the foreground.
4. `OneTakeApp` detects the inbox item.
5. `AddAuditionFlow` extracts PDF text or performs OCR.
6. `NoticeParser` creates a draft.
7. User reviews and corrects project, role, date, and requirements.
8. `ScriptParser` creates scenes and identifies the actor’s lines.
9. `AppStore` commits the draft as an `Audition`.
10. The audition checklist appears.
11. User records reader tracks.
12. User rehearses lines.
13. User records slate and scenes.
14. Each recording becomes a `Take`.
15. User circles preferred takes.
16. `TapeAnalyzer` checks the final clip set.
17. `MediaExporter` previews and merges the selected clips.
18. `ZipArchive` creates the separate deliverable archive.
19. User shares files or publishes an iCloud link.
20. The audition becomes `.sent`.
21. Widgets, reminders, and Live Activity update.

---

## 18. Important implementation invariants

The codebase consistently protects several important invariants:

- **Media files live on disk; JSON stores metadata and URLs.**
- **Only circled takes are eligible for final export.**
- **Take selection is scoped by audition and scene.**
- **Optional pieces do not block packaging.**
- **Tape Check, Preview, and Export use the same clip-selection function.**
- **AI guidance does not replace deterministic media measurements.**
- **Reader recordings are local and versioned for UI refresh.**
- **Corrupt records do not destroy all saved state.**
- **Sending is only marked complete after the actual share action succeeds.**
- **Local sharing does not require an account.**
- **iCloud link delivery does require an account and iCloud availability.**
- **Widgets receive a small snapshot instead of the full private app database.**

> [!NOTE]
> **Configuration Source of Truth**: `project.yml`, `OneTake.entitlements`, and `WidgetSnapshot.swift` use `group.com.srmist.onetake` as the App Group identifier. The project configuration and entitlements are the build-time source of truth.
