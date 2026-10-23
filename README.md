# OneTake · iOS 🎬

> **The actor's self-tape audition studio.** Built with **SwiftUI**, **AVFoundation**, and **VisionKit** for iOS 18+.

[![iOS](https://img.shields.io/badge/iOS-18.0%2B-blue.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.10%20%2F%206.0-orange.svg?style=flat&logo=swift)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple.svg?style=flat)](https://developer.apple.com/xcode/swiftui/)
[![Build](https://img.shields.io/badge/build-passing-brightgreen.svg?style=flat)](https://github.com/IneshAg/OneTake-iOS/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 📱 Overview

**OneTake** is a dedicated audition recording studio and production assistant built for actors. It streamlines the entire self-tape lifecycle—from parsing casting notices and running lines with an automated teleprompter to filming multi-take scenes, running pre-flight checks, and packaging finished tapes to casting specifications.

Designed meticulously around the **OneTake v2 · Light / Dark** design system with Velvet color tokens, dynamic system typography, and distraction-free filming ergonomics.

> 🤖 **Android Companion:** Looking for the Android version? Check out [OneTake-Android](https://github.com/IneshAg/OneTake-Android), built with Kotlin, Jetpack Compose, and CameraX.

---

## ✨ Key Features

### 🏠 Hero Audition & Schedule
- **Hero Audition Card**: At-a-glance dashboard showing your most urgent upcoming self-tape deadline, hours remaining, and today's practice schedule.
- **Readiness Dial**: Visual completion indicator dynamically calculated from script memorization, slate status, and recorded scenes.

### 📋 Audition Pipeline & Sides Scanner
- **Library Management**: Filter auditions seamlessly across `Active`, `Due Soon`, `Ready`, and `Sent`.
- **Sides Scanner**: Capture printed script pages directly using Apple's VisionKit (`VNDocumentCameraViewController`).
- **Pieces Checklist**: Automatically track deliverables required by casting (Headshots, Spoken Slate, Full-Length Profile, Scene Takes).

### 🎭 Prepare & Voice Rehearsal Studio
- **Line Memorization Modes**: Switch between `Full lines`, `First letters` (mnemonic practice), and `Hide mine` (hide your dialogue for memory recall).
- **Voice-Follow Teleprompter**: Automatic scrolling powered by on-device Speech Recognition (`SFSpeechRecognizer`) and `AVAudioEngine`.
- **Reader Tracks**: Rehearse sides with your own recorded voice tracks or synthetic speech reader tracks.

### 🎥 Studio Camera & Filming HUD
- **Live Camera Studio**: Hardware-accelerated camera preview hosted via `AVCaptureVideoPreviewLayer`.
- **Pre-Roll Slate & Countdown**: Automated 3-2-1 slate countdown with spoken slate overlay before scene capture begins.
- **Exposure Lock & Grid**: Manual exposure locking and rule-of-thirds eye-line framing guides.
- **Hold-to-Stop Protection**: Ergonomic hold-to-stop trigger to prevent accidental capture termination during emotional scenes.

### ⭐ Takes Review & Automated Tape Check
- **Circle Takes**: Scrub through recorded takes and long-press/tap to star (circle) your hero take for delivery. No take-comparison screen by design — the loop stays record → check → keep/retake/edit.
- **Automated Tape Check**: Real-time pre-flight verification checking for framing positioning, eye-line alignment, and audio clipping/room noise.

### 📦 Casting Package & Delivery
- **One-Tap Packaging**: Package final videos according to industry standards without tedious external video editing.
- **Export Presets**: Dedicated export configurations tailored for:
  - **Actors Access**
  - **Casting Networks**
  - **Spotlight**
  - **Direct Agency Email** (custom size/resolution optimization)
- **Share Sheet Integration**: Native iOS system share sheet supporting AirDrop, Mail, and Files export.

### 👤 Actor Profile, Slate & Headshots
- **Digital Slate Studio**: Configure spoken slate specifications (Full Name, Height, Location/Based In, Representation) with real-time text and speech preview.
- **Headshot Studio**: Guided capture flow for front, 3/4 left, and 3/4 right angles with oval face alignment overlays.
- **Privacy First**: 100% on-device data retention. All media stays local to your device until explicitly exported.

---

## 🏛️ Architecture & Tech Stack

The application leverages modern Swift 5.10 / Swift 6 paradigms with a clean modular structure:

```
OneTake/
├── App/
│   ├── OneTakeApp.swift        # App entry point, TabView hierarchy, sheet handlers
│   └── AppStore.swift          # Centralized observable state & navigation router
├── DesignSystem/
│   ├── Theme.swift             # Velvet tokens, semantic colors, light/dark providers
│   └── Components/
│       └── Components.swift    # Custom buttons, dials, status tags, cards & HUD elements
├── Models/
│   ├── Models.swift            # Audition, Scene, Take, Slate, Deliverable & LineLearningMode data structures
│   └── SampleData.swift        # Mock auditions and call sheets for simulator testing
├── Features/
│   ├── Onboarding/             # Welcome + slate setup only — guest-first, no sign-in wall, no upfront permission prompts
│   ├── Auditions/              # Auditions library (absorbs what used to be a separate Home tab), add-audition flow, and detail breakdown
│   ├── Prepare/                # Line memorization studio, reader audio, and teleprompter
│   ├── Shoot/                  # Filming flows, live preview HUD, exposure lock
│   ├── Takes/                  # Takes review, scrubbing, and automated tape check
│   ├── Practice/               # Practice hub, scene drills, and practice recordings
│   ├── Profile/                # Profile management, slate configuration, headshot studio
│   └── Package/                # Export packaging and destination presets
├── UIKitBridges/
│   ├── CameraController.swift  # AVFoundation session management, photo & video output
│   └── UIKitBridges.swift      # VisionKit scanner, ShareSheet, haptic feedback generators
└── Resources/
    └── Assets.xcassets         # Accent colors, headshots, and system symbols
```

### System Framework Integrations

| Capability | System Framework / API |
|---|---|
| **Video & Photo Capture** | `AVFoundation` (`AVCaptureSession`, `AVCaptureMovieFileOutput`, `AVCapturePhotoOutput`) |
| **Document Scanning** | `VisionKit` (`VNDocumentCameraViewController`) |
| **Speech Recognition & Prompter** | `Speech` (`SFSpeechRecognizer`) & `AVFAudio` (`AVAudioEngine`) |
| **Synthesized Speech Reader** | `AVFoundation` (`AVSpeechSynthesizer`) |
| **Haptic Feedback** | `UIKit` (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`, `UISelectionFeedbackGenerator`) |
| **Share & Export** | `UIKit` (`UIActivityViewController`) |
| **Declarative Project Generation** | `XcodeGen` (`project.yml`) |

---

## 🚀 Getting Started

### Prerequisites

- **macOS Sonoma** or **macOS Sequoia**
- **Xcode 16+** with the iOS 18+ SDK
- **Homebrew** (for installing `xcodegen`)

### Installation & Project Generation

OneTake uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to maintain a clean git history free of cumbersome `.xcodeproj` merge conflicts.

1. **Clone the repository:**
   ```bash
   git clone https://github.com/IneshAg/OneTake-iOS.git
   cd OneTake-iOS
   ```

2. **Install XcodeGen (if not already installed):**
   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode project:**
   ```bash
   xcodegen generate
   ```

4. **Open and build:**
   ```bash
   open OneTake.xcodeproj
   ```

5. Select an **iPhone 16 / iPhone 16 Pro Simulator (iOS 18+)** or a physical device and press **⌘R** to run.

---

## 📱 Simulator vs. Physical Device Notes

- **Camera Feeds**: The iOS Simulator does not have access to a hardware camera sensor; OneTake automatically provides high-resolution simulated studio backgrounds so you can test all teleprompter and UI flows smoothly.
- **Physical Device**: To record live video takes and capture headshots with real sensor hardware, select your target iPhone and configure your Development Team under *Signing & Capabilities* in Xcode.

---

## 🎨 Design System & Ergonomics

- **Velvet Color Scheme**: Minimalist aubergine palette optimized for low eye fatigue in dimly lit studio environments.
- **Amber Signals Urgency**: Amber is reserved strictly for time-critical states (audition due dates, countdown timers).
- **Fail-Safe Filming**: Accidental taps are avoided during shoots via hold-to-stop buttons and prominent status indicators.
- **Full Light & Dark Mode**: Dynamic color providers ensure rich contrast across all lighting conditions.

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
