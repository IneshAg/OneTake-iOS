# OneTake iOS — Testing & Quality Assurance

This document details the test framework, test directory structure, automated test harnesses, and the strict classification of verification evidence.

---

## 1. Test Architecture & Directory Structure

```text
OneTake-iOS/
├── OneTakeTests/                      # Native Swift XCTest Suites
│   ├── AuditionTests.swift            # Audition checklist, piece ordering, and migration
│   ├── CameraAndImageTests.swift      # Monotonic recording clock and interruption handling
│   ├── LocalBackupTests.swift         # Backup manifest, inode safety, crash recovery, CRC32
│   ├── PackageAndSentTests.swift      # Deliverable packaging, CloudLink sharing, revocation
│   ├── PersistenceTests.swift         # Off-MainActor storage, FlushOperation, background tokens
│   ├── ShootAndTakeTests.swift        # Take entity duration, trimming, and circle takes
│   └── ZipArchiveTests.swift          # System zlib CRC32 vectors, ZIP header parsing
│
└── scripts/                           # Automated Python Regression & Verification Harnesses
    ├── test_notice_and_script_parsers.py # Vision OCR & regex chunking integration
    ├── test_separate_pdf_import.py       # Dual-document PDF workflow isolation (Phase 1)
    ├── test_local_backup_safety.py       # Root Documents container inode preservation (Phase 2)
    ├── test_persistence_reliability.py   # StateStorage actor & monotonic sequence ordering (Phase 3)
    ├── test_recording_reliability.py     # CACurrentMediaTime monotonic timer simulation (Phase 4)
    ├── test_export_performance.py        # System zlib IEEE 802.3 test vectors & benchmarks (Phase 5)
    ├── test_sharing_lifecycle.py         # iCloud folder mapping, delete, and legacy safety (Phase 6)
    ├── test_phase7_quality.py            # Regex parse caching, RecordButton accessibility (Phase 7)
    └── test_phase8_remediation.py        # Reconciled rollback, FlushOperation winner races (Phases 8-8.2)
```

---

## 2. Evidence Classification Standard

To ensure engineering truth, testing evidence must **never** conflate simulation with native iOS execution. All test reports adhere to this six-tier classification:

1. **Native Xcode Build**: Compilation of the project schemes against the official iOS SDK using `xcodebuild`.
2. **Native XCTest Execution**: Execution of Swift unit and integration tests inside an active iOS Simulator or device kernel.
3. **Static Source Inspection**: Automated or manual validation verifying that required types, signatures, access controls, and invariants exist in the source code.
4. **Python Automated Tests**: Independent scripts parsing code or exercising Python models of algorithms (e.g. CRC32 vector validation, regex chunking).
5. **Simulated Filesystem Tests**: Scripts replicating OS kernel behavior (atomic file renaming, directory rollback, token lifecycle) in a local temp directory.
6. **Physical-Device Tests**: Direct verification on an iPhone checking hardware camera sensors, thermal throttling, and UIKit lifecycle transitions.

---

## 3. How to Run Tests

### 3.1 macOS Environment (Native Apple Toolchain)
```bash
# 1. Generate Xcode project
xcodegen generate

# 2. Run all unit test suites on iPhone 16 Pro simulator
xcodebuild test \
  -project OneTake.xcodeproj \
  -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'

# 3. Run individual test suites
xcodebuild test \
  -project OneTake.xcodeproj \
  -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:OneTakeTests/LocalBackupTests \
  -only-testing:OneTakeTests/PersistenceTests
```

### 3.2 Non-macOS / Cross-Platform Environment (Python Harnesses)
To run the complete automated regression suite across all remediation phases:
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

---

## 4. Latest Verified Test Status (as of Commit `d4a3e8b`)

| Suite | Scope / Invariant Verified | Status |
| :--- | :--- | :--- |
| `test_notice_and_script_parsers.py` | Role detection, notice extraction, 90% payload reduction, scene boundaries | **PASS (100%)** |
| `test_separate_pdf_import.py` | Casting call & script sides independent import, replacement, persistence | **PASS (100%)** |
| `test_local_backup_safety.py` | Documents container inode preservation, manifest corruption pre-flight | **PASS (100%)** |
| `test_persistence_reliability.py` | Off-MainActor storage, atomic writes, monotonic sequence ordering | **PASS (100%)** |
| `test_recording_reliability.py` | Monotonic hardware clock (0.000s drift vs 3.60s discrete timer drift) | **PASS (100%)** |
| `test_export_performance.py` | System zlib CRC32 IEEE 802.3 compliance, 2,600× throughput speedup | **PASS (100%)** |
| `test_sharing_lifecycle.py` | Ubiquity folder tracking, deletion on clear/delete, safe legacy link handling | **PASS (100%)** |
| `test_phase7_quality.py` | Regex parse caching (2.9× speedup), accessibility hints, App Group centralization | **PASS (100%)** |
| `test_phase8_remediation.py` | Durable snapshot, unrecorded file removal, ambiguous file preservation, FlushOperation | **PASS (100%)** |
