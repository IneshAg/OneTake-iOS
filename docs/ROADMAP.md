# OneTake iOS — Product & Engineering Roadmap

This document outlines completed milestones, work in progress, and planned future initiatives based on verified codebase state.

---

## 1. Completed Milestones

- ✅ **Independent Document Import (`WORKFLOW-PDF-01`)**: Decoupled Casting Call PDF and Script Sides PDF workflows.
- ✅ **Safe Container Backup & Restore (`AUDIT-001`)**: Root Documents directory inode preserved during restore.
- ✅ **Off-MainActor Persistence (`AUDIT-003`, `010`)**: `StateStorage` actor with monotonic sequence numbers.
- ✅ **Monotonic Hardware Recording Clock (`AUDIT-006`, `011`)**: `CACurrentMediaTime()` elapsed time and interruption recovery.
- ✅ **High-Performance Export (`AUDIT-005`)**: System `zlib` streaming CRC32 (2,600× throughput speedup).
- ✅ **iCloud Share Link Revocation (`AUDIT-007`)**: Persisted `shareUbiquityFolderURL` and safe legacy revocation.
- ✅ **Parsing Optimization & Accessibility (`AUDIT-012`, `013`, `016`)**: Screenplay regex caching, VoiceOver hints, centralized App Group.
- ✅ **Durable Restore Journaling & Background Assertion (`Phase 8`)**: Application Support journal storage outside `tmp/`, `BackgroundTaskToken` thread-safety.
- ✅ **Restore Snapshot Reconciliation & Synchronized Flush (`Phase 8.1`)**: Pre-flight snapshot, unrecorded file deletion, `FlushOperation` winner logic.
- ✅ **Content Integrity & Ambiguous File Isolation (`Phase 8.2`)**: CRC32 integrity validation, ambiguous external file preservation, sequence-matched dirty state.

---

## 2. In Progress

- 🟡 **macOS CI / CD Pipeline Setup**: Automating `xcodegen generate` and `xcodebuild test` across GitHub Actions on `macos-14` / `macos-15` runners.
- 🟡 **Comprehensive Technical Documentation & AI Handoff**: Creating complete Markdown documentation suite for human contributors and autonomous AI coding agents.

---

## 3. Planned Initiatives

- 📋 **Apple Foundation Models Integration (iOS 18.2+)**: On-device LLM integration via Apple's native Foundation Models framework for explaining complex casting breakdown requirements and converting Tape Check measurements into actionable framing tips.
- 📋 **Audio Prompter Whisper Mode**: Enhancing on-device speech recognition to follow quiet or whispered dramatic line delivery without false prompts.
- 📋 **Multi-Camera Selection**: Support for ultra-wide camera lenses for small-room audition setups where standard 1× distance is constrained.
- 📋 **Background Video Processing Task (`BGProcessingTask`)**: Exploring scheduled background compression for multi-scene 4K auditions that exceed transient UIKit execution windows.

---

## 4. Blocked / Needs Investigation

- ⏸️ **Direct CloudKit Legacy Link Revocation**: Blocked by Apple's lack of client-side reverse index lookups from opaque public link hashes to container directories. (Legacy links elapse safely via server-side expiration).
