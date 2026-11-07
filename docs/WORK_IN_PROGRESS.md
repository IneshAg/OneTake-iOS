# Current Work Handoff (Active State)

**Last Updated**: 2026-11-07  
**Audience**: Incoming human engineers and autonomous AI coding agents.

---

## 1. Repository State

- **Current Branch**: `ocr-column-reconstruction`
- **Current HEAD**: `d4a3e8b` (`fix(reliability): verify restore recovery and persistence race invariants (Phase 8.2)`)
- **Working Tree**: Clean (all code changes committed).
- **History**: All 10 remediation commits (`6527bb2` through `d4a3e8b`) are preserved sequentially.

---

## 2. Summary of Recently Completed Work

### Phase 8.2 Remediation & Verification (`d4a3e8b`)
1. **Restore Ambiguous File Isolation**:
   - Captured `incomingManifest` in `RestoreJournal`.
   - Reconciled restore recovery: any entry in `Documents` absent from `originalSnapshot`, `rollback`, and `incomingManifest` is treated as ambiguous external data.
   - Recovery **halts**, preserves the ambiguous file, retains rollback storage and journal, and surfaces a recoverable error.
2. **Content Integrity Verification**:
   - `OriginalEntrySnapshot` records file sizes and streaming `zlib` CRC32 checksums.
   - Post-restore verification checks byte counts and checksums without loading large media files into memory. Rollback storage is preserved if verification fails.
3. **Persistence Dirty-State Sequence Matching**:
   - `hasUncommittedChanges` is only cleared if `self.saveSequence == operation.sequence`.
   - If user edits occurred on `@MainActor` while an asynchronous flush was writing to disk, the dirty flag remains `true` for subsequent save.

---

## 3. Test Verification Status

### Executed Tests
All 9 automated regression and verification harnesses were executed and passed **100% (43/43 tests)**:
1. `scripts/test_notice_and_script_parsers.py`: **PASS** (Vision OCR, 90% payload reduction, role detection)
2. `scripts/test_separate_pdf_import.py`: **PASS** (Dual-document import, independent replacement, persistence)
3. `scripts/test_local_backup_safety.py`: **PASS** (Root Documents inode preservation, pre-flight manifest checks)
4. `scripts/test_persistence_reliability.py`: **PASS** (StateStorage actor, monotonic sequence ordering, atomic writes)
5. `scripts/test_recording_reliability.py`: **PASS** (Monotonic clock 0.000s drift vs 3.60s discrete timer drift)
6. `scripts/test_export_performance.py`: **PASS** (System zlib CRC32 IEEE 802.3 test vectors, 2,600× speedup)
7. `scripts/test_sharing_lifecycle.py`: **PASS** (Ubiquity folder mapping, delete cleanup, safe legacy unmapped handling)
8. `scripts/test_phase7_quality.py`: **PASS** (Regex caching 2.9× speedup, RecordButton accessibility hints, AppGroup centralization)
9. `scripts/test_phase8_remediation.py`: **PASS** (Durable snapshot, unrecorded file deletion, ambiguous file preservation, FlushOperation winner logic)

### Tests Not Executed on Current Host
- **Native `xcodebuild build`**: Not executed (host environment is Windows 11).
- **Native `xcodebuild test`**: Not executed (host environment is Windows 11).
- **Physical Device Testing**: Not executed (no physical iOS hardware attached).

---

## 4. Remaining Work & Technical Debt

1. **macOS CI Runner Execution**: Execute native `xcodebuild test` on a macOS runner (e.g. GitHub Actions `macos-14`) to confirm clean compilation against the iOS 18 SDK.
2. **Apple Foundation Models Integration (iOS 18.2+)**: Wire on-device Foundation Models framework into `TapeCheck` for natural-language framing suggestions.
3. **Google Sign-In Production OAuth Keys**: Inject production OAuth client IDs in release build configurations.

---

## 5. Exact Next Steps for Incoming Agent / Engineer

1. Clone or pull the branch `ocr-column-reconstruction`.
2. Confirm working tree status: `git status`.
3. If on macOS, run:
   ```bash
   xcodegen generate
   xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
   ```
4. If on Windows/Linux, run:
   ```powershell
   python scripts/test_phase8_remediation.py
   ```
5. Review [`docs/INDEX.md`](INDEX.md) and [`docs/AI_AGENT_GUIDE.md`](AI_AGENT_GUIDE.md) before implementing new features.

---

## 6. Suggested Next Task Prompt

```text
Please inspect the current branch ocr-column-reconstruction in OneTake-iOS, review docs/WORK_IN_PROGRESS.md, and assist in configuring the GitHub Actions CI workflow to run xcodegen generate and xcodebuild test on a macos-14 runner.
```
