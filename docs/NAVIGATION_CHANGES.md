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
