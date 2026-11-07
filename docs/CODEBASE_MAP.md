# OneTake iOS — Codebase Map & Navigation Guide

This document maps all directories, source files, and primary symbols across the repository, providing a fast lookup guide for common engineering tasks.

---

## 1. Directory Structure

```text
OneTake-iOS/
├── OneTake/                       # Main iOS Application Target
│   ├── Models/                    # Data models, persistence, backup, script parsing
│   ├── Views/                     # SwiftUI views, navigation screens, asset catalog
│   ├── ModelViews/                # AppStore coordinator, camera controller, export services
│   ├── Info.plist                 # Target configuration properties
│   └── OneTake.entitlements       # App Group & iCloud capabilities
├── OneTakeWidgets/                # WidgetKit Extension (Home/Lock Screen widgets, Live Activity)
├── OneTakeShare/                  # Action / Share Extension (Imports from Mail, Files, Safari)
├── Shared/                        # Code shared between app and extensions (AppGroup, ShareInbox)
├── OneTakeTests/                  # Native Swift XCTest test suites
├── scripts/                       # Python regression and independent verification test suites
├── dataset/                       # Sample audition notices and script PDFs for testing
├── docs/                          # Comprehensive technical and product documentation
└── project.yml                    # XcodeGen declarative project specification
```

---

## 2. File & Symbol Inventory

### 2.1 Core Models & Persistence (`OneTake/Models/`)

| File | Primary Symbols | Responsibility |
| :--- | :--- | :--- |
| [`Models.swift`](../OneTake/Models/Models.swift) | `Audition`, `Piece`, `Take`, `SlateConfig`, `AccountProfile`, `PieceKind` | Fundamental domain models and Codable structures. |
| [`Persistence.swift`](../OneTake/Models/Persistence.swift) | `Persistence`, `PersistedState`, `StateStorage`, `HeadshotStore`, `PersistenceError` | Off-MainActor state serialization to `state.json` with monotonic sequence ordering, and headshot disk management. |
| [`LocalBackup.swift`](../OneTake/Models/LocalBackup.swift) | `LocalBackup`, `RestoreJournal`, `OriginalEntrySnapshot`, `LocalBackupPayload` | Full ZIP backup creation, inode-safe restoration, durable journaling outside tmp, and CRC32 verification. |
| [`ScriptParser.swift`](../OneTake/Models/ScriptParser.swift) | `ScriptParser`, `ScriptScene`, `DialogueCue`, `ParsedCharacter` | Scene splitting at sluglines (`INT.`/`EXT.`), character extraction, and dialogue cue mapping. |
| [`BPETokenizer.swift`](../OneTake/Models/BPETokenizer.swift) | `BPETokenizer` | Pure-Swift BPE tokenizer for on-device Core ML parsing runners. |
| [`CoreMLParserRunner.swift`](../OneTake/Models/CoreMLParserRunner.swift) | `CoreMLParserRunner` | Grammar-constrained Core ML inference runner for parsing breakdowns. |

### 2.2 Application Coordination & Services (`OneTake/ModelViews/`)

| File | Primary Symbols | Responsibility |
| :--- | :--- | :--- |
| [`AppStore.swift`](../OneTake/ModelViews/AppStore.swift) | `AppStore`, `AuditionRoute`, `PracticeRoute`, `AppTab` | Central `@MainActor` state manager, navigation controller, and background flush coordinator. |
| [`BackgroundTaskCoordinator.swift`](../OneTake/ModelViews/BackgroundTaskCoordinator.swift) | `BackgroundTaskManaging`, `BackgroundTaskToken`, `FlushOperation`, `UIKitBackgroundTaskManager` | Thread-safe UIKit background task assertions and synchronized flush lifecycle state machine. |
| [`CameraController.swift`](../OneTake/ModelViews/CameraController.swift) | `CameraController`, `RecordingState`, `CameraPosition` | AVFoundation video capture, monotonic hardware timing, interruption handling, and zoom controls. |
| [`NoticeOCR.swift`](../OneTake/ModelViews/NoticeOCR.swift) | `NoticeParser`, `Draft`, `NoticeDetails`, `RolePrompt` | Vision OCR extraction, casting notice parsing, and dual-document draft storage. |
| [`ZipArchive.swift`](../OneTake/ModelViews/ZipArchive.swift) | `ZipArchive`, `ArchiveError`, `ZipEntry` | Zero-dependency ZIP file reader/writer with streaming system `zlib` CRC32 checksum computation. |
| [`CloudLink.swift`](../OneTake/ModelViews/CloudLink.swift) | `CloudLink`, `Published`, `RevocationOutcome`, `CloudError` | iCloud Drive ubiquity container upload, public link publishing, and safe folder revocation. |
| [`TapeAnalyzer.swift`](../OneTake/ModelViews/TapeAnalyzer.swift) | `TapeCheck`, `CheckResult`, `TapeCheckReport` | Vision & AVFoundation technical analysis (headroom, lighting, centring, audio clipping). |
| [`Reminders.swift`](../OneTake/ModelViews/Reminders.swift) | `Reminders` | Local notification scheduling for audition submission deadlines. |
| [`WidgetSync.swift`](../OneTake/ModelViews/WidgetSync.swift) | `WidgetSync`, `LiveActivitySync` | Writes snapshot data to App Group container for WidgetKit and Live Activities. |
| [`UIKitBridges.swift`](../OneTake/ModelViews/UIKitBridges.swift) | `ReaderTrackPlayer`, `DocumentPickerViewController` | Per-line recorded reader audio playback and UIKit view controller bridges. |
| [`MediaExporter.swift`](../OneTake/ModelViews/MediaExporter.swift) | `MediaExporter` | Video composition rendering and deliverable export. |
| [`SilenceTrimmer.swift`](../OneTake/ModelViews/SilenceTrimmer.swift) | `SilenceTrimmer` | Automated audio silence edge detection for slate trims. |
| [`AudioCleanup.swift`](../OneTake/ModelViews/AudioCleanup.swift) | `AudioCleanup` | On-device speech isolation and audio normalization. |
| [`ImageFraming.swift`](../OneTake/ModelViews/ImageFraming.swift) | `ImageFraming` | Vision-based face detection and framing guide alignment. |

### 2.3 User Interface (`OneTake/Views/`)

| File | Primary Symbols | Responsibility |
| :--- | :--- | :--- |
| [`OneTakeApp.swift`](../OneTake/Views/OneTakeApp.swift) | `OneTakeApp`, `scenePhase` | Application entry point, deep link routing, and scene phase persistence flushes. |
| [`AuditionsView.swift`](../OneTake/Views/AuditionsView.swift) | `AuditionsView`, `AuditionCard` | Main auditions list, status filters (Active, Due, Sent, All), context menu actions. |
| [`AuditionDetailView.swift`](../OneTake/Views/AuditionDetailView.swift) | `AuditionDetailView`, `ChecklistRow` | Project overview, deliverable checklist, "Next" action routing. |
| [`AddAuditionFlow.swift`](../OneTake/Views/AddAuditionFlow.swift) | `AddAuditionFlow`, `AddAuditionDraft` | Multi-step import wizard for notices and script sides with parsed scene caching. |
| [`ShootViews.swift`](../OneTake/Views/ShootViews.swift) | `ShootView`, `RecordButton`, `PrompterOverlay` | Live camera recording screen, hold-to-stop button, prompter overlay, countdown timer. |
| [`TakesViews.swift`](../OneTake/Views/TakesViews.swift) | `TakesSheet`, `TakeCard`, `TrimSheet` | Take playback, circle take selection, and non-destructive trim editor. |
| [`PackageViews.swift`](../OneTake/Views/PackageViews.swift) | `PackageView`, `SentView`, `ShareOptionsView` | Deliverable packaging, Share Link vs Separate Elements export, sent confirmation. |
| [`PrepareViews.swift`](../OneTake/Views/PrepareViews.swift) | `PrepareView`, `ReaderRecorderView` | Scene preparation and line-by-line reader track recording. |
| [`LineLearningViews.swift`](../OneTake/Views/LineLearningViews.swift) | `LineLearningView`, `RunLinesView` | Line rehearsal drills (Mask & Reveal, First Letter, Audio Gap). |
| [`PracticeViews.swift`](../OneTake/Views/PracticeViews.swift) | `PracticeViews` | Standalone practice navigation and drills. |
| [`TapePreviewView.swift`](../OneTake/Views/TapePreviewView.swift) | `TapePreviewView` | Complete self-tape timeline preview with chapter markers. |
| [`ProfileViews.swift`](../OneTake/Views/ProfileViews.swift) | `ProfileView`, `LocalBackupView` | Actor profile settings, default headshots, local backup creation and restore. |
| [`Components.swift`](../OneTake/Views/Components.swift) | `GlassButton`, `CardContainer` | Reusable design system UI components and styling modifiers. |
| [`Theme.swift`](../OneTake/Views/Theme.swift) | `Colors`, `Typography`, `Dimensions` | Design system color tokens, typography scales, and HIG layout metrics. |

### 2.4 Shared Module (`Shared/`)

| File | Primary Symbols | Responsibility |
| :--- | :--- | :--- |
| [`WidgetSnapshot.swift`](../Shared/WidgetSnapshot.swift) | `AppGroup`, `WidgetSnapshot` | Centralized App Group identifier (`group.com.srmist.onetake`) and shared snapshot model. |
| [`ShareInbox.swift`](../Shared/ShareInbox.swift) | `ShareInbox`, `IncomingShare` | Shared file exchange allowing Share Extension to pass imported PDFs into the main app. |
| [`AuditionActivity.swift`](../Shared/AuditionActivity.swift) | `AuditionActivityAttributes` | ActivityKit attributes for Dynamic Island and Lock Screen countdowns. |

---

## 3. Practical "Where to Make Changes" Guide

| Engineering Task | Primary Files to Inspect & Modify | Relevant Tests |
| :--- | :--- | :--- |
| **Change audition checklist or flow ordering** | [`AuditionDetailView.swift`](../OneTake/Views/AuditionDetailView.swift), [`Models.swift`](../OneTake/Models/Models.swift) (`Piece`) | `OneTakeTests/AuditionTests.swift` |
| **Modify PDF import or OCR extraction** | [`NoticeOCR.swift`](../OneTake/ModelViews/NoticeOCR.swift), [`AddAuditionFlow.swift`](../OneTake/Views/AddAuditionFlow.swift) | `scripts/test_separate_pdf_import.py`, `scripts/test_notice_and_script_parsers.py` |
| **Modify Script sides scene splitting** | [`ScriptParser.swift`](../OneTake/Models/ScriptParser.swift) | `scripts/test_notice_and_script_parsers.py` |
| **Change camera controls, timer, or zoom** | [`CameraController.swift`](../OneTake/ModelViews/CameraController.swift), [`ShootViews.swift`](../OneTake/Views/ShootViews.swift) | `OneTakeTests/CameraAndImageTests.swift`, `scripts/test_recording_reliability.py` |
| **Modify take trimming or playback** | [`TakesViews.swift`](../OneTake/Views/TakesViews.swift), [`Models.swift`](../OneTake/Models/Models.swift) (`Take`) | `OneTakeTests/ShootAndTakeTests.swift` |
| **Change state persistence or sequence ordering** | [`Persistence.swift`](../OneTake/Models/Persistence.swift), [`AppStore.swift`](../OneTake/ModelViews/AppStore.swift) | `OneTakeTests/PersistenceTests.swift`, `scripts/test_persistence_reliability.py` |
| **Modify backup creation or crash-recovery restore** | [`LocalBackup.swift`](../OneTake/Models/LocalBackup.swift), [`ProfileViews.swift`](../OneTake/Views/ProfileViews.swift) | `OneTakeTests/LocalBackupTests.swift`, `scripts/test_phase8_remediation.py` |
| **Modify deliverable packaging or ZIP generation** | [`ZipArchive.swift`](../OneTake/ModelViews/ZipArchive.swift), [`PackageViews.swift`](../OneTake/Views/PackageViews.swift) | `OneTakeTests/ZipArchiveTests.swift`, `scripts/test_export_performance.py` |
| **Modify iCloud public download link sharing** | [`CloudLink.swift`](../OneTake/ModelViews/CloudLink.swift), [`AppStore.swift`](../OneTake/ModelViews/AppStore.swift) | `OneTakeTests/PackageAndSentTests.swift`, `scripts/test_sharing_lifecycle.py` |
| **Change widget or Live Activity updates** | [`WidgetSync.swift`](../OneTake/ModelViews/WidgetSync.swift), [`Shared/WidgetSnapshot.swift`](../Shared/WidgetSnapshot.swift) | `OneTakeWidgets/` |
