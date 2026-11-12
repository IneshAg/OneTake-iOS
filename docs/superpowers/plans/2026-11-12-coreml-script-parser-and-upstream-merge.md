# Core ML Script Parser & Upstream Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fragile regex script parsing in `ScriptParser.swift` with an on-device `ScriptElementClassifier` Core ML model, while cleanly integrating the upstream enhancements and bug fixes from commit `c3a1da4` into our modular, `OneTakeUI`-compliant architecture.

**Architecture:** A native Core ML multiclass text classifier (`ScriptElementClassifier.mlmodel`) categorizes script lines into headings, cues, dialogue, parentheticals, and actions on the Apple Neural Engine (<5ms latency, <3MB footprint). Upstream fixes (atomic media persistence rollback, multi-pass OCR enlargement, sides revision tracking, and multi-reader cue stability) are extracted and adapted into `Core/Models/`, `Core/Services/`, `Core/Store/`, and `Features/` while maintaining strict design system compliance (0 lint violations, all files < 800 lines).

**Tech Stack:** Swift 5.10 / 6, Core ML, Vision, CreateML / NaturalLanguage, SwiftUI, OneTakeUI, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-12-coreml-script-parser-design.md`

## Global Constraints

- iOS 18.0 deployment target, Apple Silicon & Apple Neural Engine (ANE) compatible.
- Strict 800-line ceiling on all files in `OneTake/` and `Packages/OneTakeUI/`.
- Strict design lint: `./scripts/lint-design-system.sh --strict` must exit 0 with 0 violations at every task.
- Zero network dependencies for model inference: 100% on-device and offline.
- Run `xcodebuild`, `xcodegen`, and git operations with `BypassSandbox: true`.

## Review Focus

1. **Model Cold-Start & Availability:** If the Core ML model is missing or fails compilation on older toolchains, `ScriptParser` must gracefully fall back to deterministic parsing without crashing or dropping dialogue.
2. **Atomic Media Replacement:** `MediaStore.persist` must never leave the disk without either the old recording or the new recording, even if a filesystem write fails or is cancelled mid-move.
3. **Multi-Reader Cue Collision:** When multiple reader characters alternate lines in the same scene, cue indices must remain stable across recording, scrubbing, trimming, and playback.
4. **Sides Revision Take Preservation:** Re-importing revised sides must reset package readiness but keep earlier takes accessible under `.previousSides`.
5. **OCR Blank Page Alignment:** `NoticeOCR.recognizePages` must retain empty slots for blank pages so that 1-indexed document page numbers never drift out of sync.

---

### Task 1: Core Models & Media Persistence Rollback

**Files:**
- Modify: `OneTake/Core/Models/Models.swift`
- Modify: `OneTake/Core/Persistence/Persistence.swift`
- Test: `OneTakeTests/PersistenceTests.swift`
- Test: `OneTakeTests/CameraAndImageTests.swift`

- [ ] **Step 1: Write failing persistence and headshot completion tests**
  Add `testMediaStorePersistRetakePreservesPreviousRecordingOnFailure` to `OneTakeTests/PersistenceTests.swift`.
  Add `testHeadshotChecklistRequiresAllAngles` to `OneTakeTests/CameraAndImageTests.swift`.

- [ ] **Step 2: Run test suite to verify tests fail**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "platform=iOS Simulator,name=iPhone 18 Pro" -only-testing:OneTakeTests/PersistenceTests -only-testing:OneTakeTests/CameraAndImageTests CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Update `Models.swift`**
  Add `.exported` case to `AuditionStatus`.
  Add `isArchived`, `sidesRevision`, `requiredProgressSummary`, and `nextRequiredPiece` to `Audition`.
  Add `isPreviousSides`, `previousSides`, `previousSidesLabel`, `sidesRevision`, and `currentSidesRevision` to `Take`.

- [ ] **Step 4: Update `Persistence.swift`**
  Implement safe atomic move with rollback backup in `MediaStore.persist(_:as:in:)`.
  Add `requirementDescription` and `isComplete(auditionID:)` to `HeadshotStore`.

- [ ] **Step 5: Run tests and verify they pass**
  Run `xcodebuild test` for `PersistenceTests` and `CameraAndImageTests`.

- [ ] **Step 6: Verify lint and commit**
  Run `./scripts/lint-design-system.sh --strict`.
  Commit: `feat(core): atomic media persistence rollback and audition sides revision models`

---

### Task 2: Core Services (NoticeOCR, CameraController, MediaExporter, TapeAnalyzer)

**Files:**
- Modify: `OneTake/Core/Services/NoticeOCR.swift`
- Modify: `OneTake/Core/Services/CameraController.swift`
- Modify: `OneTake/Core/Services/MediaExporter.swift`
- Modify: `OneTake/Core/Services/TapeAnalyzer.swift`
- Test: `OneTakeTests/NoticeParserTests.swift`

- [ ] **Step 1: Write failing OCR and deadline tests**
  Add `testFlyersOCRAndDeterministicParsing` and `testVideoSubmissionsDeadlinePreservesTimeAndExplicitTimeZone` to `OneTakeTests/NoticeParserTests.swift`.

- [ ] **Step 2: Run tests to verify failure**
  Run `xcodebuild test` on `NoticeParserTests`.

- [ ] **Step 3: Update `NoticeOCR.swift`**
  Add `configureSupportedLanguages` for dynamic runtime language querying.
  Preserve empty entries in `recognizePages` to maintain 1-to-1 page alignment.
  Add `isWeakOCR`, `ocrScore`, `scaledCGImage` (2x Core Graphics enlargement pass), and luminance inversion retry.

- [ ] **Step 4: Update `CameraController.swift`**
  Add `InterruptionEvent` struct and `lastInterruption` property.
  Observe `AVCaptureSession.wasInterruptedNotification` and handle background/audio interruptions.
  Preserve partial takes in `recordingFinishedHandler` if bytes exist.

- [ ] **Step 5: Update `MediaExporter.swift` & `TapeAnalyzer.swift`**
  Filter out `previousSides` takes in `MediaExporter.assembleClips`.
  Update `TapeAnalyzer` to check `HeadshotStore.isComplete(auditionID:)`.

- [ ] **Step 6: Run tests and verify they pass**
  Run `xcodebuild test` on `NoticeParserTests` and `CameraAndImageTests`.

- [ ] **Step 7: Verify lint and commit**
  Run `./scripts/lint-design-system.sh --strict`.
  Commit: `feat(services): multi-pass OCR enlargement, camera interruption recovery, and clip filtering`

---

### Task 3: AppStore & Revised Sides Migration

**Files:**
- Modify: `OneTake/Core/Store/AppStore.swift`
- Modify: `OneTake/Core/Store/AppStore+Auditions.swift`
- Modify: `OneTake/Core/Store/AppStore+Headshots.swift`
- Test: `OneTakeTests/PersistenceTests.swift`

- [ ] **Step 1: Write failing revised sides migration and multi-reader cue tests**
  Add `testRevisedSidesReorderingAndReaderAudioMigration`, `testMultipleReaderCharactersInSameSceneHaveStableCueIDs`, and `testRevisedSidesResetSceneCompletionAndChecklistReadiness` to `OneTakeTests/PersistenceTests.swift`.

- [ ] **Step 2: Run tests to verify failure**
  Run `xcodebuild test` on `PersistenceTests`.

- [ ] **Step 3: Implement Store enhancements**
  Add `loadSampleAudition()`, `active`, `sent`, `archived` filters to `AppStore.swift`.
  Implement `compareSides(of:with:)` and `SidesChangeSummary` in `AppStore+Auditions.swift`.
  Implement `replaceSides(of:with:sourceText:)` in `AppStore+Auditions.swift`, marking existing takes as `previousSides = true`, incrementing `sidesRevision`, migrating staged reader audio files, and resetting checklist status.
  Add `archiveAudition(_:)`, `unarchiveAudition(_:)`, `markExported(_:)`, `markSubmitted(_:)`.

- [ ] **Step 4: Run tests and verify they pass**
  Run `xcodebuild test` on `PersistenceTests`.

- [ ] **Step 5: Verify lint and commit**
  Run `./scripts/lint-design-system.sh --strict`.
  Commit: `feat(store): revised sides migration, reader audio staging, and audition archive filters`

---

### Task 4: Core ML Script Element Classifier Model Training & Packaging

**Files:**
- Create: `scripts/train_script_element_classifier.swift`
- Create: `OneTake/Core/Models/ScriptElementClassifier.mlmodel`
- Create: `OneTake/Core/Models/CoreMLScriptParserRunner.swift`
- Modify: `project.yml`
- Test: `OneTakeTests/ScriptParserTests.swift`

- [ ] **Step 1: Create training generator script**
  Create `scripts/train_script_element_classifier.swift` using Apple's `CreateML` framework (`MLTextClassifier`).
  Train on labeled screenplay dataset covering `scene_heading`, `character_cue`, `dialogue`, `parenthetical`, `action`, and `metadata`.
  Export compiled model to `OneTake/Core/Models/ScriptElementClassifier.mlmodel`.

- [ ] **Step 2: Run training script and generate model**
  Execute `swift scripts/train_script_element_classifier.swift` (`BypassSandbox: true`) to generate the model artifact.

- [ ] **Step 3: Create `CoreMLScriptParserRunner.swift`**
  Implement actor `CoreMLScriptParserRunner` that loads `ScriptElementClassifier` and exposes `classify(line:) -> ElementClass?` and `isAvailable`.

- [ ] **Step 4: Register in `project.yml` and regenerate Xcode project**
  Add `OneTake/Core/Models/ScriptElementClassifier.mlmodel` to `project.yml` sources.
  Run `xcodegen generate` (`BypassSandbox: true`).

- [ ] **Step 5: Write unit tests for classifier**
  Add `testCoreMLScriptElementClassifierAccuracy` in `OneTakeTests/ScriptParserTests.swift`.
  Verify accuracy on sluglines, cues, dialogue, parentheticals, and action lines.

- [ ] **Step 6: Run tests and commit**
  Run `xcodebuild test` on `ScriptParserTests`.
  Commit: `feat(ml): train and bundle ScriptElementClassifier Core ML model`

---

### Task 5: Integrate Core ML Classifier into `ScriptParser.swift`

**Files:**
- Modify: `OneTake/Core/Models/ScriptParser.swift`
- Test: `OneTakeTests/ScriptParserTests.swift`

- [ ] **Step 1: Write failing indented cue and Core ML end-to-end tests**
  Add `testIndentedCharacterCuesWithTabsAndSpaces` and `testCoreMLScriptParserParsesScenes` to `OneTakeTests/ScriptParserTests.swift`.

- [ ] **Step 2: Run tests to verify current behavior**
  Run `xcodebuild test` on `ScriptParserTests`.

- [ ] **Step 3: Refactor `ScriptParser.parseScenes`**
  Integrate `CoreMLScriptParserRunner`:
  - Each line is evaluated by the Core ML model for its semantic role (`scene_heading`, `character_cue`, `dialogue`, `parenthetical`, `action`, `metadata`).
  - `scene_heading` opens a new `ScriptScene`.
  - `character_cue` switches active speaker and flushes dialogue.
  - `dialogue` formats and appends spoken line.
  - `action` / `parenthetical` flushes dialogue without attaching stage directions to dialogue.
  - Retain deterministic guardrail fallback for maximum safety.
  - Add `normalizeDialogue(_:)` utility.

- [ ] **Step 4: Run all 22+ tests in `ScriptParserTests`**
  Verify all existing and new tests pass with 0 failures.

- [ ] **Step 5: Verify lint and commit**
  Run `./scripts/lint-design-system.sh --strict`.
  Commit: `feat(parser): replace regex script extraction with Core ML element classifier`

---

### Task 6: Feature Views & Design System Verification

**Files:**
- Modify: `OneTake/Features/Auditions/AuditionsView.swift`
- Modify: `OneTake/Features/AuditionDetail/AuditionDetailView.swift`
- Modify: `OneTake/Features/AddAudition/NoticeReviewView.swift`
- Modify: `OneTake/Core/Services/VoicePracticeReview.swift`
- Test: Full Test Suite (`ModelTests`, `DesignSystemTests`, `ScriptParserTests`, `PersistenceTests`, `NoticeParserTests`, `CameraAndImageTests`)

- [ ] **Step 1: Update `AuditionsView.swift`**
  Add tab picker for `[Active] [Submitted] [Archived]` using `OneTakeUI` styles.
  Filter list rows based on selected segment.
  Add swipe action for Archive / Unarchive.

- [ ] **Step 2: Update `AuditionDetailView.swift`**
  Show sides revision indicator and Previous Takes section if `audition.currentSidesRevision > 0`.
  Add "Mark as Submitted" button when status is `.exported` or `.ready`.

- [ ] **Step 3: Update `NoticeReviewView.swift`**
  Safeguard ambiguous candidate roles: if multiple roles detected, keep role unselected with explicit guidance banner (`testMultipleDetectedRolesLeaveRoleBlankInDraftAndUnselectedInReview`).

- [ ] **Step 4: Update `VoicePracticeReview.swift`**
  Add matched count header and "Listen" audio pill styling.

- [ ] **Step 5: Verify 800-line ceiling and zero lint violations**
  Run `./scripts/lint-design-system.sh --strict` across entire repository.
  Confirm all modified files are strictly < 800 lines.

- [ ] **Step 6: Run full unit test suite**
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination "platform=iOS Simulator,name=iPhone 18 Pro" CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 7: Final commit**
  Commit: `feat(ui): auditions filter tabs, sides revision history, and role review safeguards`
