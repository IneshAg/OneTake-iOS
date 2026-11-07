# OneTake iOS — Export, Packaging & Sharing Lifecycle

This document details deliverable compilation, streaming ZIP packaging with system `zlib` CRC32, and the iCloud public share link lifecycle.

---

## 1. Deliverable Formats & Product Constraints

OneTake supports strictly **two** user-facing export choices:

1. **Share Link**: Uploads the audition package to the user's personal iCloud Drive ubiquity container and generates an authenticated public download link.
2. **Separate Elements**: Compiles an organized `.zip` archive containing individual clip files (`SLATE.mp4`, `SCENE_1.mp4`, `HEADSHOT.jpg`).

> [!IMPORTANT]
> **Product Constraint**: User-facing options are strictly limited to `Share Link` and `Separate Elements`. Direct combined video concatenation and custom destination selection were intentionally removed from the user-facing workflow to ensure clean, consistent deliverables matching casting industry expectations.

### 1.1 Deliverable Naming Standard
All deliverable files adhere to standard industry naming templates:
```text
{LAST}_{FIRST}_{ROLE}_{PROJECT}.mp4
{LAST}_{FIRST}_{ROLE}_{PROJECT}_SEPARATE.zip
```
Actors can optionally customize filename templates in settings using supported tokens: `{lastName}`, `{firstName}`, `{role}`, `{project}`, `{take}`.

---

## 2. High-Performance ZIP Archiving (`ZipArchive.swift`)

### 2.1 Zero-Dependency ZIP Compiler
[`OneTake/ModelViews/ZipArchive.swift`](../OneTake/ModelViews/ZipArchive.swift) implements a zero-dependency ZIP compiler written directly in Swift. It builds standard ZIP local file headers, central directory records, and end-of-central-directory markers conforming to PKWARE ZIP standards.

### 2.2 System `zlib` Streaming CRC32 (`AUDIT-005`)
- **The Performance Problem**: Historically, CRC32 was calculated using an un-vectorized bitwise loop (`crc = (crc >> 1) ^ 0xedb88320`). On a typical 150MB audition video, the bitwise loop took over **110 seconds**, freezing the device.
- **The Optimization**: Replaced the bitwise loop with Apple's hardware-accelerated system `zlib` implementation (`zlib.crc32`).
- **Performance Benchmark**:
  - Un-vectorized bitwise loop: ~75ms per 100KB (projected ~115s for 150MB).
  - System `zlib` CRC32: ~0.029ms per 100KB (projected ~44ms for 150MB).
  - **Throughput Speedup**: **2,600× faster**, processing 150MB video files in milliseconds without frame drops.
- **Streaming Implementation**: Reads files in 1MB chunks via `FileHandle` without buffering full video files into memory, keeping memory usage constant.

---

## 3. iCloud Public Share Link Lifecycle (`CloudLink.swift`)

### 3.1 Upload & Link Generation
When an actor chooses `Share Link`:
1. Creates a unique folder in the app's iCloud Drive container:
   `iCloud~com~srmist~onetake/Documents/Tapes/<UUID>/`
2. Copies deliverable files into this ubiquitous folder.
3. Awaits background upload via `NSFileManager` ubiquity item monitoring.
4. Generates a public download link using Apple's API:
   ```swift
   var expiration: NSDate?
   let link = try fm.url(forPublishingUbiquitousItemAt: destination, expiration: &expiration)
   ```
5. Persists `shareLink: URL?` and `shareUbiquityFolderURL: URL?` in the `Audition` record.

### 3.2 Revocation Architecture & Safety (`AUDIT-007` & `AUDIT-FINDING-04`)
When an audition is deleted or the link is revoked:
- **Explicit Folder Deletion**: `CloudLink.revokeDetails(...)` targets the exact persisted directory `ubiquityFolderURL`. Deleting this folder removes the local copy, triggering CloudKit to delete the remote cloud container and invalidate the public link.
- **Safe Legacy Handling**: Older records generated prior to Phase 6 contain public URLs (`https://www.icloud.com/iclouddrive/<hash>`) but lack a recorded folder URL. Because public URLs use server-generated opaque hashes that have no relationship to client-side UUIDs, searching or guessing folder names risked deleting another audition's files.
- **Revocation Outcome States**:
  - `.revoked`: Folder located via `ubiquityFolderURL` and deleted.
  - `.alreadyRevoked`: Folder already absent (idempotent success).
  - `.unmappedLegacyLink`: Legacy link without folder reference; logged and preserved without touching any filesystem directories.
  - `.failed(String)`: I/O or filesystem error.

> [!NOTE]
> **Distinction Between Local Deletion and Remote Invalidation**: Local deletion removes the ubiquitous item from the device container, queuing a CloudKit deletion request with Apple's servers. True remote public link invalidation depends on iCloud network sync. Legacy unmapped links remain active until their server-side expiration date elapses.
