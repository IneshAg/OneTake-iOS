import SwiftUI
import UIKit

// MARK: - Velvet colour tokens (generated from the Figma variable collection "Velvet", Light / Dark modes)

extension UIColor {
    /// Creates a dynamic colour that resolves per trait collection (Light / Dark).
    convenience init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        }
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Design tokens. Names mirror the Figma variables (`bg/canvas` → `OT.bgCanvas`).
enum OT {
    // Backgrounds & surfaces
    static let bgCanvas      = Color(UIColor(light: 0xF6F4F7, dark: 0x121014))
    static let surfaceCard   = Color(UIColor(light: 0xFFFFFF, dark: 0x1B181E))
    static let surfaceSunken = Color(UIColor(light: 0xEFEBF1, dark: 0x252128))
    static let surfaceRaised = Color(UIColor(light: 0xFFFFFF, dark: 0x252128))
    static let fillField     = Color(UIColor(light: 0x1E1A22, dark: 0xF3EEF5, lightAlpha: 0.07, darkAlpha: 0.10))
    static let fillQuiet     = Color(UIColor(light: 0x1E1A22, dark: 0xF3EEF5, lightAlpha: 0.06, darkAlpha: 0.09))
    static let separator     = Color(UIColor(light: 0xE3DDE7, dark: 0x322C37))
    static let scrim         = Color(UIColor(light: 0x120E15, dark: 0x120E15, lightAlpha: 0.34, darkAlpha: 0.6))

    // Labels
    static let labelPrimary   = Color(UIColor(light: 0x1E1A22, dark: 0xF3EEF5))
    static let labelSecondary = Color(UIColor(light: 0x5A5262, dark: 0xB8AEBF))
    static let labelTertiary  = Color(UIColor(light: 0x736A7B, dark: 0x8A8092))
    static let labelOnAccent  = Color(UIColor(light: 0xFFFFFF, dark: 0x24152F))

    // Accent (aubergine) — the only accent colour
    static let accent     = Color(UIColor(light: 0x5B3E73, dark: 0xC8A8E0))
    static let accentSoft = Color(UIColor(light: 0x5B3E73, dark: 0xC8A8E0, lightAlpha: 0.10, darkAlpha: 0.18))

    // Amber means TIME only (countdowns, due dates)
    static let due      = Color(UIColor(light: 0x8E6210, dark: 0xE2BE7A))
    static let dueTrack = Color(UIColor(light: 0x8E6210, dark: 0xE2BE7A, lightAlpha: 0.12, darkAlpha: 0.18))

    // Status
    static let success  = Color(UIColor(light: 0x3C7A5E, dark: 0x82C9A4))
    static let danger   = Color(UIColor(light: 0xC2364A, dark: 0xF2788A))
    static let warning  = Color(UIColor(light: 0x8E6210, dark: 0xE2BE7A))
    static let reader   = Color(UIColor(light: 0x3C7A86, dark: 0x7DC0CB))

    // Script
    static let scriptHighlight   = Color(UIColor(light: 0xF2E8D5, dark: 0x3A3122))
    static let scriptOnHighlight = Color(UIColor(light: 0x1E1A22, dark: 0xF7EEDC))

    // Camera (always dark)
    static let cameraBg     = Color(UIColor(hex: 0x0C0B0D))
    static let cameraGlass  = Color(UIColor(hex: 0x2A2730, alpha: 0.55))
    static let cameraLabel  = Color.white
    static let cameraLabel2 = Color.white.opacity(0.68)
    static let cameraStroke = Color.white.opacity(0.18)
    static let recRed       = Color(UIColor(hex: 0xE0475A))

    // Layout
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 24
    static let rowHeight: CGFloat = 66
    static let minTap: CGFloat = 44
}

// MARK: - Typography (SF Pro via system font)

extension Font {
    static let otLargeTitle = Font.system(size: 34, weight: .bold)
    static let otTitle      = Font.system(size: 28, weight: .bold)
    static let otHero       = Font.system(size: 32, weight: .bold)
    static let otHeadline   = Font.system(size: 17, weight: .semibold)
    static let otBody       = Font.system(size: 17)
    static let otCallout    = Font.system(size: 15)
    static let otSubhead    = Font.system(size: 15, weight: .medium)
    static let otFootnote   = Font.system(size: 13)
    static let otCaption    = Font.system(size: 12)
    static let otEyebrow    = Font.system(size: 13, weight: .semibold)
    static let otNumber     = Font.system(size: 34, weight: .bold).monospacedDigit()
}

// MARK: - Common modifiers

struct CardBackground: ViewModifier {
    var radius: CGFloat = OT.cardRadius
    func body(content: Content) -> some View {
        content
            .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

extension View {
    func otCard(radius: CGFloat = OT.cardRadius) -> some View { modifier(CardBackground(radius: radius)) }

    /// Full-screen canvas background used by every tab root.
    func otCanvas() -> some View { background(OT.bgCanvas.ignoresSafeArea()) }

    /// Ensures a 44 pt hit area without changing layout.
    func otHitArea() -> some View { contentShape(Rectangle()).frame(minWidth: OT.minTap, minHeight: OT.minTap) }
}
