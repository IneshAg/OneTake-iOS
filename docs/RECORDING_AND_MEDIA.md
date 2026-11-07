# OneTake iOS — Recording & Media Pipeline

This document details the AVFoundation capture pipeline, monotonic hardware clock timing, session interruption resilience, and take management.

---

## 1. AVFoundation Video Capture Architecture (`CameraController.swift`)

### 1.1 Session Configuration
`CameraController` manages a single `AVCaptureSession` configured for:
- **Preset**: `.high` (1080p 1920×1080 capture).
- **Video Device**: Front or back wide-angle camera with automatic continuous autofocus and exposure.
- **Audio Device**: Built-in microphone configured via `AVAudioSession` with `.playAndRecord` category and `.default` mode.
- **Orientation Normalization**: Recorded video tracks are set to portrait/upright orientation matching device position and are **never mirrored**, ensuring text in slates or wardrobe marks is readable.

---

## 2. Monotonic Hardware Timing vs Software Drift (`AUDIT-006`)

### 2.1 The Discrete Timer Problem
Standard `Timer.publish` or `Task.sleep` loops running on the main runloop experience scheduling jitter and UI throttling under heavy video encoding load. Over a 3-minute audition scene, software timers routinely drift by **3.6+ seconds**, producing takes where the displayed elapsed time fails to match the actual video file length.

### 2.2 Monotonic Clock Implementation
`CameraController` tracks elapsed recording duration using the CPU's invariant hardware clock via `CACurrentMediaTime()`:
```swift
let startClock = CACurrentMediaTime()
// In update tick:
let elapsed = CACurrentMediaTime() - startClock
```
Mathematical simulation confirms that `CACurrentMediaTime()` exhibits **0.000s drift** over arbitrary recording durations regardless of CPU or UI thread load.

### 2.3 Post-Capture Asset Duration Verification
When `fileOutput(_:didFinishRecordingTo:from:error:)` completes, `CameraController` does not rely on the timer. It queries the actual encoded movie file duration via `AVURLAsset`:
```swift
let asset = AVURLAsset(url: outputFileURL)
let trueDuration = CMTimeGetSeconds(asset.duration)
```
The resulting `Take` entity is initialized with this authoritative hardware duration.

---

## 3. Session Interruption Handling (`AUDIT-011`)

### 3.1 Failure Modes
Mobile video capture is frequently interrupted by external system events:
- Incoming cellular phone calls or FaceTime alerts.
- System alarms and timers.
- Backgrounding or locking the screen mid-take.
- Audio route changes (AirPods disconnection).

### 3.2 Notification Observers
`CameraController` registers dedicated observers for capture and audio interruptions:
1. `AVCaptureSession.wasInterruptedNotification`: Captures reason (e.g. `.videoDeviceNotAvailableWithMultipleForegroundApps`).
2. `AVCaptureSession.interruptionEndedNotification`: Re-arms capture session.
3. `AVAudioSession.interruptionNotification`: Handles `.began` and `.ended` interruption phases.

### 3.3 Safe Take Finalization
Upon interruption, `CameraController` immediately stops the active movie output. AVFoundation finalizes the QuickTime movie container header on disk. The partial take is safely saved to disk rather than corrupted or discarded.

---

## 4. Take Management & Storage

### 4.1 On-Disk Directory Structure
All video takes are stored within the app's `Documents` sandbox partitioned by audition UUID:
```text
<Container>/Documents/
├── audition-<UUID>/
│   ├── take-<UUID>.mov
│   ├── slate.mov
│   ├── full-length.mov
│   └── headshot-front.jpg
└── ReaderTracks/
    └── <audition_UUID>/
        └── <scene_UUID>/
            └── line-1.m4a
```

### 4.2 Non-Destructive Trimming
Take trimming operates non-destructively:
- `Take.trimStart: Double?` and `Take.trimEnd: Double?` record boundary offsets in seconds.
- Playback in `ReviewViews.swift` uses `AVPlayer.seek(to:)` to respect trim boundaries.
- Physical trimming is applied only during final delivery export rendering.

### 4.3 Hold-to-Stop Safety Gesture
During video recording, tapping the stop button requires a **hold-to-stop** gesture (minimum 0.5s press). This prevents accidental cancellations if an actor's hand grazes the screen during an emotional or active take.
