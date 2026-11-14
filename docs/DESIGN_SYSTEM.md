# OneTake Design System (`OneTakeUI`)

The OneTake design system unifies the visual language, interaction patterns, tokens, and navigation paradigms across the entire iOS application, widgets, and share extension.

---

## 1. Core Principles

1. **Dark-first, Adaptive:** Every element supports Light and Dark appearance through semantic dynamic tokens (`OT.*`).
2. **Predictable Geometry & Modularity:** No hardcoded heights or arbitrary paddings. Sizing follows a 4pt/8pt grid via `OTSpace`, `OTRadius`, and `OTControlSize`.
3. **Dedicated Screen Containers:** Navigation bars are never hidden haphazardly. `OTScreen` owns navigation headers, back transitions, canvas backgrounds, and system bar visibility.
4. **Resilient Tab Bar Management:** Pushed screens strictly suppress the floating tab bar using dual-layer enforcement: SwiftUI's native `.toolbarVisibility` and `TabBarShower` / `TabBarHider` responder inspection.

---

## 2. Token Catalogue

### Spacing (`OTSpace`)
| Token | Points | Typical Use |
|---|---|---|
| `OTSpace.xxs` | 2 pt | Micro spacing between icon and text |
| `OTSpace.xs` | 4 pt | Tight label/subtitle stacks |
| `OTSpace.s` | 8 pt | Component item spacing, standard inset |
| `OTSpace.m` | 12 pt | Intermediate layout gap |
| `OTSpace.l` | 16 pt | Standard card internal padding, section item gaps |
| `OTSpace.xl` | 24 pt | Section separation |
| `OTSpace.xxl` | 32 pt | Major layout margins, screen bottom padding |
| `OTSpace.gutter` | 16 pt | Universal screen horizontal margin |

### Corner Radii (`OTRadius`)
| Token | Points | Typical Use |
|---|---|---|
| `OTRadius.s` | 8 pt | Small tags, badges, status chips |
| `OTRadius.m` | 12 pt | Form inputs, buttons, menu pills |
| `OTRadius.l` | 16 pt | Cards, list tiles, video previews |
| `OTRadius.xl` | 24 pt | Elevated sheets, prominent modal cards |
| `OTRadius.full` | 9999 pt | Capsule buttons, circular icon buttons |

### Color Tokens (`OT.*`)
| Token | Purpose | Light / Dark Behavior |
|---|---|---|
| `OT.bgCanvas` | Root app background | `#F8F6FA` / `#121014` |
| `OT.surfaceCard` | Standard grouped card background | `#FFFFFF` / `#1B181E` |
| `OT.surfaceRaised` | Modals, elevated dialogs | `#FFFFFF` / `#252128` |
| `OT.surfaceSunken` | Inset wells, sliders | `#EFEBF1` / `#252128` |
| `OT.fillField` | Textfield, search bar, button background | 7% / 10% opacity dynamic fill |
| `OT.separator` | Dividers, hair lines | `#E3DDE7` / `#322C37` |
| `OT.accent` | Aubergine brand accent | `#5B3E73` / `#C8A8E0` |
| `OT.accentSoft` | Accent tint behind icons/chips | 10% / 18% opacity dynamic tint |
| `OT.labelPrimary` | Main headings, primary content | `#1E1A22` / `#F3EEF5` |
| `OT.labelSecondary` | Subheadings, supporting copy | `#5A5262` / `#B8AEBF` |
| `OT.labelTertiary` | Timestamps, metadata | `#736A7B` / `#8A8092` |
| `OT.due` | Time/urgency countdowns (Amber only) | `#8E6210` / `#E2BE7A` |
| `OT.success` | Completed steps, valid state | `#3C7A5E` / `#82C9A4` |
| `OT.danger` | Destructive actions, errors | `#C2364A` / `#F2788A` |
| `OT.cameraBg` | Always-dark camera background | `#0C0B0D` (Pure dark) |

---

## 3. Button Component Matrix

Buttons use `.buttonStyle(.ot(variant, size: size, fullWidth: bool, shape: shape))` or a convenience style. The configured shape controls both the background and the hit-test shape.

### Shapes

- `.squircle` is the default and uses continuous corners sized by the control.
- `.capsule` uses pill ends. `.otCompact` and `.otCompactPrimary` use this shape.
- `.rounded(radius)` uses circular corners. Pass `nil` for a radius based on control size.

### Variants
- `.primary` (`.otPrimary`): Filled accent background with contrasting white/dark text. Reserved for primary calls-to-action (e.g., "Set up camera", "Continue to slate").
- `.secondary` (`.otSecondary`): Soft field fill with primary label. Used for secondary actions (e.g., "Retake", "Replace").
- `.tertiary` uses a clear background.
- `.glass` uses ultra-thin material, with a dedicated fill on camera surfaces.
- `.destructive`: Red danger fill or text for permanent deletion.

### Sizes
| Size | Min Height | Typography | Horizontal Padding |
|---|---|---|---|
| `.small` | 32 pt | `Font.otCaption.weight(.semibold)` | `OTSpace.s` (8pt) |
| `.medium` | 44 pt | `Font.otSubhead.weight(.semibold)` | `OTSpace.m` (12pt) |
| `.large` | 52 pt | `Font.otHeadline` | `OTSpace.l` (16pt) |

---

## 4. Component Catalogue

- **`OTScreen`**: The foundational container for all pushed views. Enforces canvas background, automatic scroll-handling, `OTNavHeader`, and navigation bar suppression.
- **`OTNavHeader`**: Consistent top navigation bar with circular back button and optional title/trailing actions.
- **`OTSheetHeader`**: Modal sheet header with leading/trailing action buttons and title.
- **`OTCard` (`.otCard(kind)` / `.otCard(radius:)`)**: Standard card wrapper supporting `.grouped`, `.elevated`, and `.inset` appearances.
- **`OTBottomBar` (`.otBottomBar { ... }`)**: Anchors primary action buttons and status indicators to the bottom safe area with canvas-matching drop shadows.
- **`OTStatusLine`**: High-signal status indicator (`.success`, `.warning`, `.danger`, `.neutral`) with icon, label, and detail.
- **`OTCallout`**: Highlighted information box with icon, title, message, and action slot.

---

## 5. Floating Tab Bar Visibility Architecture

The floating tab bar must only appear at the root level of the main navigation tabs:
1. **SwiftUI Layer:** Each `NavigationStack` in `RootTabView` binds its tab bar visibility directly to the stack's state:
   ```swift
   .toolbarVisibility(store.auditionsPath.isEmpty ? .visible : .hidden, for: .tabBar)
   ```
2. **UIKit Bridge Layer (`TabBarShower` / `TabBarHider`):**
   - `TabBarShower(isVisible:)` checks if `isVisible` is true AND inspects the active `UINavigationController.viewControllers.count <= 1`. If pushed (`count > 1`), it guarantees the tab bar remains hidden.
   - `TabBarHider` proactively sets `hidesBottomBarWhenPushed = true` on the hosting controller hierarchy and hides the UITabBarController.

---

## 6. Linter & `ot-lint:allow` Policy

To maintain design system adherence and eliminate regressions, `./scripts/lint-design-system.sh --strict` runs on all code.

### Permitted Exceptions (`// ot-lint:allow`)
The `// ot-lint:allow` comment is strictly reserved for:
- Hardware/sensor geometries (camera reticle sizes, video aspect ratios, waveform bar geometry).
- Standard iOS accessibility touch target dimensions (`44x44`).
- Low-level UIKit `UIColor` trait collection resolvers that power the design system tokens themselves.
