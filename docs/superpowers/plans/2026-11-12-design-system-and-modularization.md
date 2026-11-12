# OneTake Design System & Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ad-hoc, per-screen styling with one reusable, compiler-enforced design system (`OneTakeUI` package) and reorganise the app into feature modules so every button, card, header and bottom bar is built from the same parts.

**Architecture:** A local Swift package `Packages/OneTakeUI` owns all tokens (colour, type, spacing, radius, icon and control sizes), a single parameterised button style, surfaces, and pure UI components; it cannot see `AppStore`/`HeadshotStore`, so it stays reusable. The app is regrouped into `App/`, `Core/`, `Features/<Feature>/`, `Shared/UI/`, mega-files are split one-primary-view-per-file, and a lint script (warning → error) stops raw literals coming back.

**Tech Stack:** Swift 5.10, SwiftUI, iOS 18.0 floor, XcodeGen (`project.yml` is the source of truth), XCTest, local SwiftPM package.

**Spec:** The user's request (2026-11-12): *"overhaul our current codebase to pioneer code reusability … that's the reason the buttons are different sizes and elements are just not the same. Ensure modularity as well."* plus the audit below.

---

## Audit (why this plan exists)

Measured on `main @ d093f79`:

| Symptom | Count |
|---|---|
| Distinct `cornerRadius:` literals | 17 values (14×58, 12×44, 8×32, 10×30, 16×28, 18×12 …) |
| Distinct `minHeight:` literals | 17 values (44, 50, 40, 56, 52, 48, 46, 34 …) |
| `.font(.system(size:` bypassing type tokens | 222 |
| Raw `.padding(<number>)` | 400+ (14, 4, 10, 12, 16, 2, 6 … ) |
| Hand-rolled `background(OT.fillField/surfaceCard, in: RoundedRectangle…)` vs `.otCard()` | 67 vs 40 |
| Button styles in use | 4 custom + `.bordered`, `.borderedProminent`, `.glass`, `.glassProminent`, 120× `.plain` with hand-built labels |
| `Menu` labels hand-styled to *look* like buttons | 16 (root cause of the mismatched Retake / Pick-from-Photos pair) |
| `.safeAreaInset(edge: .bottom)` bars, each built differently (one had no background) | 19 |
| Screens repeating `InContentNavHeader` + `.toolbar(.hidden…)` + `.otCanvas()` + gutter padding | 38 |
| `onDark:` boolean flags threaded through components | 37 |
| Files > 2,000 lines | `AddAuditionFlow` 4,688 · `ProfileViews` 2,794 · `PrepareViews` 2,237 · `AuditionDetailView` 2,174 · `ShootViews` 2,062 |
| `Components.swift` | 1,155 lines mixing generic UI with audition-domain cards |
| Widget target compiles `OneTake/Views/Theme.swift` by file path | coupling hack |

---

## Global Constraints

- iOS deployment target stays `18.0`; Swift `5.10`; package `swift-tools-version: 5.10`, `platforms: [.iOS(.v18)]`.
- `project.yml` is the only project definition. Every file add/move ends with `xcodegen generate`; never hand-edit `project.pbxproj`. Team stays `SCY3DW3F4W`, bundle IDs unchanged.
- `OneTakeUI` must not import or reference app types (`AppStore`, `HeadshotStore`, `Audition`, routes). If a component needs app data, it takes plain values/closures, or it lives in `OneTake/Shared/UI/`.
- Token names keep the `OT` prefix (`OT.accent`, `Font.otHeadline`) so existing call sites keep compiling; new scales are `OTSpace`, `OTRadius`, `OTIconSize`, `OTControlSize`.
- **Control sizes (exact):** `.large` = 50 pt visual height (bottom-bar CTAs, full-width actions) · `.medium` = 40 pt (inline action rows, toolbars) · `.small` = 34 pt visual / 44 pt hit-target height (chips, compact actions). Heights are minimums (`minHeight`) so Dynamic Type can grow them.
- **One size per row:** buttons/menus placed side by side in one `HStack` must share one `OTControlSize`.
- **Bottom bars:** every bottom action area uses `.otBottomBar { … }`; at most one `.primary` and one `.secondary` action; opaque `OT.bgCanvas` background.
- **Menus that look like buttons** use `.buttonStyle(.ot(…))` (or `OTMenuButton`), never a hand-built label.
- **Dark/camera surfaces:** set `.otSurface(.camera)` once on the container; components read it from the environment. No new `onDark:` parameters.
- **Escape hatch:** a literal that is genuinely content geometry (e.g. a 300 pt photo grid) carries a trailing `// ot-lint:allow <reason>`.
- **Spacing scale (`OTSpace`):** `xxs 2 · xs 4 · s 8 · m 12 · l 16 · xl 24 · xxl 32`; semantic `gutter 16 · cardInset 16 · rowInset 12 · stack 12 · section 24`. Legacy → token rule: 1–3→xxs, 4–6→xs, 7–10→s, 11–13→m, 14–18→l, 19–26→xl, ≥27→xxl.
- **Radius scale (`OTRadius`):** `xs 4 · s 8 · m 12 · control 14 · l 16 · xl 20 · card 24`. Legacy rule: ≤5→xs, 6–9→s, 10–12→m, 13–14→control, 15–17→l, 18–21→xl, ≥22→card; values used to draw circles (55, 120) become `Circle()`/`Capsule()`.
- **Icon scale (`OTIconSize`):** `xs 11 · s 13 · m 15 · l 17 · xl 22 · xxl 28 · hero 40`; `.font(.system(size: N))` on an `Image` maps to the nearest, ties round up.
- **Type:** existing `Font.ot*` names are canonical but are rebuilt on text styles so they follow Dynamic Type (today they're fixed `system(size:)` and never scale): `otLargeTitle` = `.largeTitle.bold()` (34), `otHero` = `.largeTitle.bold()` (32→34), `otTitle` = `.title.bold()` (28), `otHeadline` = `.headline` (17 semibold), `otBody` = `.body` (17), `otCallout` = `.subheadline` (15), `otSubhead` = `.subheadline.weight(.medium)`, `otFootnote` = `.footnote` (13), `otCaption` = `.caption` (12), `otEyebrow` = `.footnote.weight(.semibold)`, `otNumber` = `.largeTitle.bold().monospacedDigit()`; new `otButtonSmall` = `.subheadline.weight(.semibold)`, `otCaptionStrong` = `.caption.weight(.semibold)`. `.font(.system(size:))` on `Text` maps to the nearest token. `Font.otIcon(_:)` uses `@ScaledMetric`-equivalent scaling relative to `.body`.
- Every task ends green on: `xcodebuild build -destination 'generic/platform=iOS'` and `xcodebuild test … -only-testing:OneTakeTests/ModelTests -only-testing:OneTakeTests/DesignSystemTests` (the 8 pre-existing `NoticeParserTests` failures on `main` are out of scope and must not grow).
- Work happens on branch `refactor/design-system`; one commit per task.

## Review Focus

1. **Dynamic Type at accessibility sizes** — buttons, headers and bottom bars grow rather than clip at `.accessibility3`. Pinned by `testButtonsGrowWithDynamicType` (Task 2).
2. **Menus beside buttons** — a `Menu` styled `.ot(.secondary)` renders the exact same height as a `Button` of the same size (the bug the user reported). Pinned by `testMenuMatchesButtonHeight` (Task 2).
3. **Bottom bar over scrolling content** — content never shows through the bar. Pinned by `testBottomBarIsOpaque` (Task 3).
4. **Camera (always-dark) screens** — Shoot/TapePreview keep white-on-glass controls in Light Mode after `onDark` removal. Pinned by `testCameraSurfaceUsesLightForeground` (Task 2) + Task 12 screenshot check in Light Mode.
5. **Widget extension** — still builds and renders after `Theme.swift` moves into the package. Pinned by the Task 1 widget-target build step.

---

## File Structure (end state)

```
Packages/OneTakeUI/
  Package.swift
  Sources/OneTakeUI/
    Tokens/      Colors.swift (OT, UIColor(light:dark:)) · Typography.swift · Spacing.swift (OTSpace)
                 Radius.swift (OTRadius) · IconSize.swift · ControlSize.swift · Surface.swift
    Styles/      OTButtonStyle.swift · CardStyle.swift · PressStyles.swift
    Components/  OTScreen.swift · OTBottomBar.swift · OTNavHeader.swift · OTIconButton.swift
                 OTSheetHeader.swift · OTMenuButton.swift · OTCallout.swift · OTStatusLine.swift
                 OTSectionLabel.swift · OTIconRow.swift · OTChip.swift · OTEmptyState.swift
                 OTProgressRing.swift
    Support/     Haptics.swift
    Gallery/     OTGallery.swift   (#Preview of every component, light/dark/camera)
OneTake/
  App/           OneTakeApp.swift · RootTabView.swift · RouteDestinations.swift · OneTakeUIExports.swift
  Core/          Models/ · Persistence/ · Services/ (Camera, MediaExporter, NoticeOCR, TapeAnalyzer …)
                 Store/ AppStore.swift + AppStore+Navigation/+Auditions/+Practice/+Headshots.swift
                 Bridges/ one file per UIKit bridge (DocumentScanner, VideoTrimmer, ReaderAudioTrimmer,
                          ScriptTextEditor, TabBarVisibility, KeepScreenAwake, SwipeBack)
  Shared/UI/     HeadshotImage.swift · ProfileButton.swift · PhotoSourceMenu.swift
  Features/      Auditions/ · AuditionDetail/ · AddAudition/ · Prepare/ · Practice/ · Shoot/
                 Takes/ · Package/ · Headshots/ · Profile/ · Onboarding/
scripts/lint-design-system.sh · scripts/design-lint-baseline.txt
OneTakeTests/DesignSystemTests.swift
docs/DESIGN_SYSTEM.md
```

Rule for Features: one primary view per file, no file over 800 lines, feature-private subviews are `private`/`fileprivate` in the same folder.

---

## Phase 0 — Safety net

### Task 0: Branch, lint baseline, screenshot baseline

**Files:**
- Create: `scripts/lint-design-system.sh`, `scripts/design-lint-baseline.txt`
- Modify: `project.yml` (OneTake target `preBuildScripts`, `ENABLE_USER_SCRIPT_SANDBOXING: NO` for that target)

**Interfaces:**
- Produces: `scripts/lint-design-system.sh [--xcode] [--strict] [--path <dir>]`. Default: prints per-rule counts and exits 1 if any count exceeds `design-lint-baseline.txt`. `--xcode`: emits `file:line: warning: [rule] message`. `--strict`: exits 1 on any violation. `--path`: limits scanning to one folder (used per migration task). Scans `OneTake/` (excluding `Packages/`) and `OneTakeWidgets/`; skips lines containing `ot-lint:allow`.

Rules (id → ERE):
| id | pattern |
|---|---|
| `radius` | `cornerRadius: *[0-9]` |
| `font-size` | `\.font\(\.system\(size:` |
| `frame-literal` | `\.frame\([^)]*(minHeight\|height\|minWidth\|width): *[0-9]{2,}` |
| `padding-literal` | `\.padding\((\.[a-zA-Z]+, *)?[0-9]` |
| `raw-color` | `Color\(UIColor\(\|Color\(red:\|Color\.(white\|black)\.opacity` |
| `system-button-style` | `\.buttonStyle\(\.(bordered\|borderedProminent\|glass\|glassProminent)\)` |
| `manual-surface` | `background\(OT\.(fillField\|surfaceCard\|surfaceRaised), *in:` |
| `hidden-navbar` | `\.toolbar\(\.hidden, *for: *\.navigationBar\)` |
| `on-dark-flag` | `onDark:` |

- [ ] **Step 1:** `git switch -c refactor/design-system`.
- [ ] **Step 2:** Write the script; run `scripts/lint-design-system.sh > scripts/design-lint-baseline.txt` — expected: a `rule count` line per rule with non-zero counts (e.g. `font-size 222`).
- [ ] **Step 3:** Run it again without changes — expected exit 0. Add a `cornerRadius: 3` line to a scratch Swift file under `OneTake/` — expected exit 1 naming `radius`; delete the scratch file.
- [ ] **Step 4:** Add to `project.yml` under `OneTake`: `preBuildScripts: - name: Design lint, script: "\"${SRCROOT}/scripts/lint-design-system.sh\" --xcode || true", basedOnDependencyAnalysis: false`, and `ENABLE_USER_SCRIPT_SANDBOXING: NO` in the target's `settings.base`. Run `xcodegen generate`, build — expected `** BUILD SUCCEEDED **` with design-lint warnings in the log.
- [ ] **Step 5:** Capture baseline screenshots (Light + Dark) on the iPhone 18 Pro simulator into `docs/design-baseline/` for: Auditions list, Audition detail, Add audition sheet, Notice review, Prepare, Run lines, Shoot setup, Shoot (camera), Takes, Tape preview, Package, Headshots, Profile, Practice, Onboarding first screen.
- [ ] **Step 6:** Commit `chore: add design lint baseline and screenshot baseline`.

---

## Phase 1 — `OneTakeUI` package

### Task 1: Package skeleton + tokens

**Files:**
- Create: `Packages/OneTakeUI/Package.swift`, `Sources/OneTakeUI/Tokens/*.swift`, `Sources/OneTakeUI/Support/Haptics.swift`, `OneTake/App/OneTakeUIExports.swift`, `OneTakeWidgets/OneTakeUIExports.swift`, `OneTakeTests/DesignSystemTests.swift`
- Delete: `OneTake/Views/Theme.swift` (contents move to `Tokens/Colors.swift` + `Tokens/Typography.swift`, made `public`)
- Modify: `OneTake/ModelViews/UIKitBridges.swift` (remove `enum Haptics`), `project.yml` (`packages: OneTakeUI: path: Packages/OneTakeUI`; add `- package: OneTakeUI` to OneTake, OneTakeWidgets, OneTakeTests; remove `- path: OneTake/Views/Theme.swift` from widgets)

**Interfaces:**
- Produces (all `public`): `enum OT` (every existing colour + `gutter`, `cardRadius`, `rowHeight`, `minTap`), `extension UIColor { init(light:dark:lightAlpha:darkAlpha:); init(hex:alpha:) }`, `extension Font` (existing `ot*` + `otButtonSmall`, `otCaptionStrong`), `enum OTSpace { static let xxs, xs, s, m, l, xl, xxl, gutter, cardInset, rowInset, stack, section: CGFloat }`, `enum OTRadius { static let xs, s, m, control, l, xl, card: CGFloat }`, `enum OTIconSize: CGFloat { case xs = 11, s = 13, m = 15, l = 17, xl = 22, xxl = 28, hero = 40 }`, `extension Font { static func otIcon(_ size: OTIconSize, weight: Font.Weight = .semibold) -> Font }`, `enum OTControlSize { case large, medium, small; var height: CGFloat; var hitHeight: CGFloat; var font: Font; var horizontalPadding: CGFloat }`, `enum Haptics` (unchanged API: `tick()`, `success()`, `warning()` …), existing `View.otCanvas()`, `View.otHitArea()`.
- `OneTakeUIExports.swift` contains exactly `@_exported import OneTakeUI` so no other file needs an import line.

- [ ] **Step 1: Write failing tests** in `DesignSystemTests.swift`:
```swift
func testControlSizes() {
    XCTAssertEqual(OTControlSize.large.height, 50)
    XCTAssertEqual(OTControlSize.medium.height, 40)
    XCTAssertEqual(OTControlSize.small.height, 34)
    XCTAssertEqual(OTControlSize.small.hitHeight, 44)
}
func testScales() {
    XCTAssertEqual([OTSpace.xxs, .xs, .s, .m, .l, .xl, .xxl], [2, 4, 8, 12, 16, 24, 32])
    XCTAssertEqual([OTRadius.xs, .s, .m, .control, .l, .xl, .card], [4, 8, 12, 14, 16, 20, 24])
    XCTAssertEqual(OTSpace.gutter, OT.gutter)
}
func testTypeTokensScaleWithDynamicType() {
    func h(_ size: DynamicTypeSize) -> CGFloat {
        UIHostingController(rootView: Text("Aa").font(.otBody).environment(\.dynamicTypeSize, size))
            .sizeThatFits(in: CGSize(width: 300, height: 500)).height
    }
    XCTAssertGreaterThan(h(.accessibility3), h(.large))
}
```
- [ ] **Step 2:** Run `-only-testing:OneTakeTests/DesignSystemTests` — expected: compile failure (`OTControlSize` not found).
- [ ] **Step 3:** Create the package and token files; move Theme/Haptics; update `project.yml`; `xcodegen generate`.
- [ ] **Step 4:** Run the tests — expected PASS. Build the app **and** the widget target (`-scheme OneTake` builds both) — expected `** BUILD SUCCEEDED **`.
- [ ] **Step 5:** Commit `feat(ui): add OneTakeUI package with design tokens`.

### Task 2: One button system

**Files:**
- Create: `Sources/OneTakeUI/Tokens/Surface.swift`, `Styles/OTButtonStyle.swift`, `Styles/PressStyles.swift`, `Components/OTMenuButton.swift`
- Modify: `OneTake/Views/Components.swift` (delete `PrimaryButtonStyle`, `SecondaryButtonStyle`, `CompactSecondaryButtonStyle`, `GlassLabelButtonStyle`, `PressableCardStyle`, `NativeNavPressStyle`, `CircularIconPressStyle`, the `Glass*Compatibility` modifiers and the `ButtonStyle` static extensions — all replaced below)
- Test: `OneTakeTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `enum OTSurface { case standard, camera }`, `View.otSurface(_:)`, `EnvironmentValues.otSurface`.
- `enum OTButtonVariant { case primary, secondary, tertiary, destructive, glass }` — tertiary = accent text, no fill; glass = iOS 26 `.glass` capsule with `.ultraThinMaterial` fallback on iOS 18–25.
- `struct OTButtonStyle: ButtonStyle { init(_ variant: OTButtonVariant, size: OTControlSize = .large, fullWidth: Bool = true) }` — reads `isEnabled` and `otSurface`; on `.camera` uses `OT.cameraLabel` foreground and `OT.cameraGlass` fill for non-primary variants. Radius `OTRadius.control` for large/medium, `OTRadius.m` for small.
- `extension ButtonStyle where Self == OTButtonStyle { static func ot(_ v: OTButtonVariant, size: OTControlSize = .large, fullWidth: Bool = true) -> Self; static var otPrimary: Self; static var otSecondary: Self; static var otCompact: Self /* .ot(.secondary, size: .small, fullWidth: false) */; static var otGlass: Self }` — keeps all 85 existing call sites compiling. `otSecondaryDark`/`otCompactDark` are removed; their 1 call site gets `.otSurface(.camera)`.
- `struct OTPressStyle: ButtonStyle { init(_ kind: Kind = .card) }` with `Kind { case card /* 0.82 */, nav /* 0.65 */, icon /* 0.55 + 0.96 scale */ }`.
- `struct OTMenuButton<Content: View>: View { init(_ title: String, systemImage: String? = nil, variant: OTButtonVariant = .secondary, size: OTControlSize = .large, fullWidth: Bool = true, @ViewBuilder content: () -> Content) }` — a `Menu` whose label is rendered through `OTButtonStyle`.

- [ ] **Step 1: Write failing tests** (helper `height(_ v: some View) -> CGFloat` = `UIHostingController(rootView: v.frame(width: 320)).sizeThatFits(in: CGSize(width: 320, height: .greatestFiniteMagnitude)).height`):
```swift
func testPrimaryAndSecondaryShareHeight() {
    XCTAssertEqual(height(Button("Continue") {}.buttonStyle(.ot(.primary))), 50)
    XCTAssertEqual(height(Button("Retake") {}.buttonStyle(.ot(.secondary))), 50)
}
func testMenuMatchesButtonHeight() {
    for size in [OTControlSize.large, .medium] {
        let b = height(Button("Camera") {}.buttonStyle(.ot(.secondary, size: size)))
        let m = height(OTMenuButton("Photos", systemImage: "photo", size: size) { Button("Front") {} })
        XCTAssertEqual(b, m, "\(size)")
    }
}
func testSmallButtonKeepsTapTarget() {
    XCTAssertEqual(height(Button("Edit") {}.buttonStyle(.ot(.secondary, size: .small, fullWidth: false))), 44)
}
func testButtonsGrowWithDynamicType() {
    let v = Button("Continue to slate") {}.buttonStyle(.ot(.primary))
        .environment(\.dynamicTypeSize, .accessibility3)
    XCTAssertGreaterThan(height(v), 50)
}
func testCameraSurfaceUsesLightForeground() {
    XCTAssertEqual(OTButtonStyle.foreground(for: .secondary, surface: .camera), OT.cameraLabel)
    XCTAssertEqual(OTButtonStyle.foreground(for: .secondary, surface: .standard), OT.labelPrimary)
}
```
(`static func foreground(for: OTButtonVariant, surface: OTSurface) -> Color` is internal-for-testing via `public`.)
- [ ] **Step 2:** Run — expected: compile failure (`OTButtonStyle` not found).
- [ ] **Step 3:** Implement; delete the replaced types from `Components.swift`; fix the compile errors the deletions surface (`GlassCapsuleButtonCompatibility()` → `.buttonStyle(.ot(.glass, size: .medium, fullWidth: false))`, `GlassProminentCapsuleButtonCompatibility()` → `.buttonStyle(.ot(.primary, size: .medium, fullWidth: false))`, `PressableCardStyle()` → `OTPressStyle(.card)`).
- [ ] **Step 4:** Run tests — expected PASS; build — expected success.
- [ ] **Step 5:** Commit `feat(ui): unify buttons into OTButtonStyle with sizes, variants and surfaces`.

### Task 3: Cards and bottom bar

**Files:**
- Create: `Styles/CardStyle.swift`, `Components/OTBottomBar.swift`
- Test: `OneTakeTests/DesignSystemTests.swift`

**Interfaces:**
- `enum OTCardKind { case elevated /* surfaceCard + shadow, radius card */, grouped /* fillField, radius l */, inset /* bgCanvas 55%, radius m */ }`, `View.otCard(_ kind: OTCardKind = .elevated, padding: CGFloat? = OTSpace.cardInset)` — replaces `.otCard(radius:)` (old signature kept as `@available(*, deprecated)` forwarding to `.elevated` until Task 16).
- `View.otBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar)` — `safeAreaInset(edge: .bottom)` with `VStack(spacing: OTSpace.s)`, horizontal `OTSpace.gutter`, top `OTSpace.m`, bottom `OTSpace.s`, background `OT.bgCanvas.ignoresSafeArea(edges: .bottom)` + top shadow `black 0.25, radius 12, y -4`.

- [ ] **Step 1: Write failing test:**
```swift
@MainActor func testBottomBarIsOpaque() {
    let v = Color.red.frame(width: 320, height: 400)
        .otBottomBar { Button("Go") {}.buttonStyle(.otPrimary) }
    let img = ImageRenderer(content: v).uiImage!
    // 4pt in from the left, 2pt above the bottom edge: must be canvas, not the red content behind it
    let px = img.rgba(at: CGPoint(x: 4, y: img.size.height - 2))
    XCTAssertEqual(px.a, 1, accuracy: 0.01)
    XCTAssertFalse(px.r > 0.9 && px.g < 0.1 && px.b < 0.1, "content bleeds through the bar")
}
```
(test-file helper: `extension UIImage { func rgba(at: CGPoint) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) }`, drawing the 1×1 pixel into a `CGContext`).
- [ ] **Step 2:** Run — expected compile failure (`otBottomBar` not found).
- [ ] **Step 3:** Implement `CardStyle` and `OTBottomBar`.
- [ ] **Step 4:** Run — expected PASS.
- [ ] **Step 5:** Commit `feat(ui): add card kinds and otBottomBar`.

### Task 4: Navigation, screen container and feedback components

**Files:**
- Create: `Components/OTScreen.swift`, `Components/OTNavHeader.swift`, `OTIconButton.swift`, `OTSheetHeader.swift`, `OTCallout.swift`, `OTStatusLine.swift`, `OTSectionLabel.swift`, `OTIconRow.swift`, `OTChip.swift`, `OTEmptyState.swift`, `OTProgressRing.swift`, `Gallery/OTGallery.swift`
- Modify: `OneTake/Views/Components.swift` — delete `SectionLabel`, `InlineStatus(Kind)`, `SheetHeader`, `IconRow`, `GlassBackButton`, `GlassIconButton`, `InContentNavHeader`, `ProgressRing`, `ScheduleRow` and add `typealias`es (`SectionLabel = OTSectionLabel`, `InContentNavHeader = OTNavHeader`, …) so call sites compile until their feature migrates.
- Test: `OneTakeTests/DesignSystemTests.swift`

**Interfaces:**
- `OTNavHeader<Trailing: View>(title: String = "", backLabel: String = "Back", onBack: (() -> Void)? = nil, @ViewBuilder trailing:)` — height 44; back is `OTIconButton("chevron.left")`; `"Cancel"`/`"Done"` labels render as `.tertiary` text; reads `otSurface` instead of `onDark`; trailing defaults to a 44×44 spacer so the title stays centred.
- `struct OTScreen<Content: View, Trailing: View>: View { init(title: String = "", backLabel: String = "Back", onBack: (() -> Void)? = nil, scrolls: Bool = true, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) }` — `ScrollView` (when `scrolls`) → `VStack(alignment: .leading, spacing: OTSpace.l)` → `OTNavHeader` + content, horizontal `OTSpace.gutter`, bottom padding `OTSpace.xxl`; applies `.otCanvas()`, `.toolbar(.hidden, for: .navigationBar)`, `.navigationBarBackButtonHidden(true)`. Callers attach `.otBottomBar` (Task 3) themselves. This is the only place in the app allowed to hide the navigation bar.
- `OTIconButton(_ systemName: String, accessibilityLabel: String, action: () -> Void)` — 44×44 circle, `.otIcon(.l)`, glass on iOS 26 / material fallback, `Haptics.tick()`.
- `OTSheetHeader(title:leading:trailing:onLeading:onTrailing:)` — same API as `SheetHeader`.
- `OTCallout(systemImage: String, title: String, message: String, tint: Color = OT.accent, @ViewBuilder actions: () -> some View = { EmptyView() })` — the icon/title/message card used by "Headshots are optional", "Saved for this audition", empty sides, etc. Renders inside `.otCard(.grouped)`.
- `OTStatusLine(_ kind: OTStatusKind, _ text: String, detail: String? = nil)` where `OTStatusKind { case progress, success, failure, offline }` — replaces `InlineStatus` and the ad-hoc "✓ Headshots saved · Next: slate" rows.
- `OTSectionLabel(_ text: String)`, `OTIconRow(symbol:title:detail:tint:)`, `OTChip(_ title: String, systemImage: String? = nil, isSelected: Bool = false, action:)`, `OTEmptyState(illustration: Image?, title:, message:, action: (title: String, run: () -> Void)?)`, `OTProgressRing(progress: Double, lineWidth: CGFloat = 4)`.
- `OTGallery` — `#Preview`s showing every component in Light, Dark and `.otSurface(.camera)`.

- [ ] **Step 1: Write failing tests:**
```swift
func testNavHeaderHeight() { XCTAssertEqual(height(OTNavHeader(title: "Audition Headshots")), 44) }
func testIconButtonIsMinimumTapTarget() {
    let size = UIHostingController(rootView: OTIconButton("xmark", accessibilityLabel: "Close") {})
        .sizeThatFits(in: CGSize(width: 200, height: 200))
    XCTAssertEqual(size, CGSize(width: 44, height: 44))
}
func testChipKeepsTapTarget() { XCTAssertGreaterThanOrEqual(height(OTChip("Front") {}), 44) }
func testScreenStartsWithHeader() {
    // header (44) + content (100) + stack spacing (16) + bottom padding (24), non-scrolling
    XCTAssertEqual(height(OTScreen(title: "T", scrolls: false) { Color.clear.frame(height: 100) }), 184)
}
```
- [ ] **Step 2:** Run — expected compile failure.
- [ ] **Step 3:** Implement components, `OTScreen`, gallery, and the typealiases.
- [ ] **Step 4:** Run tests + build — expected PASS / success. Open `OTGallery` preview and confirm every component in all three surfaces.
- [ ] **Step 5:** Commit `feat(ui): add OTScreen, navigation, callout, status and list components`.

---

## Phase 2 — App structure

### Task 5: Feature folder layout (moves only)

**Files:** `git mv` per the File Structure section: `Views/OneTakeApp.swift` → `App/` (then extract `RootTabView` and `RouteDestinations` into their own files in `App/`), `Models/*` → `Core/Models/` + `Core/Persistence/`, `ModelViews/{CameraController,MediaExporter,NoticeOCR,OCRLayoutReconstructor,OnDeviceIntelligence,TapeAnalyzer,ImageFraming,ZipArchive,CloudLink,Reminders,WidgetSync,AccountAuth,VoicePracticeReview}.swift` → `Core/Services/`, `ModelViews/AppStore.swift` → `Core/Store/`, each `Views/<X>.swift` → `Features/<X>/`.

- [ ] **Step 1:** Move files; no edits other than the `RootTabView`/`RouteDestinations` extraction (cut/paste, `private` → `internal` for `RouteDestinations`).
- [ ] **Step 2:** `xcodegen generate`; build — expected success. `git diff --stat -M` shows renames only plus the two extracted files.
- [ ] **Step 3:** Commit `refactor: organise app into App/Core/Features/Shared`.

### Task 6: Dismantle `Components.swift`

**Files:**
- Create: `OneTake/Shared/UI/HeadshotImage.swift`, `ProfileButton.swift`, `PhotoSourceMenu.swift`
- Move domain components to their feature folder (one file each): `SilentReactionCue`, `RecallWordHintText`, `RecallGapHintText`, `RecallWordsLayout` → `Features/Prepare/`; `ReadinessDial`, `ReadinessDashes`, `PackageStepsBar` → `Features/AuditionDetail/`; `SidesInputTile`, `SidesChip`, `AuditionMaterialKindPicker`, `MilestoneDatesListCard`, `ProjectDetailsCard`, `FieldEvidenceSection`, `RoleBreakdownCard` → `Features/AddAudition/Components/`; `Date.otDue/otDayMonth` → `Core/Models/Date+Formatting.swift`.
- Delete: `OneTake/Views/Components.swift` (the generic parts already live in `OneTakeUI` or as typealiases in a new `OneTake/Shared/UI/LegacyAliases.swift`).

**Interfaces:**
- `PhotoSourceMenu(auditionID: Audition.ID?, size: OTControlSize = .medium, onPick: (HeadshotAngle) -> Void)` with `enum HeadshotAngle: String, CaseIterable { case front, left, right; var title: String }` — the Front/Left/Right picker menu currently duplicated in `HeadshotsView` (×2) and any other picker site; renders via `OTMenuButton` with `checkmark.circle.fill`/`circle` per existing headshot.

- [ ] **Step 1:** Add test `testHeadshotAngleTitles` asserting `HeadshotAngle.allCases.map(\.title) == ["Front", "Left profile", "Right profile"]`; run — expected compile failure.
- [ ] **Step 2:** Do the moves/extraction; implement `PhotoSourceMenu`; `xcodegen generate`.
- [ ] **Step 3:** Tests + build — expected PASS / success.
- [ ] **Step 4:** Commit `refactor: split Components.swift into OneTakeUI, Shared/UI and feature folders`.

### Task 7: Split `AppStore` and `UIKitBridges`

**Files:**
- Create: `Core/Store/AppStore+Navigation.swift` (`push`, `pop`, `popTo`, `popToRoot`, `currentPath`, `continueAudition`), `AppStore+Auditions.swift`, `AppStore+Practice.swift`, `AppStore+Headshots.swift` (`syncHeadshotPieces`, `headshotVersion` helpers); `Core/Bridges/<Bridge>.swift` one per type now in `UIKitBridges.swift` (`ShareSheet`, `VideoTrimmer`, `ReaderAudioTrimmer`, `DocumentScannerView`, `KeepScreenAwake`, the `@Observable` speech/audio classes each in their own file, `SwipeBack` (the `UINavigationController` extension), `TabBarVisibility` (`TabBarHider`/`TabBarShower`), `ScriptTextEditor`).
- Delete: `ModelViews/UIKitBridges.swift`.

- [ ] **Step 1:** Move code verbatim into extensions/files (stored properties stay in `AppStore.swift`; only methods move). No behaviour change.
- [ ] **Step 2:** `xcodegen generate`; build; run full `ModelTests` — expected same pass count as before (27).
- [ ] **Step 3:** Commit `refactor: split AppStore by domain and UIKitBridges per bridge`.

---

## Phase 3 — Screen migrations

Every migration task below uses this **definition of done** (not repeated per task):

1. Each screen's root is `OTScreen` (or `.otSurface(.camera)` + `OTNavHeader` for full-bleed camera screens); bottom actions use `.otBottomBar`.
2. All buttons/menus use `.ot(…)`/`OTMenuButton`; side-by-side controls share one `OTControlSize`.
3. Hand-built cards → `.otCard(kind)` / `OTCallout`; status rows → `OTStatusLine`; `onDark:` removed.
4. Literals mapped with the Global Constraints rules; remaining content geometry tagged `// ot-lint:allow`.
5. Files over 800 lines are split one-primary-view-per-file inside the feature folder.
6. `scripts/lint-design-system.sh --strict --path OneTake/Features/<Feature>` exits 0.
7. Build + `ModelTests` + `DesignSystemTests` green; screenshots for the feature's baseline screens retaken in Light + Dark, compared side-by-side with `docs/design-baseline/` — differences must be only the intended normalisation (sizes/radii/spacing), no missing content.
8. Lower the matching counts in `scripts/design-lint-baseline.txt`; commit `refactor(<feature>): migrate to OneTakeUI`.

### Task 8: Headshots + Profile
**Files:** `Features/Profile/ProfileViews.swift` (2,794) → `Features/Headshots/{HeadshotsView, HeadshotSlotTile, HeadshotAdjustSheet, HeadshotViewerSheet, HeadshotFlow}.swift`, `Features/Profile/{ProfileView, EditSlateView, PrivacyView, NotificationSettingsView}.swift`.
Specific: `HeadshotsView` bottom bar = `OTStatusLine(.success, "Headshots saved on this iPhone", detail: "Next: slate")` + one `.otPrimary`; `photoActionsBar` = `[Camera .ot(.secondary, size: .medium)] [PhotoSourceMenu size: .medium] [Auto-frame OTMenuButton size: .medium]`; top card = `OTCallout`.

### Task 9: Auditions list + Audition detail
**Files:** `Features/Auditions/{AuditionsView, AuditionCard, SearchView}.swift`; `Features/AuditionDetail/AuditionDetailView.swift` (2,174) → `{AuditionDetailView, UpNextCard, PackageSheet, CallbackSheet, EditAuditionSheet, RevisedSidesSheet, SubmissionInstructionsCard}.swift`.

### Task 10: Add audition
**Files:** `Features/AddAudition/AddAuditionFlow.swift` (4,688) → `{AddAuditionFlow, NoticeReviewView, MissingDetailsView, OCRReviewSheet, AddDraftSidesSheet, AutofillKeyboardBar}.swift` + `Components/`. Keyboard + `.otBottomBar` must coexist (bar rides above the keyboard, fields stay visible).

### Task 11: Prepare + line learning
**Files:** `Features/Prepare/PrepareViews.swift` (2,237) → `{PrepareView, RunLinesView, ReaderView, RecordReaderView, SceneAudioFlowView, ShootSetupView}.swift`; `LineLearningViews.swift` → `{LineDrillView, AudioWalkView}.swift`.

### Task 12: Shoot + tape preview + takes (camera surface)
**Files:** `Features/Shoot/ShootViews.swift` (2,062) → `{ShootFlow, CameraOverlay, SlateStage, TeleprompterView, HeadshotCaptureView}.swift`; `TapePreviewView.swift`; `Features/Takes/{TakesView, TapeCheckView}.swift`. Container gets `.otSurface(.camera)`; screenshots **must** include Light Mode to prove controls stay white-on-glass.

### Task 13: Package
**Files:** `Features/Package/PackageViews.swift` (1,408) → `{PackageView, DestinationSheet, PackageFormatSheet, FileNameTemplateSheet, SubmissionCheckSummary}.swift`. `bottomSendBar` becomes `.otBottomBar`.

### Task 14: Practice + onboarding
**Files:** `Features/Practice/PracticeViews.swift` (1,641) → `{PracticeView, PracticeSetupView, PracticeOptionsView, StandalonePracticeView, PracticeTakeView}.swift`; `Features/Onboarding/OnboardingFlow.swift`.

### Task 15: Widgets
**Files:** `OneTakeWidgets/NextAuditionWidget.swift`, `AuditionLiveActivity.swift` — tokens only (`OTSpace`, `OTRadius`, `Font.ot*`, `.otIcon`); `--path OneTakeWidgets` strict lint passes; widget previews render in small/medium/lock-screen families.

---

## Phase 4 — Lock it in

### Task 16: Enforce, clean up, document

**Files:**
- Modify: `project.yml` (pre-build script: drop `|| true`, add `--strict`), `scripts/design-lint-baseline.txt` (all zeros)
- Delete: `OneTake/Shared/UI/LegacyAliases.swift`, deprecated `otCard(radius:)`
- Create: `docs/DESIGN_SYSTEM.md` — token tables (the scales above), the button matrix (variant × size with when-to-use), component catalogue with one snippet each, the 8-point definition of done, how to add a new component (pure → `OneTakeUI`; needs app data → `Shared/UI`; one feature only → `Features/<X>`), and the `ot-lint:allow` policy.

- [ ] **Step 1:** Remove aliases/deprecations; fix any remaining call sites by migrating them to the `OT*` names.
- [ ] **Step 2:** `scripts/lint-design-system.sh --strict` — expected exit 0. Temporarily add `cornerRadius: 9` to a feature file and build — expected `** BUILD FAILED **` naming `radius`; revert.
- [ ] **Step 3:** Full build, full test suite (only the 8 pre-existing `NoticeParserTests` failures allowed), install on the device and walk the baseline screen list.
- [ ] **Step 4:** Write `docs/DESIGN_SYSTEM.md`; commit `chore: enforce design system lint and document OneTakeUI`.

---

## Open decisions (defaults chosen; change before execution if you disagree)

1. **Local Swift package vs. folder only** — default: package, because it makes "UI can't reach into app state" a compiler rule and removes the widget's file-path hack.
2. **Visual normalisation** — default: snap to the scales above (e.g. 10/14/18 pt radii collapse to 12/14/16/20). This deliberately changes some pixels; that's the consistency the user asked for.
3. **Snapshot testing** — default: no third-party dependency; height/opacity unit tests + manual baseline screenshots. Adding `swift-snapshot-testing` would automate step 7 of the definition of done.
