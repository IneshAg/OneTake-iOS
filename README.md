# OneTake · iOS 🎬

> **The actor's self-tape audition studio.** SwiftUI, AVFoundation, Vision and VisionKit, for iOS 18+.

[![Build](https://github.com/IneshAg/OneTake-iOS/actions/workflows/build.yml/badge.svg)](https://github.com/IneshAg/OneTake-iOS/actions/workflows/build.yml)
[![iOS](https://img.shields.io/badge/iOS-18.0%2B-blue.svg?style=flat&logo=apple)](https://developer.apple.com/ios/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

OneTake takes an actor from a casting notice to a finished self-tape: it reads the notice and the
sides, helps you learn the lines, films the slate and every scene with a prompter and your own
recorded reader, checks the tape, and packages it the way casting asked. There's no server and no
sign-up — everything stays on the iPhone until you send it.

On supported newer iOS releases, OneTake also uses Apple's on-device Foundation Models framework
to explain casting notices and turn measured Tape Check findings into practical retake guidance.
The media checks remain deterministic (Vision and AVFoundation); the model only explains those
measured facts and never replaces them. Older supported iOS releases use the existing local parser
and deterministic guidance.

> 🤖 **Android:** [OneTake-Android](https://github.com/IneshAg/OneTake-Android) (Kotlin, Jetpack Compose, CameraX).

---

## ✨ Features

### Auditions
- **Add from anywhere** — paste the notice, take a photo, scan the pages (VisionKit), pick a PDF or
  text file, type it in, or **Share → OneTake** from Mail, WhatsApp, Safari, Photos or Files.
  Everything is read on-device (Vision OCR, PDFKit).
- **Reads the notice** — role, project, due date, number of scenes and what casting asked for
  (slate, full length, landscape, length limit, destination). Anything it can't find, you fill in.
- **Splits the sides into scenes** at each slugline (`INT.` / `EXT.`) or `SCENE 2` header, and marks
  your lines.
- **Checklist per audition** — headshot, slate, optional full length and one piece per scene, with a
  single "Next" action that opens whatever's next.
- Edit details, revised sides, callbacks, and filters for Active / Due this week / Sent / All.

### Learn the lines
- **Prepare** — full lines, first letters, or hide yours (tap to peek), with casting's notes on top.
- **Run lines** — your recorded reader plays their lines; speech recognition follows yours and moves on
  when you've said it. Say "Line?" for a prompt. The end screen shows which lines you got on your own,
  and that becomes the scene's "lines learned".
- **Quick drills** — First-Letter prompts, Mask & Reveal (hide a quarter to all of each line), Audio Gap,
  and a hands-free Audio Walk loop.
- **Record the reader** in your own voice, one line at a time, per scene.

### Shoot
- Front or back camera at 1080p, recorded upright however the phone is held and never mirrored.
- Pinch to zoom or tap the zoom control to cycle through 1×, 1.5× and 2× framing.
- A visible timer control enables or disables the 3-second countdown before recording.
- Slate, optional full length, then each scene — with a scene picker and “Next: Scene N”.
- Hands-free: say "Action" / "Cut" (only when said on their own), or use a volume button, Camera Control
  or an AirPods stem press. The prompter follows your voice and plays your reader lines.
- Hold-to-stop while rolling, so a stray tap can't end an emotional take.

### Takes, Tape Check and sending
- Takes per scene, circle your send take, trim, and private notes.
- **Tape Check** analyses only the finalized/circled clips that will be sent: face in frame, distance,
  headroom, centring, head turn, lighting, silence, quiet voice, clipping, plus the package itself
  (slate, every scene shot, length, orientation, file name). The navigation bar is hidden to keep the
  check focused on the results.
- **Preview** the whole tape with accurate chapter durations (real duration for slate and scene chapters)
  and quick chapter actions to change headshots, retake the slate or full-length tape, and open takes for
  a specific scene.
- **Package** generates a merged `.mp4` (`LAST_FIRST_ROLE_PROJECT.mp4`) plus a separate `.zip` archive
  containing finalized clips and headshots via custom zero-dependency streaming. Tapping the Audio row
  opens Tape Check, and "Preview the whole tape" opens the local tape preview.
- **Sent screen** shows a destination-aware headline, persisted send date, actual destination, scene count,
  merged video and separate ZIP deliverables, and link expiration when applicable.
- Send through the Share Sheet (AirDrop, Mail, Files, a casting site's app) sharing both the merged MP4 and
  separate ZIP archive, or as an **iCloud download link** from your own iCloud Drive. Sending a link is the
  one place OneTake asks you to sign in, with Apple or Google; headshots go along as photos.

### Profile and the rest
- Slate details, front / left / right headshots with a guide overlay, reader volume, appearance.
- Deadline reminders (morning of, two hours before) scheduled locally, Home and Lock Screen widgets, and
  a Live Activity countdown in the last 24 hours.
- Privacy & data shows what's stored and deletes it; the privacy policy is in the app.

---

## 🏛️ Project layout

```
OneTake/
├── App/            AppStore (state + navigation), app entry & routes, Reminders, WidgetSync
├── DesignSystem/   Velvet colour tokens (light/dark) and shared components
├── Models/         Audition, Take, Scene, Slate… and ScriptParser
├── Persistence/    JSON state on disk (tolerant of damaged records), media and headshot storage
├── Features/       Auditions, Onboarding, Prepare, Practice, Shoot, Takes (incl. TapeAnalyzer),
│                   Package (MediaExporter, CloudLink, Preview), Profile
├── UIKitBridges/   CameraController (AVFoundation), speech follower, reader audio, trimmer, scanner
└── Resources/      Asset catalog, PrivacyInfo.xcprivacy
OneTakeWidgets/     Widgets and the Live Activity
OneTakeShare/       "Share to OneTake" extension
Shared/             Code shared with the extensions (widget snapshot, share inbox)
OneTakeTests/       Unit tests
project.yml         XcodeGen project definition
```

---

## 🚀 Getting started

Requirements: macOS with **Xcode 16 or later** (building with the iOS 26 SDK also turns on the
search-tab behaviour) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/IneshAg/OneTake-iOS.git
cd OneTake-iOS
brew install xcodegen
xcodegen generate
open OneTake.xcodeproj
```

Run on an iPhone simulator or a device (set your team under *Signing & Capabilities*). On a device,
the iCloud container `iCloud.com.onetake.app` and the App Group `group.com.onetake.app` must be
registered for your team for "Email or link" sending, widgets and the share extension. The open
build leaves Sign in with Apple disabled because its capability requires a paid Apple Developer
account; a paid team can enable the capability and set `AppleSignInEnabled: true` in `project.yml`.
For Google sign-in, set `GOOGLE_CLIENT_ID` and `GOOGLE_REVERSED_CLIENT_ID` in `project.yml` to your
OAuth client (until then the Google button stays disabled).

Tests: **⌘U** in Xcode, or

```bash
xcodebuild test -project OneTake.xcodeproj -scheme OneTake -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI (`.github/workflows/build.yml`) builds for the Simulator and for a device and runs the unit tests on
every push and pull request.

### Simulator notes
The Simulator has no camera, so the camera screens show a plain silhouette and headshot capture saves a
placeholder; recording itself needs a real iPhone.

---

## 📄 License

MIT — see [LICENSE](LICENSE).
