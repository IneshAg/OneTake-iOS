# Implementation notes — 7 November 2026

This note records the implementation work discussed in the current Codex conversation. It describes the code in this checkout, rather than treating every suggestion or Figma reference as shipped behavior. The session changes are still uncommitted.

## Audition intake and first review

### OCR, layout and source handling

- Notice intake continues to accept photos, scans, PDFs, pasted/shared text and shared files. PDF extraction keeps page text and document/page metadata; image-only pages go through Vision OCR.
- OCR output is reconstructed from Vision bounding boxes so rows, key/value layouts, screenplay speaker indentation and sufficiently clear two-column layouts can be retained. When a column boundary is ambiguous, the reconstruction uses row order rather than guessing a column sequence.
- The review sheet can show the original notice image for visual cross-checking. Extracted project, role, character information, casting contact, notes and requested materials remain editable before the audition is saved.
- Notice-only content is guarded from being parsed as screenplay dialogue. The parser requires actual sides/scene markers before creating scenes, which prevents headings such as “WHAT TO SUBMIT” from becoming a role or an accidental required scene.
- Scene selection is offered only when sides exist. Scene requirement can be inferred as optional from notice wording, and required/optional deliverables such as slate and headshots can be reviewed and changed.
- Notice material and script sides have distinct source kinds in the data model. There is an Add/Replace Sides route for bringing script pages in separately. This is not yet a dedicated two-step wizard that makes the user import two PDFs as two explicitly labeled steps; sources shared together can still be classified from their contents.
- The OCR flow detects résumé requests and their optional/required wording. A résumé can be stored once in Profile and included or replaced per audition. Imports accept PDF, DOC, DOCX, RTF and plain text; the imported file is copied into app-owned storage so a temporary Files-picker URL is not retained.

### Review-sheet presentation

- Review labels now distinguish production/project information, role and character details, “What to prepare,” casting notes, and actor notes.
- Long requirement values are presented as readable, wrapping text rather than clipped chips. Casting contact can be added optionally. The notice image remains available to compare the extraction with its source.
- Reader-audio setup is described as practice cue audio: the actor can record the other character’s lines now or add them later. This replaces the ambiguous “Reader: Currently” phrasing in that setup context.
- The edit-details/save action reports the actual parsed actor and reader line counts and selected sides rather than treating the “What to Submit” list as a role. A notice without script pages does not manufacture a “scene required” step.
- Edit Details now builds its role choices from stored role breakdowns, parsed script speakers and saved scene speakers. When there are no detected names, the form says so and keeps manual entry available. The same “no names found” explanation appears during missing-details intake.
- The due-time presets are horizontally scrollable, single-line chips with a consistent 34-point minimum height. The old fixed row compressed “5:00 PM” onto two lines on narrower screens.
- The flow-requirements controls are grouped into one compact Form row instead of several automatically separated Form rows with an extra inner divider. This removes the large blank-looking gap before the Scenes heading.
- Edit Details includes a Flow Order section. Tap **Edit** and drag pieces to reorder them; the order is saved in `Audition.pieces` and drives the next-step flow.

## Practice and reader audio

### Meaningful-word Gaps and Foundation Models

- Added a **Gaps** display choice alongside Full, First Letters and Hide my lines in standalone practice and in the line-learning drill. The in-recording practice prompter can also render the gaps mode.
- Tapping a masked word reveals that word as a temporary clue. Spaces and punctuation remain in the displayed line.
- `RecallGapSelectionStore` asks Apple Foundation Models directly on-device on iOS 26+ to choose a limited number of meaning-bearing word indices. It does not send the line to a server.
- Choices are cached by normalized line text in UserDefaults so the same line does not reshuffle on a later attempt. Foundation Model unavailability or an unusable response falls back to a deterministic local word-ranking rule. That fallback is heuristic; it does not understand dramatic importance.
- Selection runs only after the user chooses Gaps. Other display modes do not trigger Foundation Model work.
- This does **not** add a new Figma “Test Yourself” screen or merge all existing drills into one chooser. The four display modes are available in the existing practice screens; audio gap, audio walk and camera practice remain separate practice actions.

### Recorded voice-practice review

- Added `VoicePracticeReviewAnalyzer` and a review view for a recorded voice-only practice take. It extracts the audio track from the take, requests on-device Apple Speech transcription with word timestamps, and aligns recognized words against the actor’s script lines.
- Per-line suggestions include Looks okay, Skipped, Forgot, Hesitated and Not in Script. A pause of approximately 1.25 seconds between recognized words can suggest Hesitated. Each result retains an approximate recording timestamp when speech was matched.
- Marks are editable/dismissible review suggestions, not an acting score. Speech recognition may miss an accent, paraphrase or intentional pause. If on-device recognition is unavailable or detects too little speech, the app reports that and leaves the recording available for manual review.

### Reader-line audio editing

- Reader audio can be scrubbed and trimmed from the reader-audio management screen, including when opening an existing recording for review.
- A successful trim installs an edited copy while preserving the original. The UI offers **Restore original** with confirmation. Failed edits leave the existing track untouched.
- The trimmer is for the audition’s recorded reader cues. It is not a practice-take editor.

## Headshots, recording and element review

### Shared navigation and glass buttons

- Audited shared button styling in `GlassBackButton`, `GlassIconButton`, `GlassButtonCompatibility`, and the capsule compatibility modifiers, plus their use in audition, practice, prepare, takes/review, profile and onboarding screens.
- Icon-only Back/Close/Add and icon actions use circular glass controls. Capsule actions use capsule glass. Text-only Cancel/Done actions remain plain text controls.
- Fixed the compatibility modifier so a text action with glass disabled no longer falls through to the legacy circular material background. That fallback had drawn a stray circle behind Cancel/Done in edit and sheet headers on iOS 26.
- Kept explicit circular backgrounds on camera-only controls and the profile avatar, where the circle is part of the intended control. Header icons retain 44-point content/hit frames.

### Headshot completion and crop state

- Headshot completion now explicitly says **Saved for this audition** and explains that the images stay on the iPhone and accompany the tape. The saved set is shown with thumbnails and each image’s saved crop ratio.
- Saved angles are counted from actual files rather than assuming that the first N angle slots were filled. The angle slots reflect the specific front/left/right files that exist.
- Crop selection is persisted with the captured image. The camera framing preset control updates the selected preset before applying it to the image set.
- The next step is labeled **Continue to slate** (or a skip-headshots action that says it goes to slate); it no longer silently implies an unspecified destination.
- The default audition order is **Headshots → Slate → Scenes**, with a separate **Full-body shot** inserted only when the notice requests one separately. If the notice asks for a head-to-toe view as part of the slate, it is included in the slate instructions and does not create another clip. Existing legacy “Full length” pieces are relabeled and migrated to the full-body-shot step. Actors can still customize the order with Flow Order.

### Camera and recording controls

- The camera setup/check screen reports camera readiness, requested orientation mismatch, pose guidance and live microphone input when the capture session provides an audio meter.
- Supported resolution choices now come from the full `CameraResolution` case list. On Simulator, the chosen resolution can be changed and retained as a preference, but Simulator has no real camera capture hardware and this does not prove that a recording uses that resolution.
- The recording countdown is a top-bar menu. Storage estimates are not shown in Shoot setup. Camera, framing, zoom and recording controls remain in the camera workflow; this change does not make Simulator video capture functional.

### Separate reviews per audition element

- Tape Check lists available Slate, Full Length and individual scene recordings as separate review entries.
- Opening an entry plays only that element and filters its technical findings to that clip. Its action returns to the relevant slate/full-length camera or scene take-selection/recording path.
- The overall Tape Check and full audition preview remain available. This change does not combine all element reviews into one slate-and-scene review page.
- In the camera, Skip now records which scenes were passed during that camera session. The next-scene search excludes those scenes, so skipping the last scene exits the camera instead of wrapping back to Scene 1. Skipping an optional scene also marks its optional checklist piece complete; skipping a required scene does not falsely mark it recorded.

## Packaging, recovery and account access

- Package format and submission destination are selected in sheets instead of presenting every option as a large inline list. A compact submission check sits near those choices; filename/duration/size/slate details are inside a disclosure section.
- A detected required deliverable can be preselected. If none is detected, the UI exposes “Choose one” in the submission check; the package renderer still has a combined-video fallback internally while the user is choosing, so do not interpret that fallback as notice-derived intent.
- The currently implemented format set still includes Combined Video (.mp4), Separate Clips (.zip), Headshots / Photos and Full Package. The request to remove combined video and reduce final sharing to only private-link and separate-files actions has **not** been implemented in this change set.
- Destination selection is separate from format selection. Local destinations use the iOS share sheet. A hosted link still needs account support; the Apple and Google providers are not configured in this build. The sign-in screen is reachable both from Profile and from the package destination picker, so the actor does not have to leave the audition to find it.
- The export failure view now offers **Back to package options** and **Try again**, restoring a route to edit choices after a failed package attempt.
- The sign-in screen is present, but a sign-in UI alone does not make Apple/Google authentication or hosted sharing available. Do not describe hosted-link sending as verified for this build.

## Camera check, hands-free controls and prompter options

- Replaced the raw AVFoundation input port string (for example, `MicrophoneBuiltIn`) with plain labels: **iPhone microphone**, **Bluetooth microphone**, **Headset microphone**, or **External microphone**.
- Replaced the ambiguous `Reader · 0 of 0 recorded` shortcut with **Reader audio · n of m cues recorded**. The shortcut is hidden when the selected scene has no reader cues, instead of showing a meaningless zero-of-zero count.
- Added independent **Voice: say Action / Cut** and **Gestures: open palm** controls to the pre-scene setup and the camera-check menu. They can be enabled separately or together, and the same voice-control choice is available in Profile alongside the existing gesture preference. Voice command actions are now gated by that preference; speech recognition remains available for voice-following prompter behavior.
- Current gesture behavior in the camera is an open-palm hold: it starts, pauses, or resumes a take; the on-screen Record control ends the take. The pre-shoot screen and camera-check menu explain this. Real gesture and speech accuracy still requires testing on a physical device; the Simulator camera cannot validate it.
- Resolution choices are populated from `AVCaptureSession.canSetSessionPreset` for the active camera. Compatible iPhones can record 4K; front-camera support and available presets vary by model. The Simulator intentionally exposes resolution preferences for UI testing but cannot record actual 4K video.
- Moved **Mirror text** under **Advanced teleprompter options** and clarified that it is only for a beam-splitter teleprompter attachment. It remains off by default for ordinary phone recording.

## Compiler correction and verification record

- Résumé importers now construct DOC/DOCX `UTType`s from their filename extensions instead of referencing the unavailable `UTType.word` symbol. This is applied in both Profile and per-audition résumé import.
- Removed two unused locals from `ScriptParser` and marked the pure reader-audio original-file URL helper `nonisolated`, so the audio export callback can compute that URL under Swift 6 concurrency checking.
- All app and test Swift sources passed `swiftc -frontend -parse` after these follow-up changes, including the camera-check/profile controls and status-label cleanup; `git diff --check` passed. A small Foundation Models API probe type-checked against the installed Simulator SDK.
- A complete Xcode build was not verified in this environment. `xcodebuild -list` failed while resolving package dependencies with `sandbox_apply: Operation not permitted`, and CoreSimulator service was unavailable. The parser checks do not substitute for a full build or on-device validation.
- The current documentation update does not claim that OCR accuracy, the speech-review classifications, real camera resolutions or hosted link delivery were validated end-to-end on a physical iPhone.

## Relevant implementation files

| Area | Main files |
|---|---|
| Notice OCR and intake review | `OneTake/ModelViews/NoticeOCR.swift`, `OneTake/ModelViews/OCRLayoutReconstructor.swift`, `OneTake/Views/AddAuditionFlow.swift`, `OneTake/Models/ScriptParser.swift` |
| Résumé persistence/import | `OneTake/Models/Persistence.swift`, `OneTake/Models/Models.swift`, `OneTake/Views/ProfileViews.swift`, `OneTake/Views/AddAuditionFlow.swift` |
| Foundation Models and Gaps | `OneTake/ModelViews/OnDeviceIntelligence.swift`, `OneTake/Models/Models.swift`, `OneTake/Views/Components.swift`, `OneTake/Views/LineLearningViews.swift`, `OneTake/Views/PracticeViews.swift`, `OneTake/Views/ShootViews.swift` |
| Voice practice review | `OneTake/ModelViews/VoicePracticeReview.swift`, `OneTake/Views/PracticeViews.swift` |
| Reader audio trim/restore | `OneTake/Views/PrepareViews.swift`, `OneTake/ModelViews/UIKitBridges.swift` |
| Headshots and element review | `OneTake/Views/ProfileViews.swift`, `OneTake/Views/TakesViews.swift`, `OneTake/ModelViews/AppStore.swift` |
| Package, destination and recovery | `OneTake/Views/PackageViews.swift`, `OneTake/Views/OnboardingFlow.swift`, `OneTake/ModelViews/CloudLink.swift` |
