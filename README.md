# OneTake · iOS 🎬

> **The personal self-tape audition studio for actors.** Built with SwiftUI, AVFoundation, Vision, and VisionKit for iOS 18+.

[![Build](https://github.com/IneshAg/OneTake-iOS/actions/workflows/build.yml/badge.svg)](https://github.com/IneshAg/OneTake-iOS/actions/workflows/build.yml)
[![iOS](https://img.shields.io/badge/iOS-18.0%2B-blue.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Docs](https://img.shields.io/badge/Docs-Complete-green.svg)](docs/INDEX.md)

---

## 🎭 What is OneTake?

OneTake is a dedicated personal self-tape studio for actors. It guides an actor through the complete self-tape lifecycle:
1. **Intake**: Ingests casting notice requirements and script sides as independent documents.
2. **Rehearse**: Helps actors learn lines with an adaptive prompter and their own recorded reader cues.
3. **Shoot**: Films the slate, full-body shots (when requested), and scene takes with a monotonic hardware clock and interruption protection.
4. **Inspect**: Analyzes technical framing, headroom, audio levels, and lighting via on-device Vision and AVFoundation tape checks.
5. **Deliver**: Packages deliverables into industry-standard filenames as either a local `.zip` of separate elements or a published temporary iCloud download link.

**OneTake operates 100% locally and offline.** There are no user sign-ups, tracking analytics, or third-party servers. All scripts, takes, and headshots remain on the actor's device.

> [!NOTE]
> **Explicit Non-Goals**: OneTake is **not** a casting marketplace or job board. It does not grade or score acting performance, and it does not synthesize AI voice replacements for scene partners.

---

## ✨ Core Capabilities

- **Independent Document Ingestion**: Ingests Casting Call PDFs and Script Sides PDFs independently. Updating a casting call preserves existing script scenes; revising sides preserves notice metadata.
- **Line Rehearsal & Prompter**: Record partner dialogue line-by-line. Speech recognition follows the actor's voice and automatically plays the recorded reader's cues.
- **Monotonic Recording Clock**: `CameraController` tracks elapsed time using `CACurrentMediaTime()` (0.000s drift) and queries true `AVURLAsset` durations upon file completion.
- **Hold-to-Stop Protection**: Prevents accidental take termination during emotional scenes.
- **Tape Check Analysis**: Objective technical analysis of headroom, centring, audio clipping, volume levels, and contrast. Never judges dramatic acting.
- **Crash-Safe Local Backups**: Creates portable ZIP backups. Restore operations preserve root container inodes, maintain durable journals in Application Support, verify streaming `zlib` CRC32 checksums, and safely isolate ambiguous files.
- **Deliverable Packaging**: Generates `{LAST}_{FIRST}_{ROLE}_{PROJECT}` deliverables. Export choices are strictly limited to **Share Link** (iCloud Drive) and **Separate Elements** (`.zip`).
- **Widgets & Dynamic Island**: Home Screen widgets, Lock Screen deadline countdowns, and Live Activities in the final 24 hours before submission.

---

## 🏛️ Repository Layout

```text
OneTake-iOS/
├── OneTake/                       # Main iOS Application Target
│   ├── Models/                    # Data models, persistence, backup, script parsing
│   ├── Views/                     # SwiftUI views, navigation, design system
│   ├── ModelViews/                # AppStore coordinator, camera, tape check, ZIP archive
│   ├── Info.plist                 # Target configuration properties
│   └── OneTake.entitlements       # App Group & iCloud capabilities
├── OneTakeWidgets/                # WidgetKit & Live Activity Extension
├── OneTakeShare/                  # Action / Share Extension (PDF intake from Mail/Files)
├── Shared/                        # Code shared between app and extensions (AppGroup, ShareInbox)
├── OneTakeTests/                  # Native Swift XCTest suites
├── scripts/                       # Automated regression & verification test harnesses
├── dataset/                       # Sample audition breakdowns and script sides for testing
├── docs/                          # Comprehensive technical and product documentation
└── project.yml                    # Declarative XcodeGen project specification
```

---

## 🚀 Getting Started

### Prerequisites
- macOS 14 (Sonoma) or macOS 15 (Sequoia).
- Xcode 16.0 or later with the iOS 18.0+ SDK.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

### Build & Run
```bash
# 1. Clone repository
git clone https://github.com/IneshAg/OneTake-iOS.git
cd OneTake-iOS

# 2. Install XcodeGen and generate project
brew install xcodegen
xcodegen generate

# 3. Open in Xcode
open OneTake.xcodeproj
```
Select the **OneTake** scheme and run on an iOS 18+ simulator or device.

---

## 🧪 Testing & Verification

### Native Swift XCTest (macOS)
```bash
xcodebuild test \
  -project OneTake.xcodeproj \
  -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Automated Cross-Platform Regression Suites (Python)
To run the full 9-phase automated verification suite:
```powershell
python scripts/test_notice_and_script_parsers.py
python scripts/test_separate_pdf_import.py
python scripts/test_local_backup_safety.py
python scripts/test_persistence_reliability.py
python scripts/test_recording_reliability.py
python scripts/test_export_performance.py
python scripts/test_sharing_lifecycle.py
python scripts/test_phase7_quality.py
python scripts/test_phase8_remediation.py
```
*Current test status: 43/43 tests passing 100% across all regression suites.*

---

## 📚 Documentation & Handoff

Detailed technical documentation is maintained in the [`docs/`](docs/INDEX.md) directory:

- **[Documentation Index (`docs/INDEX.md`)](docs/INDEX.md)**: Master hub linking all technical references.
- **[Autonomous AI Agent Guide (`docs/AI_AGENT_GUIDE.md`)](docs/AI_AGENT_GUIDE.md)**: Mandatory guidelines, invariants, and execution discipline for LLM coding assistants.
- **[Current Work Handoff (`docs/WORK_IN_PROGRESS.md`)](docs/WORK_IN_PROGRESS.md)**: Active branch state, latest commit, and next engineering tasks.
- **[Project Overview (`docs/PROJECT_OVERVIEW.md`)](docs/PROJECT_OVERVIEW.md)**: Product philosophy, target users, and explicit non-goals.
- **[Product Specification (`docs/PRODUCT_SPECIFICATION.md`)](docs/PRODUCT_SPECIFICATION.md)**: Detailed screen and subsystem specifications with verification statuses.
- **[System Architecture (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md)**: Concurrency models, `@MainActor` state flow, and actor boundaries.
- **[Codebase Map (`docs/CODEBASE_MAP.md`)](docs/CODEBASE_MAP.md)**: File directory, symbol inventory, and practical navigation guide.
- **[Persistence & Backup (`docs/PERSISTENCE_AND_BACKUP.md`)](docs/PERSISTENCE_AND_BACKUP.md)**: Off-MainActor `StateStorage`, background task lifecycle, and durable restore recovery.
- **[Engineering Decisions (`docs/ENGINEERING_DECISIONS.md`)](docs/ENGINEERING_DECISIONS.md)**: Architecture Decision Records (ADRs).
- **[Audit & Remediation History (`docs/AUDIT_AND_REMEDIATION_HISTORY.md`)](docs/AUDIT_AND_REMEDIATION_HISTORY.md)**: Complete chronicle of remediation commits from Phase 1 to Phase 8.2.
- **[Known Issues (`docs/KNOWN_ISSUES.md`)](docs/KNOWN_ISSUES.md)**: Documented platform limitations and open technical debt.

---

## 📄 License

MIT — see [LICENSE](LICENSE).
