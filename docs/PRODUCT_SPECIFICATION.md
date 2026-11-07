# OneTake iOS — Product Specification

This document details the functional specifications for every subsystem, screen, and user-facing capability in OneTake iOS.

---

## 1. Feature Specifications

### 1.1 First-Run Experience & Onboarding
- **Purpose**: Introduce the core workflow and set up default profile information (actor name, default headshot, default slate details).
- **Expected Behavior**: First launch displays an onboarding wizard capturing the actor's legal and stage name, agent/manager contact, and an optional profile headshot. Skips immediately on subsequent launches via `isOnboarded: Bool`.
- **Inputs**: Actor name, profile headshots, contact information.
- **Outputs**: Initialized `PersistedState` with `account` and `slate` defaults.
- **Dependencies**: `OneTakeApp.swift`, `AppStore.swift`, `ProfileViews.swift`.
- **Edge Cases**: Terminating the app during onboarding saves partial profile state safely via `flushPersistence()`.
- **Status**: **Implemented and verified**.

---

### 1.2 Main Navigation & Tab Structure
- **Purpose**: Provide frictionless switching between active audition shoots and standalone practice drills.
- **Expected Behavior**: Two primary tabs:
  1. `Auditions`: List of auditions filtered by Active, Due this week, Sent, and All.
  2. `Practice`: Standalone line-running drills and practice pieces disconnected from any specific audition deliverable.
  Modal sheets cover Add Audition and Profile.
- **Inputs**: User tab selection, deep links (`onetake://tab/auditions`, `onetake://tab/practice`, `onetake://add`).
- **Outputs**: Navigation state updates in `AppStore.tab`.
- **Dependencies**: `OneTakeApp.swift`, `AuditionsView.swift`, `PracticeViews.swift`.
- **Status**: **Implemented and verified**.

---

### 1.3 Add Audition & Independent Document Import (`WORKFLOW-PDF-01`)
- **Purpose**: Allow actors to import casting notices and script sides from PDFs, camera scans, images, or pasted text.
- **Expected Behavior**:
  - **Casting Call PDF**: Extracts audition metadata (project title, role name, casting director, due date, slate requirements, submission instructions).
  - **Script Sides PDF**: Parses scenes, sluglines (`INT.`/`EXT.`), character cues, and dialogue lines into independent scene entities.
  - **Independent Replacement**: Re-importing or updating a Casting Call PDF replaces only metadata and preserves script sides. Re-importing revised Script Sides updates scene dialogue and preserves notice metadata.
- **Inputs**: PDF files (via `UIDocumentPickerViewController` or Share Extension), clipboard text, VisionKit document camera scans.
- **Outputs**: `NoticeParser.Draft` with independent `castingCallDocument` and `scriptSidesDocument`.
- **Dependencies**: `NoticeParser.swift`, `ScriptParser.swift`, `AddAuditionFlow.swift`.
- **Edge Cases**: Password-protected PDFs throw readable errors; mixed packets containing both call and sides can be assigned independently.
- **Status**: **Implemented and verified** (Remediated in Phase 1 commit `6527bb2`).

---

### 1.4 Project Overview & Audition Checklist
- **Purpose**: Centralized dashboard for an active audition showing required deliverables and completion progress.
- **Expected Behavior**: Displays a sequential checklist:
  1. Headshot (audition-specific or profile default).
  2. Slate video (name, agency, height, location, role).
  3. Full Length video (only displayed if requested by casting notice).
  4. Scene 1 .. N takes.
  A prominent "Next" action automatically routes to whichever step remains uncompleted.
- **Inputs**: Selected `Audition.ID`.
- **Outputs**: Visual progress indicator and navigation triggers.
- **Dependencies**: `AuditionsView.swift`, `AuditionDetailView.swift`.
- **Status**: **Implemented and verified**.

---

### 1.5 Headshots
- **Purpose**: Capture and select front, left profile, and right profile headshots formatted to industry 8×10 aspect ratio.
- **Expected Behavior**: Uses camera overlay guides for eye-line and chin placement. Allows cropping and panning with persistent normalization coordinates (`cropOffset`, `cropScale`).
- **Inputs**: Camera capture or Photo Library image.
- **Outputs**: JPEG files stored in `Documents/audition-<id>/headshot-<type>.jpg`.
- **Dependencies**: `HeadshotStore.swift`, `CameraViews.swift`.
- **Edge Cases**: Custom audition headshots take precedence over profile defaults; deleting audition cleans up audition headshots without touching profile defaults.
- **Status**: **Implemented and verified**.

---

### 1.6 Slate & Full Length Recording
- **Purpose**: Record slate details and full-body wardrobe/physique shots.
- **Expected Behavior**:
  - **Slate**: Films actor stating required info. Offers an automated speech-silence trim suggestion that can be reviewed and applied or reverted.
  - **Full Length**: Displayed and required **only** when casting explicitly asks for a full-body view. If requested as part of the slate, it remains merged; otherwise, it records as a distinct piece.
- **Inputs**: Video stream from `CameraController`.
- **Outputs**: QuickTime `.mov` files recorded to `Documents/audition-<id>/slate.mov`.
- **Dependencies**: `CameraController.swift`, `ShootViews.swift`.
- **Status**: **Implemented and verified**.

---

### 1.7 Scene Preparation & Reader Recording
- **Purpose**: Enable actors to record reader dialogue cues and rehearse scenes before filming.
- **Expected Behavior**:
  - Actors tap a line to record audio for that specific character cue.
  - Audio files are stored under `Documents/ReaderTracks/<audition_id>/<scene_id>/<line_index>.m4a`.
  - Rehearsal mode ("Run Lines") uses on-device speech recognition to advance the teleprompter when the actor speaks, playing the reader track when it is the scene partner's turn.
- **Inputs**: Microphone audio stream, speech recognition input.
- **Outputs**: Recorded audio cues, teleprompter timing markers.
- **Dependencies**: `ReaderTrackPlayer.swift`, `ScriptParser.swift`, `PrepareViews.swift`.
- **Status**: **Implemented and verified**.

---

### 1.8 Camera Recording & Monotonic Clock
- **Purpose**: Film high-definition 1080p audition takes without timer drift or unhandled capture interruptions.
- **Expected Behavior**:
  - Records at 1080p, upright orientation, never mirrored.
  - Recording duration is tracked via monotonic hardware clock `CACurrentMediaTime()`.
  - Take finalization queries true `AVURLAsset` duration on disk rather than trusting UI timer counters.
  - Capture session and audio interruptions (phone calls, alarms) are observed and handled cleanly by committing the partial take to disk.
  - Hold-to-stop gesture prevents accidental touch cancellation.
- **Inputs**: Camera sensors, microphone, orientation sensor.
- **Outputs**: Finalized `Take` entity referencing QuickTime movie file.
- **Dependencies**: `CameraController.swift`, `ShootViews.swift`.
- **Status**: **Implemented and verified** (Remediated in Phase 4 commit `76d0473`).

---

### 1.9 Take Review & Tape Check
- **Purpose**: Review filmed takes and conduct objective technical checks before delivery.
- **Expected Behavior**:
  - Actor circles their preferred "Send Take" per scene.
  - Trimming tool adjusts in/out points non-destructively.
  - **Tape Check**: Analyzes circled takes using Vision and AVFoundation:
    - Headroom and face framing centring.
    - Lighting contrast and underexposure.
    - Audio clipping and low volume.
    - Long initial/terminal pauses.
  - Tape Check never judges dramatic acting; findings are purely technical advisories.
- **Inputs**: Selected `Take.fileURL`.
- **Outputs**: Tape check diagnostic scores and suggestions.
- **Dependencies**: `TapeCheck.swift`, `ShootViews.swift`, `ReviewViews.swift`.
- **Status**: **Implemented and verified**.

---

### 1.10 Packaging & Delivery Options
- **Purpose**: Bundle audition deliverables according to casting instructions.
- **Expected Behavior**:
  - Generates deliverable filename using template: `{LAST}_{FIRST}_{ROLE}_{PROJECT}.mp4`.
  - User is presented with exactly **two** export choices:
    1. **Share Link**: Uploads archive to the user's iCloud Drive ubiquity container and generates an authenticated download link.
    2. **Separate Elements**: Compiles a `.zip` archive containing individual clip files (`SLATE.mp4`, `SCENE_1.mp4`, `HEADSHOT.jpg`) using streaming system `zlib` CRC32.
  - Combined direct export was deprecated in favor of clean separate deliverables and share links.
- **Inputs**: Selected takes, headshots, slate metadata.
- **Outputs**: Deliverable `.mp4`, compressed `.zip` archive, or iCloud download link.
- **Dependencies**: `PackageAndSentViews.swift`, `ZipArchive.swift`, `CloudLink.swift`.
- **Status**: **Implemented and verified** (Remediated in Phase 5 commit `dd51677` and Phase 6 commit `87ac708`).

---

### 1.11 Share Link Revocation & Lifecycle
- **Purpose**: Revoke public iCloud download links when an audition is deleted or cleared.
- **Expected Behavior**:
  - `Audition` persists `shareUbiquityFolderURL: URL?`.
  - Revoking deletes the ubiquitous folder from iCloud Drive, revoking public access.
  - If called on a legacy record lacking `shareUbiquityFolderURL`, it returns `.unmappedLegacyLink` safely without performing dangerous speculative directory scans.
- **Inputs**: `Audition.shareLink`, `Audition.shareUbiquityFolderURL`.
- **Outputs**: `RevocationOutcome` (`.revoked`, `.alreadyRevoked`, `.unmappedLegacyLink`, `.failed`).
- **Dependencies**: `CloudLink.swift`, `AppStore.swift`.
- **Status**: **Implemented and verified** (Remediated in Phase 6 commit `87ac708` and Phase 8 commit `d391d89`).

---

### 1.12 Persistence & Local Backup
- **Purpose**: Ensure persistent application state is crash-safe, race-safe, and portable.
- **Expected Behavior**:
  - Off-MainActor JSON serialization via `StateStorage` actor enforcing monotonic sequence ordering.
  - UIKit background task execution assertions (`BackgroundTaskToken`, `FlushOperation`) preventing background suspension during writes.
  - Local backup creates a versioned ZIP archive of `state.json` and `Documents/`.
  - Restore preserves the root `Documents` inode, logs pre-flight snapshots (`OriginalEntrySnapshot`) with CRC32 integrity validation, and safely rolls back interrupted operations on app launch.
- **Inputs**: `PersistedState`, backup ZIP archives.
- **Outputs**: `state.json`, restore journals, backup archives.
- **Dependencies**: `Persistence.swift`, `LocalBackup.swift`, `BackgroundTaskCoordinator.swift`.
- **Status**: **Implemented and verified** (Remediated in Phases 2, 3, 8, 8.1, and 8.2).
