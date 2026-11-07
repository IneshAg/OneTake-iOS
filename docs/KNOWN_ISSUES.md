# OneTake iOS — Known Issues & Technical Limitations

This document tracks verified limitations, technical debt, and open engineering issues.

---

## [ISSUE-001] Legacy Pre-Phase 6 Public Cloud Links Cannot Be Locally Revoked

- **Status**: Open / Intentional Safety Limitation
- **Severity**: Low
- **Affected Area**: Cloud Sharing (`CloudLink.swift`)
- **Observed Behavior**: Attempting to revoke a public download link created prior to Phase 6 (commit `87ac708`) returns `.unmappedLegacyLink` and does not delete the remote file.
- **Evidence**: `CloudLink.revokeDetails` returns `.unmappedLegacyLink` when `ubiquityFolderURL == nil`.
- **Reproduction Steps**: Create an audition with a legacy public link URL but no folder URL, then tap "Revoke share link".
- **Likely Cause**: Apple's `url(forPublishingUbiquitousItemAt:expiration:)` creates opaque server-side tokens that cannot be reverse-mapped to local directory UUIDs without dangerous guesswork.
- **Workaround**: The link automatically becomes inactive when Apple's server-side expiration timestamp elapses.
- **Files Involved**: [`OneTake/ModelViews/CloudLink.swift`](../OneTake/ModelViews/CloudLink.swift).
- **Suggested Next Investigation**: Explore CloudKit private database record tracking as a secondary index for hosted links.

---

## [ISSUE-002] Native Compilation & XCTest Execution Requires macOS Runner

- **Status**: Blocked by Environment
- **Severity**: Medium
- **Affected Area**: CI / Build Automation
- **Observed Behavior**: Windows host environments can run AST verification, static token checks, and Python simulation scripts, but cannot run native `xcodebuild` or native XCTest suites.
- **Evidence**: `Get-Command xcodebuild` fails on Windows.
- **Reproduction Steps**: Attempt to execute `xcodebuild` in Windows PowerShell.
- **Likely Cause**: Apple's iOS SDK, simulator runtimes, and compiler toolchains are macOS-exclusive.
- **Workaround**: Automated Python test harnesses validate algorithmic and filesystem invariants on Windows; native builds are executed on macOS CI runners.
- **Files Involved**: `project.yml`, `scripts/`.
- **Suggested Next Investigation**: Ensure GitHub Actions workflow (`.github/workflows/build.yml`) runs on `macos-14` or `macos-15` runners with Xcode 16.

---

## [ISSUE-003] Google Sign-In & Sign in with Apple Disabled by Default in Open Builds

- **Status**: Configured / Awaiting Production Keys
- **Severity**: Low
- **Affected Area**: Authentication (`OneTake/Info.plist`, `ProfileViews.swift`)
- **Observed Behavior**: Tapping Google Sign-In or Sign in with Apple does not initiate authentication in local development builds.
- **Evidence**: `AppleSignInEnabled: false` in `project.yml`; `GOOGLE_CLIENT_ID` set to placeholder `YOUR_CLIENT_ID.apps.googleusercontent.com`.
- **Reproduction Steps**: Open Profile → Sign In.
- **Likely Cause**: Production OAuth client IDs and paid Apple Developer Team capabilities cannot be committed to open repositories.
- **Workaround**: The app operates 100% offline without signing in; authentication is needed only for hosted iCloud public link sharing.
- **Files Involved**: `project.yml`, [`OneTake/Info.plist`](../OneTake/Info.plist), [`OneTake/Views/ProfileViews.swift`](../OneTake/Views/ProfileViews.swift).
- **Suggested Next Investigation**: Document team secret injection via environment variables in CI/CD pipeline.

---

## [ISSUE-004] UIKit Background Execution Assertion Grants ~30 Seconds Budget

- **Status**: Documented Architecture Limitation
- **Severity**: Low
- **Affected Area**: Persistence & Export (`BackgroundTaskCoordinator.swift`)
- **Observed Behavior**: Background persistence flushes succeed reliably for JSON state saves (~5ms), but massive multi-gigabyte video export encoding cannot complete within the background assertion window.
- **Evidence**: iOS enforces standard execution limits on `UIApplication.beginBackgroundTask`.
- **Reproduction Steps**: Initiate export of five 4K takes and immediately lock the device.
- **Likely Cause**: iOS suspends apps that exceed their background execution budget.
- **Workaround**: Heavy video packaging and ZIP compilation must remain foreground-bound, displaying an active progress overlay to the actor.
- **Files Involved**: [`OneTake/ModelViews/BackgroundTaskCoordinator.swift`](../OneTake/ModelViews/BackgroundTaskCoordinator.swift), [`OneTake/Views/PackageViews.swift`](../OneTake/Views/PackageViews.swift).
- **Suggested Next Investigation**: Evaluate `BGProcessingTask` (BackgroundTasks framework) for scheduled overnight heavy video compression.
