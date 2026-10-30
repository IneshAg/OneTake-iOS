# OneTake UI & Navigation Changes Log

This document records the design choices, UX rationale, and architectural implementations made to the navigation and header components in **OneTake (iOS)**.

---

## 1. Profile Button Repositioning & Styling

### Problem & Exploration
The profile button needed to be clearly accessible across main views (`AuditionsView` and `PracticeView`) while maintaining a clean aesthetic.
- **Left vs. Right Header Placement:**
  - When placed on the **top-left**, the `"Auditions"` large title collided with the button, causing the text to wrap awkwardly across lines (`"Audition\ns"`).
  - Placing it on the **top-right** (adjacent to the `+` Add button) solved the title clipping issue, provided consistent layout across screens, and kept all primary navigation actions aligned.
- **Visual Contrast & Stroke:**
  - A plain icon lacked sufficient visual distinction on dark mode cards.
  - Added a high-contrast circular stroke:
    - Dynamic light/dark stroke: `Color(UIColor(light: 0x1E1A22, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.85))`
    - `OT.accentSoft` circular fill.
    - 44×44 pt touch target complying with Apple Human Interface Guidelines.
- **Navigation Presentation:**
  - Presented modally via `.sheet(isPresented: $store.showProfile)` with drag indicator and explicit "Done" button, wrapping `ProfileView()` in a `NavigationStack` with full route handling (`.withRoutes()`).

---

## 2. Bottom Navigation Architecture (System Default Sizing)

### Design Goal
Use Apple's native iOS 18 floating navigation with the system's default tab label sizing.

### Implementation
- The native tab bar contains `Auditions`, `Practice`, and the system search tab when auditions exist.
- Tab labels use plain titles without typographic padding or width adjustments.
- Search remains conditional on there being at least one audition.

---

## 3. Empty State Search Suppression

### Rationale
On first launch or whenever the audition library has no entries (`store.auditions.isEmpty`), there are no scenes, sides, lines, or takes to search. Displaying a prominent search trigger in empty state adds cognitive clutter with zero actionable utility.

### Implementation
- **Conditional Search Tab:**
  - `Tab(value: AppTab.search, role: .search)` is only included in `TabView` when `!store.auditions.isEmpty`.
  - `.searchable(...)` and `.tabViewSearchActivation(.searchTabSelection)` are conditionally attached only when searchable content exists.
  - If all auditions are deleted while on the search tab, `store.tab` automatically resets to `.auditions`.
- **Dynamic Centering in Empty State:**
  - In empty state, the standalone search circle is hidden.
  - The widened `[Auditions | Practice]` floating pill automatically centers horizontally at the bottom of the screen, creating a clean, balanced anchor.
  - As soon as the user adds their first audition, the circular Search button seamlessly re-enters the layout.

---

## 4. Search Scope & Results Clean-up (Profile Removed)

### Rationale
Profile, account, headshots, and app settings are directly accessible from the persistent high-contrast `ProfileButton` in the top-right header. Including "Profile & Settings" inside global search diluted the actor-focused nature of the tool (actors search for project titles, character roles, lines in sides, and practice pieces).

### Implementation
- **Removed Profile Scope:**
  - Removed `.profile` case from `SearchScope` in `SearchView` (`OneTake/Views/AuditionsView.swift`).
  - Scopes are now strictly creative: `All`, `Auditions`, `Practice`.
- **Removed Profile & Settings Search Section:**
  - Removed hardcoded settings list (`Slate & bio`, `Headshots`, `Notifications`, `Privacy & data`) from search results.
- **Updated Search Prompt:**
  - Changed search placeholder in `OneTakeApp.swift` from `"Search auditions, practice, profile..."` to `"Search auditions, sides, practice..."`.

---

## 5. Profile & Privacy/Data Enhancements (Sign In Relocation & Account Deletion)

### Rationale
- **Sign In Relocation**: In `ProfileView`, the "Sign in" button was previously embedded inside the general "More" settings card alongside Appearance and Notifications. Moving it down into its own dedicated "Account" card creates a clean, standard settings hierarchy separating device-level app preferences from user authentication.
- **Delete Account Option in Privacy & Data**: Apple App Store Review Guideline 5.1.1(v) requires apps that offer account sign-in to provide an explicit account deletion mechanism within the app. Adding "Delete account" in `PrivacyView` gives users full data sovereignty to revoke authentication, disconnect provider sessions (Apple / Google OAuth), and clear credential caches.

### Implementation
- **Profile Screen Hierarchy**:
  - `ProfileView` now places Appearance, Notifications, and Privacy & data inside "More".
  - Created a separate `SectionLabel(text: "Account")` card below "More" holding the "Sign in" action (when signed out) or user identity card with "Sign out" (when signed in).
- **Privacy & Data Screen**:
  - Added an "Account" section in `PrivacyView` showing connection status (`Signed in with Apple/Google` or `Guest (no account)`).
  - Added a destructive `Delete account` button with confirmation alert.
  - Implemented `store.deleteAccount()` in `AppStore.swift` and `AccountAuth.deleteAccount(_:)` in `AccountAuth.swift` to disconnect provider tokens and clear local state.

---

## 6. Profile Modal Header Spacing Adjustment

### Problem & Feedback
When opening the Profile modal (`ProfileView`), the custom header (`"Profile"` large title and `"Done"` capsule button) was rendered at the very top edge of the sheet's `ScrollView`. Because `.toolbar(.hidden, for: .navigationBar)` is active, there was no native navigation bar inset, causing the header elements to hug the top safe area boundary directly beneath the `.presentationDragIndicator(.visible)` grab handle.

### Implementation
- Added explicit `.padding(.top, 30)` to the header `HStack` in `ProfileView` (`OneTake/Views/ProfileViews.swift`).
- This offsets the title and Done button by ~30 pt, providing clean visual separation from the sheet drag indicator and matching native modal sheet ergonomics.

---

## File Reference

- [OneTake/Views/OneTakeApp.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/OneTakeApp.swift): `RootTabView`, dynamic search tab inclusion, conditional search activation.
- [OneTake/Views/Components.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/Components.swift): `ProfileButton` definition with 44×44 pt touch frame and white stroke border.
- [OneTake/Views/AuditionsView.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AuditionsView.swift): Top-right header actions with `ProfileButton` and `+` button.
- [OneTake/Views/PracticeViews.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/PracticeViews.swift): Consistent top-right header `ProfileButton` integration.
- [OneTake/Views/ProfileViews.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/ProfileViews.swift): Profile modal layout, header top padding (30pt), account section separation, and privacy/data account deletion.
- [OneTake/Views/AddAuditionFlow.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift): Refactored capture sheet, full-screen `MissingDetailsView`, `NoticeReviewView`, and `AddDraftSidesSheet`.
- [OneTake/Views/AuditionDetailView.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AuditionDetailView.swift): Added "Add or scan sides" action button in `upNext`, persistent `sidesCard`, dynamic `...` menu item, and enhanced `RevisedSidesSheet`.
- [OneTake/ModelViews/AppStore.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/AppStore.swift): Added `.missingDetails` and `.noticeReview` to `Route`, added `auditionDraft`, `pendingRouteAfterAdd`, `startAuditionDraft(_:)`, and updated `replaceSides(of:with:sourceText:)`.

---

## 7. Full-Screen "Missing Details" & Uninterrupted Back Navigation

### Problem & Exploration
- **Sheet Trap**: Tapping `+` opened `AddAuditionFlow` as a modal sheet (`.sheet(isPresented: $store.showAddAudition)`). When moving to "A few details missing" or "Here's what they want", the sheet simply expanded to `.large` detent, leaving the forms constrained inside a modal card with drag indicators and modal presentation behaviors rather than standard screen navigation.
- **Back Navigation Loop ("Reading the notice…")**:
  - The capture sheet previously pushed an intermediate `NoticeReadingView` ("Reading the notice…") to its internal navigation path.
  - When parsing completed and pushed `MissingDetailsView`, pressing `< Back` popped directly back to `NoticeReadingView`.
  - Because `NoticeReadingView` ran an automatic parsing task on appear, it immediately called `onDone` and re-pushed `MissingDetailsView`, trapping the user in a loop and preventing them from returning to the previous screen or choosing another notice.

### Implementation
1. **Pushed Screen Architecture (`Route.missingDetails` & `Route.noticeReview`)**:
   - Extended `Route` in [`AppStore.swift`](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/AppStore.swift) with `.missingDetails` and `.noticeReview`.
   - Added `auditionDraft`, `pendingRouteAfterAdd`, and `startAuditionDraft(_:)` to `AppStore`.
   - Connected destinations in `RouteDestinations` in [`OneTakeApp.swift`](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/OneTakeApp.swift).
2. **Compact Capture Sheet**:
   - Refactored `AddAuditionFlow` in [`AddAuditionFlow.swift`](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift) so the modal sheet is dedicated strictly to capture (Paste button, Photo, Scan, File, and "Type it") at a clean `.height(420)` detent.
   - When a source is chosen or pasted, `store.startAuditionDraft(draft)` dismisses the sheet and sets `pendingRouteAfterAdd`.
   - In [`OneTakeApp.swift`](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/OneTakeApp.swift), the sheet's `onDismiss` handler immediately pushes the target route onto `store.auditionsPath`.
3. **Clean Back Navigation (No Intermediate Loading Screen)**:
   - `MissingDetailsView` and `NoticeReviewView` are now full-screen views on the `NavigationStack` with `InContentNavHeader`.
   - In `MissingDetailsView`, tapping `< Auditions` calls `store.pop()`, popping cleanly back to the Auditions root. It never visits or triggers "Reading the notice…".
   - Added a "Choose a different notice" action button that pops to root and re-opens the capture sheet.
   - In `NoticeReviewView`, tapping `< Back` pops back to `MissingDetailsView` (or `< Auditions` if no fields were missing).
   - Any AI guidance generation runs asynchronously in the background via `.task` on `NoticeReviewView` without blocking navigation.

---

## 8. Integrated Sides Management (Creation Flow, Audition Detail, and Revised Sides)

### Problem & UX Gap
1. **Creation Flow Disconnect**: When an actor created an audition from casting notice text, email, or typing it in, `NoticeParser.Draft.sourceText` often contained only audition dates, roles, and project info, but no script sides. There was no way in `MissingDetailsView` or `NoticeReviewView` to inspect sides status, paste sides, scan pages, or import script files before creating the audition.
2. **Missing Sides Action on Created Auditions**: On created auditions where no sides were captured yet (`a.scenes.isEmpty`), `upNext` displayed:
   > *"No sides captured yet — Nothing was readable in what you added this audition from — rescan or retype the sides to prepare and shoot this scene."*
   However, there was **no button** or call to action on the screen. The actor was completely stranded with no direct way to add or scan sides, and had to discover an obscure "Revised sides" item hidden inside the `...` menu.
3. **Rigid "Revised sides" sheet**: The sheet was titled "Revised sides" with button "Replace" even when 0 sides had ever been added. It lacked a quick `PasteButton` for 1-tap clipboard import and didn't display the detected scene/line breakdown for the actor's role.

### Implementation
1. **Creation Flow Sides Actions (`AddDraftSidesSheet`)**:
   - Built `AddDraftSidesSheet` in [`AddAuditionFlow.swift`](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift) supporting:
     - 1-tap `PasteButton(payloadType: String.self)` to paste sides directly from clipboard.
     - Multi-line text field with manual typing/editing.
     - Document camera scanning via `DocumentScannerView` (`VisionKit`).
     - File importing via `.fileImporter` (PDF, plain text, RTF).
     - Live parser feedback showing detected scenes, role lines, and total character dialogue.
   - Embedded sides status cards in both `MissingDetailsView` and `NoticeReviewView` with "Add sides" (when empty) and "Replace / rescan" (when scenes exist).
2. **Direct Action on Audition Detail (`AuditionDetailView.swift`)**:
   - In `upNext`: When `next?.kind == .scene` and no sides are captured yet, added a primary call-to-action button:
     `Button { showSides = true } label: { Label("Add or scan sides", systemImage: "doc.badge.plus") }`
   - Added a persistent `sidesCard(a)` on `AuditionDetailView`:
     - Empty state: Displays "No sides attached yet" with warning icon and "Add or scan sides" action button.
     - Populated state: Displays "Sides · X scene(s) · Y lines" with "Replace / rescan" action button.
   - Updated the `...` options menu: Dynamically displays `"Add sides"` (with `doc.badge.plus`) when empty, or `"Revised sides"` (with `doc.badge.arrow.up`) when sides exist.
3. **Enhanced Sides Sheet (`RevisedSidesSheet`)**:
   - Dynamically titles the sheet as `"Add sides"` (if `scenes.isEmpty`) or `"Revised sides"`.
   - Action button reflects `"Add"` vs `"Replace"`.
   - Added 1-tap `PasteButton`, file import, camera scan, and live scene/line inspection.
   - Updated `store.replaceSides(...)` in [`AppStore.swift`](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/AppStore.swift) so first-time sides addition does not tag pieces as "Revised sides".

---

## 9. Complete Navigation Bar Suppression Across Audition Flow Screens

### Problem & Visual Bug
When `MissingDetailsView` and `NoticeReviewView` were migrated from a modal presentation sheet to full pushed destinations on `NavigationStack(path: $store.auditionsPath)`, the system navigation bar remained visible above the view's content. Because OneTake employs custom, high-touch in-content navigation headers (`InContentNavHeader`) with bespoke typography and back buttons, this resulted in an awkward stacked header containing both the default iOS navigation bar and the app's in-content header.

### Implementation
Explicitly attached navigation bar and tab bar suppression modifiers across all screens and sheets in the audition flow:
- [AddAuditionFlow.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift):
  - `AddAuditionFlow` (capture screen): Added `.toolbar(.hidden, for: .navigationBar)` and `.navigationBarBackButtonHidden(true)`.
  - `AddDraftSidesSheet`: Added `.toolbar(.hidden, for: .navigationBar)` and `.navigationBarBackButtonHidden(true)`.
  - `MissingDetailsView`: Added `.toolbar(.hidden, for: .tabBar)`, `.toolbar(.hidden, for: .navigationBar)`, and `.navigationBarBackButtonHidden(true)`.
  - `NoticeReviewView`: Added `.toolbar(.hidden, for: .tabBar)`, `.toolbar(.hidden, for: .navigationBar)`, and `.navigationBarBackButtonHidden(true)`.
  - `NoticeErrorView`: Added `.toolbar(.hidden, for: .navigationBar)` and `.navigationBarBackButtonHidden(true)`.
- [AuditionDetailView.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AuditionDetailView.swift):
  - `RevisedSidesSheet`: Added `.toolbar(.hidden, for: .navigationBar)` and `.navigationBarBackButtonHidden(true)`.
  - `EditAuditionSheet`: Added `.toolbar(.hidden, for: .navigationBar)` and `.navigationBarBackButtonHidden(true)`.
  - `CallbackSheet`: Added `.toolbar(.hidden, for: .navigationBar)` and `.navigationBarBackButtonHidden(true)`.

---

## 10. Script Parsing Integrity & Reader Audio Tracking Fixes

### Problems Identified
1. **Contaminated Dialogue with Scene Descriptions & Stage Directions**:
   - In `ScriptParser.swift`, action lines and stage descriptions (e.g. *"Maya sits at the counter..."*, *"Arjun walks to the door..."*) immediately following dialogue were erroneously appended to character dialogue lines because they did not match cue formats or transitions.
   - Parentheticals (e.g. `(whispers)`, `[beat]`) were treated as spoken words, leading teleprompters and reader recording to instruct actors to speak stage directions out loud.
2. **Swift Regex Literal Incompatibility with iOS 14 and Earlier**:
   - `ScriptParser.isSceneHeading` previously used `#/.../#` Swift Regex literal syntax introduced in iOS 16+. On older iOS releases (iOS 14 & 15), Swift Regex literals cause compiler errors or runtime crashes.
3. **Audio Recording Giving Both Lines of Both Actors**:
   - When role classification did not match any cue, all lines evaluated `isMine == false`. As a result, `readerLines` contained all lines for all characters in the scene, asking the user to record both characters' dialogue into a single reader track.
4. **Recorded Lines Count Displaying Stale "0 recorded"**:
   - After recording or importing audio files, views like `PrepareView`, `ShootSetupView`, and `LineLearningViews` continued displaying `"0 recorded"` because they did not observe `store.readerTrackVersion`.
   - `RecordReaderView` used `@Environment(\.dismiss)` instead of `store.pop()`, leaving the `NavigationStack` path un-popped.
   - `ReaderLineRecorder.stop()` contained an aggressive `size > 128` guard that prematurely deleted short or asynchronously-flushed recordings from disk.

### Implementation
1. **Scene Description & Parenthetical Stripping ([ScriptParser.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Models/ScriptParser.swift))**:
   - Added `isActionOrDescription(_:knownSpeakers:)` to recognize camera directions, slugline markers (`DAY`, `NIGHT`, `LATER`), standalone stage directions (`BEAT`, `PAUSE`), and third-person character action sentences (`[Name] [walks/sits/looks/turns...]`). Action lines immediately flush preceding dialogue and reset `currentCharacter = nil`.
   - Added `stripParentheticals(_:)` to strip inline directions like `(whispers)` and `[sighs]` from spoken text, and skips standalone parenthetical lines entirely.
2. **iOS 14 & Earlier Compatibility ([ScriptParser.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Models/ScriptParser.swift))**:
   - Replaced `#/.../#` Swift Regex literal in `isSceneHeading` with standard `NSRegularExpression`, ensuring full compatibility with iOS 14 and earlier iOS releases.
3. **Single Reader Isolation ([PrepareViews.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/PrepareViews.swift))**:
   - Filtered `readerLines` in `RecordReaderView`, `ReaderView`, and `PrepareView` to isolate lines for the single target reader character (`$0.character.caseInsensitiveCompare(readerName) == .orderedSame`). The reader track never mixes dialogue from two different actors.
4. **Reactive Recording Status & Reliable File Persistence ([UIKitBridges.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/UIKitBridges.swift), [PrepareViews.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/PrepareViews.swift))**:
   - Added `ReaderTrackPlayer.hasRecording(auditionID:sceneIndex:line:)` to verify audio files across both raw and standardized paths.
   - Updated `ReaderLineRecorder.start` to ensure destination directories exist and removed aggressive deletion of valid files in `ReaderLineRecorder.stop`.
   - Added observation of `store.readerTrackVersion` to `PrepareView`, `ShootSetupView`, and `LineLearningViews` so UI counters immediately reflect recorded tracks.
   - Updated `RecordReaderView` to pop via `store.pop()`.

---

## 11. Document Camera Scanner Crash Fixes on iOS 18 (iPhone XS)

### Problem & Crash Root Causes
On iOS 18 devices, particularly iPhone XS (A12 Bionic with tighter unified memory and strict jetsam thresholds), completing a document scan crashed the application immediately:
1. **Dangling KVO Observers during VisionKit Teardown**:
   - `DocumentScannerView.Coordinator` registered KVO observations on `root.bounds`, `saveBtn.frame`, and `saveBtn.isHidden`, and injected a `DocumentScannerLayoutHelperView` into VisionKit's internal view hierarchy.
   - When the user tapped "Save", VisionKit began its completion transitions and internal view teardown.
   - The KVO observations fired during this teardown pass, triggering `DocumentScannerCustomizer.reposition(saveButton:in:)`.
   - Calling `sv.bringSubviewToFront(saveButton)` or mutating frames on views detached or in the middle of being dismantled triggered UIKit assertion failures (`NSInternalInconsistencyException`) and `EXC_BAD_ACCESS`.
2. **Synchronous View Controller Dismissal within Delegate Callback**:
   - `documentCameraViewController(_:didFinishWith:)` invoked `onFinish(pages)` synchronously on the main thread.
   - The SwiftUI caller immediately updated state (`showScanner = false`), destroying the `.fullScreenCover` and deallocating `VNDocumentCameraViewController` while Apple's internal delegate invocation was still active on the call stack.
3. **High-Resolution OCR Memory Spikes on A12 Bionic**:
   - `NoticeOCR.recognizeText(in:)` used `withTaskGroup` to process all scanned pages simultaneously.
   - Each task redrew a 3000×3000 uncompressed 32-bit bitmap (~36 MB) and allocated a separate Vision inference pipeline concurrently, causing rapid memory spikes exceeding 150 MB and triggering jetsam memory kills or Vision inference context allocation failures on A12 devices.

### Implementation
1. **Safe Customizer Teardown & Invalidation ([UIKitBridges.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/UIKitBridges.swift))**:
   - Added `detachCustomizer()` to `DocumentScannerView.Coordinator` and hooked it into `deinit`, `dismantleUIViewController`, and all delegate exit points (`didFinishWith`, `didCancel`, `didFailWithError`).
   - `detachCustomizer()` immediately invalidates `boundsObservation`, `frameObservation`, and `hiddenObservation`, sets `helperView.onLayout = nil`, and removes the layout helper view from its superview.
   - Added `isFinished` guard to immediately reject any further layout/reposition passes once the user completes or cancels scanning.
   - In `DocumentScannerCustomizer.reposition`: Guarded against zero bounds and ensured `saveButton.superview === sv` before calling `sv.bringSubviewToFront(saveButton)`.
2. **Asynchronous Delegate Completion ([UIKitBridges.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/UIKitBridges.swift))**:
   - In `documentCameraViewController(_:didFinishWith:)`, scanned page images are safely extracted while the scan object is valid, `detachCustomizer()` is executed, and `onFinish(pages)` is dispatched asynchronously via `DispatchQueue.main.async`. This ensures VisionKit cleanly unwinds and finishes its delegate handling before SwiftUI tears down the hosting cover.
3. **Sequential Low-Memory OCR Processing ([NoticeOCR.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/ModelViews/NoticeOCR.swift))**:
   - Replaced unbounded parallel `withTaskGroup` in `NoticeOCR.recognizeText(in:)` with a sequential loop running in `autoreleasepool`.
   - Capped maximum image dimension for Vision OCR at 2048px (reducing per-page uncompressed bitmap memory from ~36 MB down to ~16 MB without compromising text recognition accuracy).
   - Ensured all intermediate `UIImage`, `CGImage`, and Vision request objects are purged after each page is processed.

---

## 12. Prominent, Explicitly Requested Script Sides in Creation and Detail Flows

### Problems Identified
1. **App Never Specifically Asked for Script Sides**:
   - `NoticeParser.Draft.missingRequiredDetails` only checked `project`, `role`, and `due date`. When an audition notice contained basic project metadata but no scene dialogue, `missingRequiredDetails` evaluated to empty, causing the app to bypass `MissingDetailsView` entirely and never alert the actor that sides were missing.
   - When `MissingDetailsView` was shown, its prompt text only listed "project, role, due date" and labeled the sides card as `Sides (optional)`, giving the false impression that script sides were an optional afterthought rather than the central component of an audition.
2. **Sides Option Hidden Below Screen Fold**:
   - In `MissingDetailsView`, `DatePicker` without an explicit style rendered as a full-month graphical calendar taking ~360 pt of vertical space. On standard iPhone screen sizes, this pushed the sides section completely below the screen fold.
   - On the initial Add Audition capture sheet, the prompt only referred to "the notice" (`"Copied the notice?"`, `"Or bring it in"`), offering no visual indication that script sides could be brought in directly.
3. **Audition Detail Left Missing Sides Unaddressed**:
   - When an audition was saved without sides, `AuditionDetailView` placed `Your headshot` in `upNext`, while the card for sides was pushed below `upNext` with a low-priority secondary style.
   - Tapping on "Scene 1 (No sides yet — add them)" inside `PackageSheet` previously navigated to an empty `PrepareView` rather than opening sides capture directly.
4. **Draft Sides Sheet Pre-filled with Notice Text**:
   - Opening `AddDraftSidesSheet` or `RevisedSidesSheet` when no sides existed pre-filled the sides text field with the raw notice/email text and labeled the screen "Replace sides", forcing the actor to manually select and delete email text before pasting script pages.

### Implementation
1. **Explicit Script Sides Requirement in Audition Draft ([AddAuditionFlow.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift))**:
   - Added `hasSides` property on `NoticeParser.Draft` evaluating `!ScriptParser.parseScenes(from: sourceText, myRole: role).isEmpty`.
   - Included `"script sides"` in `missingRequiredDetails` whenever `!hasSides`.
   - Notices without script dialogue now explicitly route to `MissingDetailsView` with dynamic, grammatical subtitles: e.g. `"I couldn't find the script sides in the notice. Add what you know to continue."`
2. **Prominent, Unmissable Sides Cards in Creation Views ([AddAuditionFlow.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AddAuditionFlow.swift))**:
   - Initial Capture Sheet: Renamed prompt to `"Copied notice or sides?"` with explicit subtitle `"Paste breakdown, casting email, or script dialogue"`.
   - `MissingDetailsView`:
     - Changed `DatePicker` to `.datePickerStyle(.compact)` in an inline `HStack`, saving >300 pt of vertical height and keeping the Sides section fully visible above the fold on all iPhone displays.
     - Upgraded the sides card to prominent `OT.warning` with high-visibility primary button `[Add or scan sides]` and direct 1-tap `[Paste]` button.
     - Changed the bottom continue button to dynamically indicate `Continue` vs `Continue without sides`, ensuring actors are aware sides are missing while allowing them to proceed if they do not yet have the script.
   - `NoticeReviewView`: Added prominent `No sides attached yet` warning card with `.buttonStyle(.otPrimary)` and 1-tap `[Paste]`.
   - `AddDraftSidesSheet`: Dynamically switches between `"Add sides"` and `"Replace sides"` based on `draft.hasSides`. When no sides have been added yet, the text field starts clean and empty instead of displaying notice text.
3. **High-Priority Sides Banner on Audition Detail ([AuditionDetailView.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Views/AuditionDetailView.swift))**:
   - When `a.scenes.isEmpty`, a high-visibility callout card is displayed directly beneath the Package summary at the very top of `AuditionDetailView` with a primary `[Add or scan sides]` button.
   - In `PackageSheet`, tapping on a scene piece when no sides are attached directly invokes `onAddSides: { showSides = true }`, opening `RevisedSidesSheet` immediately.
   - In `RevisedSidesSheet`, initial text starts empty when `isNewSides` is true.
