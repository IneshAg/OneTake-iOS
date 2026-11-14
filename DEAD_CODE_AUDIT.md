# OneTake Codebase Dead Code & Unused Code Audit Report

**Date:** November 14, 2026  
**Audited Target:** OneTake iOS App, App Extensions (`OneTakeShare`, `OneTakeWidgets`), and `OneTakeUI` Package  
**Build Status:** Clean build verified (`BuildProject` passed in 1.8s)  
**Test Suite:** 259 total tests (255 passed, 3 pre-existing layout/parser assertions, 1 skipped)

---

## Executive Summary

A full static and dynamic codebase audit of OneTake was conducted to uncover obsolete features, abandoned prototypes, dead methods, unused SwiftUI views, redundant state variables, and orphaned asset files.

This document serves as an exhaustive reference of all findings, including exact file locations, line ranges, symbols, rationale, and recommended cleanup actions.

---

## 1. Unused Store & Model Methods (`OneTake/Core/Store` & `Core/Models`)

| Symbol | Location | Category | Details & Recommendation |
|---|---|---|---|
| `loadSampleAudition()` | [`OneTake/Core/Store/AppStore.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore.swift#L133-L180) | Obsolete Prototype | Pre-dates the demo mode catalog (`DemoModeCatalog.swift` & `AppStore+Demo.swift`). Seeds a hardcoded "The Quiet Horizon" audition with "Maya" role. **Safe to remove.** |
| `updateRole(for:to:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L248-L253) | Dead Store API | Replaced in UI by direct mutation of `audition.role` followed by `store.reclassifyRole(for:)`. Never called anywhere. **Safe to remove.** |
| `togglePieceOptional(for:pieceID:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L367-L380) | Dead Store API | Unused piece optionality toggling logic. Never wired up in any sheet or view. **Safe to remove.** |
| `markExported(_:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L397-L400) | Dead Store API | Sets audition status to `.exported`. Audition status transitions are handled during package preparation; never invoked. **Safe to remove.** |
| `markSubmitted(_:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L402-L404) | Redundant Alias | Wrapper around `markSent(id)`. Never called. **Safe to remove.** |
| `unmarkSubmitted(_:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L417-L419) | Redundant Alias | Wrapper around `unmarkSent(id)`. Never called. **Safe to remove.** |
| `setSlateVideo(_:for:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L430-L434) | Dead Store API | Slate captures use `keepOriginalSlate(_:for:)` or `replaceSlateVideo(for:with:)` to handle backup video files and invalidate exports. `setSlateVideo` does neither and is unused. **Safe to remove.** |
| `restoreOriginalSlate(for:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L454-L460) | Dead Store API | Intended to revert a trimmed slate to its original un-trimmed capture, but is never invoked by any view. **Safe to remove or wire to UI.** |
| `restoreOriginalFullLengthVideo(for:)` | [`OneTake/Core/Store/AppStore+Auditions.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Auditions.swift#L495-L503) | Dead Store API | Intended to revert a trimmed full-length tape to its original un-trimmed capture; never called in UI. **Safe to remove or wire to UI.** |
| `bumpHeadshotVersion()` | [`OneTake/Core/Store/AppStore+Headshots.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Store/AppStore+Headshots.swift#L13-L15) | Dead Store API | Increments `headshotVersion += 1`. All 15+ caller sites across the app modify `store.headshotVersion += 1` directly. **Safe to remove (or adopt uniformly).** |

---

## 2. Unused Parsing & Machine Learning Functions (`Core/Services` & `Core/Models`)

| Symbol | Location | Category | Details & Recommendation |
|---|---|---|---|
| `isLikelyDialogueAfterAction(_:)` | [`OneTake/Core/Models/ScriptParser.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Models/ScriptParser.swift#L483-L500) | Dead Parsing Helper | Heuristic keyword and punctuation checker intended to distinguish dialogue from stage directions. Never called anywhere. **Safe to remove.** |
| `isSameRole(_:_:)` | [`OneTake/Core/Models/ScriptParser.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Models/ScriptParser.swift#L728-L730) | Dead Parsing Helper | Static helper wrapping private `isSameCharacter`. Never called anywhere. **Safe to remove.** |
| `ScriptArchetype` & `detectArchetype(in:)` | [`OneTake/Core/Models/ScriptParser.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Models/ScriptParser.swift#L9-L36) | Unintegrated Prototype | Enumerates script types (`multiRolePacket`, `screenplay`, `commercial`, `stagePlay`, `standardDialogue`). Only referenced in unit tests for itself (`ScriptParserTests.swift`); never integrated into the actual parsing pipeline. **Safe to remove if not planned.** |
| `typealias ElementClass` | [`OneTake/Core/Models/CoreMLScriptParserRunner.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Models/CoreMLScriptParserRunner.swift#L16) | Dead Typealias | `public typealias ElementClass = ScriptElementClass`. Never used across the project. **Safe to remove.** |
| `detectRole(in:)` | [`OneTake/Core/Services/NoticeParser+Detectors.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Services/NoticeParser+Detectors.swift#L353-L355) | Dead Parsing Helper | Single line returning `detectCandidateRoles(in:).first`. The parser directly uses `detectCandidateRoles` everywhere. Never called. **Safe to remove.** |
| `detectSidesLink(in:)` | [`OneTake/Core/Services/NoticeParser+Detectors.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Services/NoticeParser+Detectors.swift#L773-L775) | Dead Parsing Helper | Single line returning `detectClassifiedLinks(in:).sidesLink`. The parser directly calls `detectClassifiedLinks`. Never called. **Safe to remove.** |
| `formatAndSegmentSides(text:character:)` | [`OneTake/Core/Services/OnDeviceIntelligence.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Core/Services/OnDeviceIntelligence.swift#L567-L594) | Dead Intelligence API | LLM prompt generator and fallback to segment lines into thought units. Never called by the teleprompter (which uses `ScriptParser.divideIntoThoughtUnits` directly). **Safe to remove.** |
| `replayReaderBeforeCurrent()` | [`OneTake/Core/Services/Shoot/ShootFlow.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Shoot/ShootFlow.swift#L418-L423) | Dead Feature Method | Replays the reader track for the prior reader line. Not bound to any UI button or shortcut. **Safe to remove or wire to button.** |

---

## 3. Unused UI Components & View Modifiers

| Symbol | Location | Category | Details & Recommendation |
|---|---|---|---|
| `OTSheetHeader` | [`Packages/OneTakeUI/Sources/OneTakeUI/Components/OTSheetHeader.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/Packages/OneTakeUI/Sources/OneTakeUI/Components/OTSheetHeader.swift#L3-L53) | Dead Component File | Entire custom sheet title bar component with leading/trailing action buttons. Never used in any sheet or view across the app. **Safe to delete file.** |
| `OTMenuIconButton` | [`Packages/OneTakeUI/Sources/OneTakeUI/Components/OTMenuIconButton.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/Packages/OneTakeUI/Sources/OneTakeUI/Components/OTMenuIconButton.swift#L4-L38) | Dead Component File | Canonical circular glass menu button for header actions. Never used across the codebase. **Safe to delete file.** |
| `OTGalleryView` | [`Packages/OneTakeUI/Sources/OneTakeUI/Gallery/OTGallery.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/Packages/OneTakeUI/Sources/OneTakeUI/Gallery/OTGallery.swift#L3-L96) | Dead Showcase View | Component gallery and visual preview showcase. Only used within its own `#Preview`. Not exposed anywhere in the main app. **Safe to delete or keep solely for Xcode canvas.** |
| `DotLabelStyle` | [`OneTake/Features/Prepare/PrepareView.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Prepare/PrepareView.swift#L224-L232) | Dead View Style | Custom `LabelStyle` struct declared at the bottom of `PrepareView.swift`. Never instantiated or applied anywhere. **Safe to remove.** |
| `showSystemTabBar(isVisible:)` | [`OneTake/App/RouteDestinations.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/App/RouteDestinations.swift#L60-L65) | Dead View Modifier | `View` extension method controlling tab bar visibility. Navigation uses `TabBarShower` directly. Never called. **Safe to remove.** |
| `applySearch(enabled:text:)` | [`OneTake/App/RouteDestinations.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/App/RouteDestinations.swift#L68-L75) | Dead View Modifier | `View` extension method wrapping `.searchable`. Never called anywhere. **Safe to remove.** |

---

## 4. Dead State Variables, Properties & Typealiases

| Symbol | Location | Category | Details & Recommendation |
|---|---|---|---|
| `isSearchAvailable` | [`OneTake/App/RootTabView.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/App/RootTabView.swift#L8-L10) | Dead Computed Property | Computed property checking if `auditions` or `practice` is non-empty. Never accessed in `RootTabView` body. **Safe to remove.** |
| `isAutoFraming` | [`OneTake/Features/Headshots/HeadshotAdjustSheet.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Headshots/HeadshotAdjustSheet.swift#L24) | Unused `@State` | `@State private var isAutoFraming = false` is defined but never read or modified. **Safe to remove.** |
| `typealias TeleprompterView` | [`OneTake/Features/Shoot/TeleprompterView.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Shoot/TeleprompterView.swift#L6) | Dead Typealias | `typealias TeleprompterView = SidesPrompterView`. Never used outside or inside the file. **Safe to remove.** |
| `currentLine` | [`OneTake/Features/Shoot/TeleprompterView.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Shoot/TeleprompterView.swift#L24-L26) | Dead Computed Property | `private var currentLine: ScriptLine?` in `SidesPrompterView` is never read. **Safe to remove.** |
| `prevLine` | [`OneTake/Features/Shoot/TeleprompterView.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Shoot/TeleprompterView.swift#L28-L30) | Dead Computed Property | `private var prevLine: ScriptLine?` in `SidesPrompterView` is never read. **Safe to remove.** |
| `typealias ExportStage` | [`OneTake/Features/Package/PackageView.swift`](file:///Users/user1/Downloads/OneTake-refactor/OneTake/OneTake/Features/Package/PackageView.swift#L7) | Dead Typealias | `typealias ExportStage = PackageExportStage`. Never referenced. **Safe to remove.** |

---

## 5. Duplicate & Orphan Resources

| Resource | Path | Issue & Impact |
|---|---|---|
| `onetake-empty-auditions.svg` | `OneTake/Shared/onetake-empty-auditions.svg` | Orphaned asset. `AuditionsView.swift:349` loads `Image("onetake-empty-auditions-illustration")`. `onetake-empty-auditions.svg` is unreferenced. **Safe to delete.** |
| Duplicate Test PDFs & Images | `OneTake/SampleCastingFiles/` vs `OneTakeTests/Resources/` | Identical casting sides and flyers are duplicated across the main app bundle and the test target bundle (`Grease_Audition_Sides_V2.pdf`, `Pilgrimage_Casting_Sides.pdf`, `Audition_Flyer_Casting_Call.jpg` / `flyer_test.jpg`). Bundle size can be reduced by unifying test fixtures. |

---

## 6. Action Plan for Clean-Up

1. **Phase 1 (Zero-Risk Cleanup):**
   - Remove unused computed properties: `isSearchAvailable` in `RootTabView`, `currentLine` and `prevLine` in `TeleprompterView`.
   - Remove unused `@State private var isAutoFraming` in `HeadshotAdjustSheet`.
   - Remove dead typealiases: `TeleprompterView`, `ExportStage`, `ElementClass`.
   - Remove unused struct `DotLabelStyle` in `PrepareView`.
   - Remove dead view modifiers `showSystemTabBar` and `applySearch` in `RouteDestinations`.
   - Delete orphan file `OneTake/Shared/onetake-empty-auditions.svg`.

2. **Phase 2 (Store & Service Cleanup):**
   - Remove dead Store methods: `loadSampleAudition`, `updateRole`, `togglePieceOptional`, `markExported`, `markSubmitted`, `unmarkSubmitted`, `setSlateVideo`, `bumpHeadshotVersion`.
   - Remove dead helper methods in `ScriptParser` (`isLikelyDialogueAfterAction`, `isSameRole`) and `NoticeParser+Detectors` (`detectRole`, `detectSidesLink`).
   - Remove dead LLM method `formatAndSegmentSides` in `OnDeviceIntelligence`.

3. **Phase 3 (Component & Feature Decisions):**
   - Delete unused OneTakeUI components (`OTSheetHeader.swift`, `OTMenuIconButton.swift`) or keep in component library if intended for public SDK release.
   - Decide whether to preserve `restoreOriginalSlate` / `restoreOriginalFullLengthVideo` / `replayReaderBeforeCurrent` by wiring them to the UI, or remove them.
