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

## 2. Bottom Navigation Architecture (`2 and 1` Layout)

### Design Goal
Preserve Apple's iOS 18 floating navigation language while giving the primary navigation pill more visual presence without awkwardly merging all actions together.

### Implementation
- **Layout Separation:**
  - **The 2-Tab Floating Pill:** Houses primary destinations (`Auditions` and `Practice`).
  - **The 1 Detached Circle:** Dedicated circular `[ 🔍 ]` search button anchored to the trailing edge.
- **Width Customization:**
  - In iOS 18 native `TabView`, frame modifiers on `Tab` labels are ignored by UIKit's floating bar engine.
  - Applied balanced typographic em-spacing (`\u{2003}\u{2003}\u{2003}`) to each tab title.
  - Increased pill width from **~188 pt (563 px)** to **~245 pt (736 px)**, closing the excessive void between the pill and the search button while keeping the selection highlight capsule symmetric and fluid.

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
  - Removed `.profile` case from `SearchScope` in `SearchView` (`OneTake/Features/Auditions/AuditionsView.swift`).
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
- Added explicit `.padding(.top, 30)` to the header `HStack` in `ProfileView` (`OneTake/Features/Profile/ProfileViews.swift`).
- This offsets the title and Done button by ~30 pt, providing clean visual separation from the sheet drag indicator and matching native modal sheet ergonomics.

---

## File Reference

- [OneTake/App/OneTakeApp.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/App/OneTakeApp.swift): `RootTabView`, dynamic search tab inclusion, conditional search activation.
- [OneTake/DesignSystem/Components/Components.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/DesignSystem/Components/Components.swift): `ProfileButton` definition with 44×44 pt touch frame and white stroke border.
- [OneTake/Features/Auditions/AuditionsView.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Features/Auditions/AuditionsView.swift): Top-right header actions with `ProfileButton` and `+` button.
- [OneTake/Features/Practice/PracticeViews.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Features/Practice/PracticeViews.swift): Consistent top-right header `ProfileButton` integration.
- [OneTake/Features/Profile/ProfileViews.swift](file:///Users/user76/Downloads/OneTake-iOS/OneTake/Features/Profile/ProfileViews.swift): Profile modal layout, header top padding (30pt), account section separation, and privacy/data account deletion.
