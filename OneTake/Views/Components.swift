import SwiftUI

// MARK: - Section label (v2/Section Label)

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.otEyebrow)
            .kerning(0.4)
            .foregroundStyle(OT.labelTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Progress ring / readiness dial (v2/Progress Ring)

/// Segmented dial: one segment per package piece. Done = accent, next = soft accent, todo = quiet track.
struct ReadinessDial: View {
    let done: Int
    let total: Int
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6
    var onDark = false

    var body: some View {
        let gap = 0.035
        let seg = (1.0 - Double(total) * gap) / Double(total)
        ZStack {
            ForEach(0..<total, id: \.self) { i in
                let start = Double(i) * (seg + gap) + gap / 2
                Circle()
                    .trim(from: start, to: start + seg)
                    .stroke(color(for: i), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: -2) {
                Text("\(done)").font(.system(size: size * 0.3, weight: .bold)).monospacedDigit()
                Text("of \(total)").font(.system(size: size * 0.18, weight: .medium))
            }
            .foregroundStyle(onDark ? .white : OT.labelPrimary)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) pieces ready")
    }

    private func color(for i: Int) -> Color {
        if i < done { return onDark ? .white : OT.accent }
        if i == done { return (onDark ? Color.white : OT.accent).opacity(0.45) }
        return onDark ? .white.opacity(0.22) : OT.fillQuiet
    }
}

// MARK: - Continuous progress ring (v2/Progress Ring, weekly minutes)

struct ProgressRing: View {
    let value: Double
    var lineWidth: CGFloat = 8
    var body: some View {
        ZStack {
            Circle().stroke(OT.fillQuiet, lineWidth: lineWidth)
            Circle().trim(from: 0, to: value)
                .stroke(OT.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityElement().accessibilityValue("\(Int(value * 100)) percent")
    }
}

// MARK: - Readiness dashes (v2/Readiness Dashes)

struct ReadinessDashes: View {
    let done: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i < done ? OT.accent : OT.fillQuiet)
                        .frame(width: 14, height: 4)
                }
            }
            Text("\(done) of \(total)").font(.otCaption).foregroundStyle(OT.labelTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) ready")
    }
}

// MARK: - Package steps bar (v2/Package Steps)

struct PackageStepsBar: View {
    let pieces: [Piece]
    var body: some View {
        let nextIndex = pieces.firstIndex { !$0.isDone }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { i, piece in
                    Capsule()
                        .fill(piece.isDone ? OT.accent : (i == nextIndex ? OT.accent.opacity(0.4) : OT.fillQuiet))
                        .frame(height: 8)
                }
            }
            HStack(spacing: 4) {
                ForEach(Array(pieces.enumerated()), id: \.element.id) { i, piece in
                    Text(piece.title)
                        .font(.otCaption.weight(i == nextIndex ? .semibold : .regular))
                        .foregroundStyle(i == nextIndex ? OT.accent : OT.labelTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Buttons

/// A gentle press-scale for whole-card buttons (audition cards, first-run card).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = OT.accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.otHeadline)
            .foregroundStyle(OT.labelOnAccent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var onDark = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.otHeadline)
            .foregroundStyle(onDark ? .white : OT.labelPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(onDark ? Color.white.opacity(0.14) : OT.fillField, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var otPrimary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var otSecondary: SecondaryButtonStyle { .init() }
    static var otSecondaryDark: SecondaryButtonStyle { .init(onDark: true) }
}

// MARK: - Schedule row (v2/Schedule Row)

struct ScheduleRow: View {
    let eyebrow: String
    let value: String
    let title: String
    let detail: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow).font(.system(size: 11, weight: .semibold)).foregroundStyle(OT.labelTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(.otSubhead.weight(.semibold)).foregroundStyle(OT.labelPrimary)
            }
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.otBody).foregroundStyle(OT.labelPrimary).lineLimit(1)
                Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let trailing { trailing }
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: OT.rowHeight)
        .contentShape(Rectangle())
    }
}

// MARK: - Inline status (v2/Inline Status)

enum InlineStatusKind { case saving, processing, uploading, delivered, failed, offline }

struct InlineStatus: View {
    let kind: InlineStatusKind
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            switch kind {
            case .saving, .processing, .uploading: ProgressView().controlSize(.mini)
            case .delivered: Image(systemName: "checkmark.circle.fill").foregroundStyle(OT.success)
            case .failed:    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(OT.danger)
            case .offline:   Image(systemName: "wifi.slash").foregroundStyle(OT.warning)
            }
            Text(text).font(.otFootnote).foregroundStyle(OT.labelSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(OT.fillQuiet, in: Capsule())
    }
}

// MARK: - Sheet header (v2/Sheet Header)

struct SheetHeader: View {
    let title: String
    var leading: String? = "Cancel"
    var trailing: String? = nil
    var onLeading: () -> Void = {}
    var onTrailing: () -> Void = {}

    var body: some View {
        HStack {
            if let leading { Button(leading, action: onLeading).buttonStyle(.bordered).buttonBorderShape(.capsule) }
            Spacer()
            Text(title).font(.otHeadline)
            Spacer()
            if let trailing { Button(trailing, action: onTrailing).buttonStyle(.borderedProminent).buttonBorderShape(.capsule) }
            else if leading != nil { Color.clear.frame(width: 72, height: 1) }
        }
        .padding(.horizontal, OT.gutter)
        .padding(.top, 12)
    }
}

// MARK: - Icon list row (used by Add audition, Shoot setup, error states)

struct IconRow: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = OT.accent

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(OT.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.otBody).foregroundStyle(OT.labelPrimary)
                Text(detail).font(.otFootnote).foregroundStyle(OT.labelTertiary)
            }
            Spacer()
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Headshot photo

struct HeadshotImage: View {
    /// Which of the actor's own headshots to show (`front`, `left`, `right`). Without one taken —
    /// or with no key — it's a neutral silhouette, never a stand-in photo of someone else.
    var realKey: String? = nil

    var body: some View {
        if let realKey, let real = HeadshotStore.load(key: realKey) {
            Image(uiImage: real)
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
        } else {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.35)))
        }
    }
}

// MARK: - Top bar Profile button

struct ProfileButton: View {
    var action: () -> Void
    @Environment(AppStore.self) private var store

    private var strokeColor: Color {
        Color(UIColor(light: 0x1E1A22, dark: 0xFFFFFF, lightAlpha: 0.22, darkAlpha: 0.85))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if let front = HeadshotStore.load(key: "front") {
                    Image(uiImage: front)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
                } else {
                    Circle()
                        .fill(OT.accentSoft)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(strokeColor, lineWidth: 1.5))
                    Image(systemName: "person.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(OT.accent)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .id(store.headshotVersion)
        .accessibilityLabel("Profile")
    }
}

// MARK: - Date helpers

extension Date {
    var otDue: String { formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
    var otDayMonth: String { formatted(.dateTime.day().month(.abbreviated)) }
}
