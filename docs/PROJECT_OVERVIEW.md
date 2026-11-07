# OneTake iOS — Project Overview

## 1. Product Identity & Definition

**OneTake** is a dedicated, privacy-first personal self-tape audition studio for professional and aspiring actors. It guides the actor through the complete audition lifecycle: ingesting casting notices and script sides, learning lines with a recorded reader, filming slate and scene takes with an adaptive prompter, conducting automated technical tape checks, and packaging deliverables exactly as requested by casting directors.

OneTake runs on iOS 18+ and is built using native **SwiftUI**, **AVFoundation**, **Vision**, and **VisionKit**.

---

## 2. Product Philosophy

1. **Privacy-First & Local-By-Default**:
   Actors' rehearsal takes, audition footage, and unpublished scripts are sensitive personal and intellectual property. OneTake stores all video, audio, and draft metadata strictly on the local device. There are no tracking analytics, third-party media servers, or shadow cloud uploads.
2. **Actor Control & Dignity**:
   The actor makes all artistic decisions. The app never tells an actor how to perform or grades their dramatic delivery. Software tools exist solely to handle technical friction (framing, audio levels, line prompts, filename formatting, and deliverable bundling).
3. **Deterministic Core**:
   Media capture, checksum calculations, timer hardware clocks, persistence sequence ordering, and file packaging rely strictly on deterministic system frameworks. Machine learning (Vision OCR, Foundation Models) is employed exclusively for parsing assistance and explaining measured technical facts—never for subjective evaluation.

---

## 3. Explicit Non-Goals (What OneTake Is Not)

To maintain product focus and integrity, the following capabilities are explicitly out of scope:

- ❌ **Casting Marketplace / Job Board**:
  OneTake is not a marketplace. It does not list audition breakdowns, connect actors with agents, or host public talent directories. Actors import notices they receive independently.
- ❌ **AI Acting Evaluation / Performance Scoring**:
  OneTake will never score dramatic performance, evaluate emotional expression, or judge acting quality. Automated checks are limited strictly to objective technical factors: headroom, volume clipping, framing centring, lighting levels, and deliverable compliance.
- ❌ **AI Voice Generation / Synthetic Actor Replacement**:
  OneTake will not synthesize synthetic reader voices. Actors record their own reader cues line-by-line in their own voice to rehearse organically.

---

## 4. Primary Use Cases

1. **New Audition Setup**:
   An actor receives an audition breakdown email containing a casting call flyer and multi-page script sides. They share the documents to OneTake or import them directly. OneTake extracts deadline, role requirements, scene boundaries, and reader dialogue cues into an organized audition checklist.
2. **Independent Rehearsal ("Run Lines")**:
   The actor records their reader cues once. Using on-device speech recognition, the teleprompter listens as the actor speaks their lines and automatically triggers the recorded reader response when the actor finishes.
3. **Self-Tape Recording**:
   The actor films their slate and required scenes. The app maintains a monotonic elapsed timer, handles camera and audio interruptions safely, and provides a hold-to-stop safety buffer to prevent accidental cancellation during emotional takes.
4. **Packaging & Delivery**:
   The actor circles their selected takes. OneTake compiles the deliverables into an industry-standard package: either an organized `.zip` file of separate elements or a published temporary iCloud download link.

---

## 5. Account & Network Requirements

| Capability | Account Requirement | Network Requirement |
| :--- | :--- | :--- |
| **Notice Parsing & OCR** | None (Local on-device) | 100% Offline |
| **Line Practice & Teleprompter** | None (Local on-device speech recognition) | 100% Offline |
| **Video & Slate Recording** | None (Local AVFoundation) | 100% Offline |
| **Local Export (Separate Elements .ZIP)** | None (Local system zlib compression) | 100% Offline |
| **Share Link (iCloud Download Link)** | Sign in with Apple or Google required | Active Internet Connection & iCloud Drive |

OneTake operates completely offline without user registration. Authentication (Apple or Google OAuth) is required exclusively when the user elects to generate an external hosted public download link via iCloud Drive.

---

## 6. Current Product Limitations

1. **Host Compilation Environment**: The primary codebase requires macOS with Xcode 16+ and the iOS 18 SDK to compile native binaries.
2. **Pre-Phase 6 Cloud Links**: Public share links created prior to Phase 6 that lack a persisted folder URL cannot be deterministically mapped to disk UUIDs and must elapse naturally via server-side expiration.
3. **Background Export Limits**: Background execution assertions grant ~30 seconds of execution time; heavy multi-gigabyte video exports must remain foreground-bound.
