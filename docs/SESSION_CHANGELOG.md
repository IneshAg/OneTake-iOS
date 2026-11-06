# OneTake-iOS — Session Changelog

A running log of every change made during active development sessions, in reverse-chronological order. Each entry maps to a commit, describes what was fixed or built and why, and notes any error that had to be corrected along the way.

> Author for all commits: **Inesh Agarwal \<ineshag123@gmail.com\>**
> Remotes: `origin` → `IneshAg/OneTake-iOS`, `team` → `iOS-Team-10/OneTake`

---

## Session — 6 November 2026

### `e4b8a1c` — Full Casting Architecture & Gap Resolution (Material Kinds, Dates, Roles, Terms, Evidence)
**Files changed:** `Models.swift`, `AddAuditionFlow.swift`, `AuditionDetailView.swift`, `Components.swift`, `NoticeParserTests.swift`, `README.md`

**Why:** Addresses all remaining model and UI gaps identified in casting workflow audits:
1. Rich data extracted by the parser was previously never surfaced to the actor.
2. Only a single tape deadline date was shown, losing callback, rehearsal, and shoot dates needed to check booking conflicts.
3. Multiple candidate roles were shown as a flat text list with no character breakdowns or mapped sides.
4. Non-dialogue auditions (solo monologue, song cuts, dance reels, slate-only) were treated as broken sides imports.
5. Extracted facts lacked source provenance attribution.

**What was done:**

- **Audition Material Kinds (`AuditionMaterialKind`)**:
  - Added enum: `.sides` (Script Sides), `.monologue` (Solo Monologue), `.song` (Song / Vocal), `.movement` (Movement / Dance), `.slateOnly` (Slate / Intro Only).
  - Built interactive `AuditionMaterialKindPicker` segmented bar in `NoticeReviewView` and `OCRReviewSheet`.
  - Added type selector to `EditAuditionSheet` and an audition kind badge to `AuditionDetailView`'s header.
  - Adapted piece/scene generation: `.slateOnly` requires no script dialogue and suppresses sides validation errors; `.monologue` automatically builds continuous solo speech without reader pauses; `.song` and `.movement` generate tailored performance staging.

- **Milestone Dates Timeline (`MilestoneDatesListCard`)**:
  - Surfaced `importantDates` with kind-specific icons, labels (Tape Deadline, Callback Window, Rehearsals, Shoot Dates), and formatted dates.
  - Added milestone list cards to `NoticeReviewView`, `OCRReviewSheet`, and `AuditionDetailView`.

- **Production Call & Terms Card (`ProjectDetailsCard`)**:
  - Surfaced synopsis, pay terms / rate, union status, filming location, and creative team in both the intake review and `AuditionDetailView`.

- **Rich Role Breakdowns (`RoleBreakdownCard`)**:
  - Candidate roles now display character name, age range, gender, and description excerpt.
  - Selecting a role automatically loads its character notes into casting guidance and links associated sides.

- **Source Provenance Attribution (`FieldEvidenceSection`)**:
  - Collapsible grounding section showing the document page and exact quoted excerpt from which each field was extracted.

- **Unit Tests (`NoticeParserTests.swift`)**:
  - Added `testSlateOnlyAuditionDoesNotRequireSides`
  - Added `testSoloMonologueGeneratesSoloSceneWithoutReaderLines`
  - Added `testNoticeParserExtractsMilestoneDatesAndProjectDetails`
  - All 178 tests passing (0 failures).

---

### `b8d0c75` — Notice-aware file naming + branded ZIP clips + filename template editor
**Files changed:** `AppStore.swift`, `MediaExporter.swift`, `Models.swift`, `AddAuditionFlow.swift`, `PackageViews.swift`, `MediaExporterTests.swift`

**Why:** Research into real-world casting workflows confirmed that casting portals and theater companies enforce strict, bespoke filename conventions (`FirstName.LastName.ROLE.SceneTake`, `LAST_FIRST_SIDE_NUMBER.mp4`, etc.). Tapes with wrong filenames are frequently auto-rejected by platform portals before a CD ever sees them.

**What was done:**

- **`MediaExporter.makeSeparateArchive`** — Every clip inside the separate-clips ZIP is now prefixed with the actor/role/project token derived from `Audition.clipFileName()`:
  - Before: `Videos/Scene_1_-_Take_3.mov`
  - After: `Videos/RAO_ASHA_MAYA_THELASTSUMMER_Scene_1_TAKE_3.mov`
  - Slate: `RAO_ASHA_MAYA_THELASTSUMMER_SLATE.mov`
  - Full-length: `RAO_ASHA_MAYA_THELASTSUMMER_FULL_LENGTH.mov`
  - Side number included when `AuditionSideMaterial.sideNumber` is set.

- **`Audition.clipFileName()`** — Routes through `submissionInstructions.fileNameTemplate` when one is set, substituting tokens `{firstName}`, `{lastName}`, `{name}`, `{role}`, `{project}`, `{side}`, `{scene}`, `{take}`, `{song}`. Falls back to the app's stable default when no template is present.

- **`Audition.deliverableFileName()`** — Extended with `side`, `scene`, `take`, `song` parameters to support notice-extracted templates on the merged MP4 filename too.

- **`AppStore.setFileNameTemplate(_:for:)`** — New mutation method that persists a custom template to `submissionInstructions.fileNameTemplate` and invalidates any stale export so the next package uses the new name.

- **`PackageViews` — Filename row is now tappable:** Opens `FileNameTemplateSheet`, a bottom sheet with:
  - Monospaced text field with live preview of the actual output filename.
  - One-tap token chip grid: `{firstName}`, `{lastName}`, `{name}`, `{role}`, `{project}`, `{side}`, `{scene}`, `{take}`.
  - **Reset to Default** button that removes the custom template.
  - A `pencil.circle.fill` indicator on the row when a custom template is active.

- **`MediaExporterTests`** — Updated 4 stale assertions from generic clip names to new prefixed names. Added 2 new tests:
  - `testClipFileNamesUseCustomTemplateWhenSet` — verifies custom template substitution.
  - `testDefaultFileNameIsUsedWhenNoTemplateSet` — verifies fallback to `LAST_FIRST_ROLE_PROJECT` prefix.

**Tests:** 175 / 175 passed (2 new).

---

### `501f90c` — Custom photo picker design saved to docs
**Files changed:** `docs/FUTURE_ENHANCEMENTS.md` *(new)*, `docs/CODEBASE_OVERVIEW.md`, `docs/illustrations/concepts/custom_photo_picker_spec.jpg` *(new)*

**Why:** User uploaded a mockup of a bespoke in-app photo picker and explicitly asked to document it for future implementation rather than build it immediately. The system `PHPickerViewController` doesn't match OneTake's visual language or provide casting-specific filters (Recents, Albums, Screenshots).

**What was saved:**

- Full screen anatomy: circular `<` back button, `"Choose Photos"` title, segmented filter pills, 3-column `PHCachingImageManager`-backed grid with `OT.accent` selection checkmarks, floating `Add X Photos` button.
- Technical spec: `Photos` framework, `PHAuthorizationStatus.limited` handling, `NSPhotoLibraryUsageDescription` notes.
- Reference mockup image stored at `docs/illustrations/concepts/custom_photo_picker_spec.jpg`.
- Additional roadmap items: 2-step intake wizard, non-destructive trim revisions, live audio level metronome.
- `CODEBASE_OVERVIEW.md` updated to cross-link the new document.

---

### `1ef1e3d` — Storage & Reset separation
**Files changed:** `ProfileViews.swift`, `AppStore.swift`

**Why:** "Delete Local Data" was wiping the device's entire app state (all auditions, settings, user defaults) which made testing impossible without reinstalling. User needed a safe media-only cleanup option distinct from a full factory reset.

**What was done:**

- Split the single delete button into two clearly-labelled destructive actions:
  - **Clean Local Media Files** — Deletes raw take files and cached exports, freeing disk space. Audition cards, scenes, and metadata are preserved.
  - **Erase Entire App Data & Reset** — Wipes all auditions, settings, user defaults, reader tracks, and practice data, returning the app to a clean install state for testing.
- `AppStore.resetAppForTesting()` marked `@MainActor` to fix isolation compile error.

**Tests:** 173 / 173 passed.

---

### `392b278` — Non-verbal expression cues (`?` beats)
**Files changed:** `Models.swift`, `AddAuditionFlow.swift`, `Components.swift`, `PrepareViews.swift`, `ShootViews.swift`, `NoticeParserTests.swift`

**Why:** Casting sides sometimes include lines like `?` or `(pause)` where a character reacts without speaking. The app was trying to record audio for these lines (triggering a confusing empty-recording path), and the prompter showed them as plain dialogue which breaks the actor's understanding of the beat.

**What was done:**

- `ScriptLine.isSilentReactionCue` expanded to cover `?`, `...`, `…`, `.`, `(pause)`, `(beat)`, `(scoffs)`, `(shrugs)`, `(silence)`, `(reacts)`, `(hesitates)`, `(looks)` — for both actor and reader cue characters.
- `SilentReactionCue` component: glowing `?` badge in `OT.accent`, `[ ? ] Questioning expression` label, `React in character · hold your expression` instruction text.
- In-recording: reader `?` cues no longer trigger audio recording. The record button is replaced with `"Continue to next line"`. `scheduleTimedAdvance()` respects `readerAudioMissing == true` in `followVoice` mode so the prompter doesn't stall.
- In Prepare (rehearsal) prompter: silent cues render as the same `SilentReactionCue` card instead of empty dialogue.
- Test added: `testSilentReactionCueRecognitionForReaderAndActor`.

**Tests:** 173 / 173 passed.

---

### `afd13f4` — Teleprompter auto-scrolling fix
**Files changed:** `ShootViews.swift`, `PracticeViews.swift`, `OnDeviceIntelligence.swift`, `OCRLayoutReconstructor.swift`, `ScriptParser.swift`, `AddAuditionFlow.swift`

**Why:** The in-recording teleprompter was not scrolling past completed lines. The prompter was using view-replacement (swapping the displayed line) rather than keeping all lines in the scroll hierarchy, so `proxy.scrollTo(id, anchor: .top)` had no target to scroll to.

**What was done:**

- `SidesPrompterView` refactored: all lines stay in the `ScrollView` hierarchy at all times with `opacity` and sizing modifiers controlling visibility. `proxy.scrollTo("prompter_line_\(newIndex)", anchor: .top)` now executes smooth spring scrolling without jumpy view replacement.
- Bottom padding added to the scroll content so the final line can scroll fully into view.
- `scheduleTimedAdvance()` now triggers natural reading-delay advance for reader lines with no recorded audio, so the prompter never stalls on unrecorded lines.
- Silent cue lines (reader `?` etc.) also schedule their own timed advance.

**Tests:** 173 / 173 passed.

---

### `a7e3662` — Prompter sizing calibration + in-recording size toggle
**Files changed:** `ShootViews.swift`, `PracticeViews.swift`, `PrepareViews.swift`, `AuditionDetailView.swift`

**Why:** The font size options (Regular / Big / Huge) were not meaningfully differentiated — the "Regular" size was uncomfortably large for a handheld device at normal distance, and "Huge" was not large enough for actors working at a desk distance away from their phone. The 1x/1.5x/2x multiplier button was not applying changes smoothly.

**What was done:**

- Calibrated three tiers: **Regular** (118pt / 18pt line), **Big** (195pt / 26pt line), **Huge** (280pt / 38pt line).
- In-recording interactive size cycling badge `[textformat.size]` with label that updates to show current tier.
- Removed the separate 1x/1.5x/2x multiplier flow that was causing jumpy transitions.

**Tests:** 173 / 173 passed.

---

### `83e55eb` — AI guidance extraction fix (Pilgimage & Shattered Glass notices)
**Files changed:** `AddAuditionFlow.swift`, `NoticeParserTests.swift`

**Why:** Generic "About The Project" boilerplate text (e.g. *"The Shattered Glass Project is holding auditions for their upcoming production…"*) was being extracted as AI guidance shown to the actor as if it were a character note or director instruction. This polluted the guidance section with marketing copy.

**What was done:**

- Added rejection rules for boilerplate opener phrases (`"is holding auditions"`, `"we are looking for"`, `"casting call for"`, `"exciting new"`) — these trigger a skip rather than extraction.
- Prioritized actual director notes, character briefs, and casting requirements that follow a role name.
- Guidance and casting notes dynamically update when the actor changes their selected role.
- Tests added: `testPilgrimageSidesPacket`, updated `testShatteredGlassProjectNotice`.

**Tests:** 172 / 172 passed.

---

### `0a03c02` — Multi-scene sides parsing, audio inspection, light mode colors, text editor stability
**Files changed:** 32 files (see commit for full list)

**Why (multi-issue fix):** A real casting sides document (*Eve's Ale* — Side 1 + Side 2) was parsing as a single merged scene instead of two separate scenes, causing the wrong lines to be presented in each recording slot. Separately, the script text editor was blanking text on async re-renders, reader audio recording was not analysing quality, and several UI elements were invisible in light mode.

**What was done:**

**Script Parser:**
- `"Start"` / `"[START]"` detected as scene/side boundary markers so multi-scene sides with explicit start labels split correctly.
- Running page headers (e.g. `"Eve's Ale - Shanna Allman - p.39"`) stripped via `isWatermarkOrHeader` before parsing.
- Roman numeral act/scene headings (`ACT I`, `SCENE II`) detected with guard against prose false positives.
- Expanded action verb detection: `tosses`, `touches`, `busies`, `gestures`, `starts`.
- `"Slight pause"` / `"Short pause"` added to standalone stage direction list.
- All-caps cue speakers indexed in `speakerCounts` for more accurate action-line detection.

**Audio Inspection (`ReaderLineRecorder`):**
- 10ms acoustic window analysis with dynamic noise floor thresholding.
- Blank audio rejection; quality issue detection: `clipped`, `tooQuiet`, `noisyBackground`, `cutOffAtEnd`.
- Leading/trailing dead air trimmed with 60ms pre / 80ms post padding.

**UI / Light Mode:**
- Actor pill: replaced `OT.prompterGold` and hardcoded white backgrounds with `OT.accent` (Aubergine) / `OT.accentSoft`.
- Reader pill: `OT.reader` (Teal).
- Dialogue text: `OT.labelPrimary`; containers: `OT.surfaceCard`.

**Text Editor:**
- `ScriptTextEditor` (`UIViewRepresentable`) stabilized — text no longer blanks on SwiftUI re-renders during async parse debounce.

**Tab fix:**
- `OneTakeApp.swift` Tab conformance restored to standard inlined layout (search tab was incorrectly using generic `Tab<>` type).

**Tests added:**
- `testEvesAleSidesParseIntoTwoScenes`
- `testAudioInspectionShortSpeechCueAccepted`
- `testAudioInspectionBlankSilenceRejected`
- `testAudioInspectionCatchesClippingAndQuietIssues`
- `testScriptTextEditorPreservesTextAcrossUpdates`

**Tests:** 171 / 171 passed.

---

## Known Gaps & Planned Work

Based on research into real-world casting workflows across Casting Networks, Actors Access, Spotlight, and independent theater companies (see [`docs/research/`](research/)), the following areas are documented for future sessions:

| Area | Current State | Planned |
|------|--------------|---------|
| **Multiple roles per notice** | Candidate roles detected as strings; no discrete entity linking role → sides → instructions | Role records with per-role sides assignment |
| **Multiple milestone dates** | Single `due: Date`. Callback, rehearsal, production dates lost or put in notes | `AuditionMilestones` struct with separate date fields |
| **Source provenance** | `fieldEvidence` array exists in model but UI does not surface it | Show "extracted from page 2 of PDF" alongside each extracted field in review |
| **Discrete intake wizard** | Single paste/upload flow blends notice and sides | 2-step wizard: Step 1 notice metadata, Step 2 sides and material |
| **Non-dialogue auditions** | Parser expects `CHARACTER: Line` cue format; open calls with monologue/song/movement have no dedicated path | Audition type selector: Script Sides / Monologue / Song / Slate Only |
| **Non-destructive trim** | Trim is applied destructively at export | Store `CMTimeRange` offsets in `AuditionTake` metadata until final export |
| **Custom in-app photo picker** | Uses system `PHPickerViewController` | See full spec in [`docs/FUTURE_ENHANCEMENTS.md`](FUTURE_ENHANCEMENTS.md) |

---

## Errors Encountered & Fixed (All Sessions)

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `Call to main actor-isolated 'flushPersistence()' in nonisolated context` | `resetAppForTesting()` not marked `@MainActor` | Added `@MainActor` to the method |
| `Cannot find 'AVFormatIDKey' in scope` | Missing `import AVFoundation` in `ModelTests.swift` | Added import |
| `reference to property 'session' requires explicit 'self'` | Missing `self.` in closure in `CameraController.swift` | Added explicit `self.session` |
| `xcodebuild: unable to attach DB: database is locked` | Concurrent `xcodebuild` processes | Killed background process with `killall xcodebuild` |
| `Tab<AppTab, ...> does not conform to View` | Search tab used generic `Tab<>` type | Restored inline `Tab` layout |
| `testDialogueThatStartsWithSceneIsNotAHeading` failing | Roman numeral regex false positive on prose | Added boundary condition guard |
| `Invalid redeclaration of 'targetRole'` | Duplicate binding name in `AddAuditionFlow.swift` | Renamed inner binding to `guidanceRole` |
| Prompter stalls on reader lines with no audio in `followVoice` mode | `scheduleTimedAdvance()` skipped when `readerAudioMissing == true` | Added explicit timed-advance scheduling for missing-audio reader cues |
| `Type 'OT' has no member 'bgSecondary'` | Used non-existent theme token in `FileNameTemplateSheet` | Replaced with `OT.surfaceSunken` |
