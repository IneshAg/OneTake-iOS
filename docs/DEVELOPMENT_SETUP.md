# OneTake iOS — Development Setup Guide

This guide provides step-by-step instructions for setting up a local development environment, generating the Xcode project, and building OneTake iOS.

---

## 1. Prerequisites

- **Host Machine**: macOS 14 (Sonoma) or macOS 15 (Sequoia).
- **Xcode**: Xcode 16.0 or later with the iOS 18.0+ SDK installed.
- **Swift**: Swift 5.10 or later.
- **XcodeGen**: Fast, declarative Xcode project generator (`brew install xcodegen`).
- **CocoaPods / Carthage**: Not required (dependencies are managed via Swift Package Manager in `project.yml`).

---

## 2. Initial Setup

### 2.1 Clone the Repository
```bash
git clone https://github.com/IneshAg/OneTake-iOS.git
cd OneTake-iOS
```

### 2.2 Install XcodeGen
If XcodeGen is not already installed on your Mac:
```bash
brew install xcodegen
```

### 2.3 Generate the Xcode Project
OneTake uses declarative project specification via `project.yml`. The `.xcodeproj` directory is generated automatically:
```bash
xcodegen generate
```
This generates `OneTake.xcodeproj` with three targets:
1. `OneTake`: The main iOS application.
2. `OneTakeWidgets`: The WidgetKit and Live Activity extension.
3. `OneTakeShare`: The Action / Share extension.

---

## 3. Configuration & Signing

### 3.1 Development Team & Bundle Identifiers
Open `project.yml` or the generated Xcode project:
- **Default Bundle ID**: `com.srmist.onetake`
- **Default App Group**: `group.com.srmist.onetake`
- **Team ID**: Change `DEVELOPMENT_TEAM` in `project.yml` to your own Apple Developer Team ID if building to a physical device.

### 3.2 Google Sign-In & Sign in with Apple Configuration
In [`OneTake/Info.plist`](../OneTake/Info.plist) and [`project.yml`](../project.yml):
- **Google Sign-In**: Placeholder client IDs are configured (`YOUR_CLIENT_ID.apps.googleusercontent.com`). Until configured with a real Google Cloud OAuth Client ID, the Google Sign-In button stays safely disabled in the UI.
- **Sign in with Apple**: Disabled by default (`AppleSignInEnabled: false`) in open builds to prevent authorization crashes when running without a paid Apple Developer Team certificate.

---

## 4. Building and Running

### 4.1 Running in the Simulator
1. Open `OneTake.xcodeproj` in Xcode:
   ```bash
   open OneTake.xcodeproj
   ```
2. Select the `OneTake` scheme and an iOS 18+ simulator (e.g. `iPhone 16 Pro`).
3. Press `Cmd + R` to build and run.

### 4.2 Building via Command Line
```bash
xcodebuild build \
  -project OneTake.xcodeproj \
  -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### 4.3 Running Tests
```bash
xcodebuild test \
  -project OneTake.xcodeproj \
  -scheme OneTake \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

---

## 5. Troubleshooting Common Issues

| Issue | Root Cause | Solution |
| :--- | :--- | :--- |
| **`xcodegen: command not found`** | XcodeGen not installed | Run `brew install xcodegen`. |
| **App Group entitlement error** | Provisioning profile mismatch on device | When deploying to a physical device, register `group.<your_id>` in your Apple Developer account and update `project.yml`. |
| **Simulator camera shows black screen** | iOS Simulator lacks hardware camera sensor | `CameraController` detects simulator execution and provides sample test frames for framing previews. |
| **Sign in button disabled** | Placeholder OAuth IDs configured | Expected behavior; local features run 100% offline without signing in. |
