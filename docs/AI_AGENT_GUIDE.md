# OneTake iOS — Autonomous AI Agent Guide

This document is the **mandatory onboarding and operational protocol** for any Large Language Model (LLM) coding agent working in the OneTake iOS repository. It provides complete operational context, constraints, and execution discipline without requiring access to prior chat sessions.

---

## 1. Project Identity & Inviolable Product Invariants

OneTake is a personal on-device self-tape studio for actors. You must uphold these product invariants across all tasks:

1. **Explicit Non-Goals**:
   - ❌ **NEVER introduce casting marketplace / talent directory features.**
   - ❌ **NEVER introduce AI dramatic acting evaluation, performance scoring, or emotional critique.**
   - ❌ **NEVER replace actor-recorded reader cues with AI-generated synthetic voices.**
2. **Export Options**:
   - 🔒 Keep user-facing deliverable choices strictly limited to:
     1. **Share Link** (hosted public iCloud Drive download link).
     2. **Separate Elements** (local `.zip` archive containing individual clip files).
   - Do not reintroduce combined single-video direct exports or arbitrary destination selectors.
3. **Independent Document Separation (`WORKFLOW-PDF-01`)**:
   - 📄 The **Casting Call PDF** and **Script Sides PDF** are separate documents. Importing one must **never** overwrite or erase the other.
4. **Data Isolation**:
   - 🎭 Practice drills and practice pieces must remain completely isolated from active audition recording checklists.
5. **Slate & Full Length Independence**:
   - 🎬 Full Length video recording is required **only** when the casting notice explicitly requests it. Otherwise, it must not appear in the active audition checklist.

---

## 2. Before You Modify Code: Mandatory Inspection Protocol

Before editing any file:
1. Read [`README.md`](../README.md) and [`docs/INDEX.md`](INDEX.md).
2. Read [`docs/WORK_IN_PROGRESS.md`](WORK_IN_PROGRESS.md) to understand current active branch status and incomplete tasks.
3. Consult [`docs/CODEBASE_MAP.md`](CODEBASE_MAP.md) to locate the exact source files and types involved.
4. Review [`docs/ENGINEERING_DECISIONS.md`](ENGINEERING_DECISIONS.md) to avoid violating existing architectural decisions (ADRs).
5. Inspect `git status` and `git log -n 5 --oneline` to establish baseline HEAD.

---

## 3. Engineering Rules & Concurrency Invariants

- **MainActor Safety**: All UI state, `@Published` properties, and view navigation belong strictly on `@MainActor`. All disk writing and JSON serialization must occur off-MainActor inside `StateStorage` actor.
- **Monotonic Sequence Ordering**: Always increment `saveSequence` on state changes and pass it to `StateStorage.writeSnapshot`. Never bypass sequence validation.
- **Dirty-State Retention**: Never clear `hasUncommittedChanges = false` unless `saveSequence == operation.sequence`. If a new edit occurred while a background write was in flight, the dirty flag must remain `true`.
- **Background Assertions**: Always wrap background disk writes in `BackgroundTaskToken` and coordinate them via `FlushOperation`. Never allow double-ending of UIKit assertions.
- **Restore Recovery Safety**:
  - Never delete or rename the root `Documents` directory container inode.
  - Never store restore journals or rollback data in `tmp/`; always use `Application Support/OneTake/`.
  - On rollback, delete only incoming items recorded in `incomingManifest`. If an ambiguous entry is encountered, halt recovery, preserve the ambiguous file, and retain rollback storage.
  - Verify restored file size and streaming `zlib` CRC32 checksums before cleaning up rollback storage.
- **No Blanket `try?`**: Never swallow errors on critical persistence, backup, or file deletion paths.

---

## 4. Task Execution Protocol

For every engineering task:

1. **Understand**: Clarify requirements and establish exact success criteria.
2. **Inspect**: Inspect the real Swift source code and existing tests.
3. **Plan**: Formulate a minimal, targeted implementation plan without broad refactoring.
4. **Implement**: Make clean, focused changes preserving existing comments and docstrings.
5. **Test**: Run all relevant test suites and regression scripts:
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
6. **Diff Review**: Inspect `git diff` to confirm zero unintended changes, debug prints, or temporary files.
7. **Document**: Update relevant documentation in `docs/` and update [`docs/WORK_IN_PROGRESS.md`](WORK_IN_PROGRESS.md).
8. **Commit**: Create a clean, conventional commit (e.g. `fix(...)`, `feat(...)`, `docs(...)`).
9. **Report**: Report factually what was implemented, what was verified, and what remains unverified.

---

## 5. Verification Discipline (Strict Truth in Reporting)

You must explicitly separate test evidence into these distinct categories:
- **Native Xcode Build**: Only report if `xcodebuild build` actually ran on macOS.
- **Native XCTest**: Only report if `xcodebuild test` ran inside an iOS Simulator.
- **Source Inspection**: State when verification was based on static code analysis.
- **Python Static / Simulated Tests**: Report script execution results honestly. Never claim that passing Python tests equates to native Swift XCTest execution.
- **Physical Device**: Only report if tested on real iOS hardware.

---

## 6. Session Handoff Protocol

At the end of any substantial task, the agent **must** update [`docs/WORK_IN_PROGRESS.md`](WORK_IN_PROGRESS.md) with:
- Current branch and commit hash.
- Summary of work completed.
- Exact tests executed and their results.
- Unverified items and remaining risks.
- Concrete next steps for the incoming agent.
