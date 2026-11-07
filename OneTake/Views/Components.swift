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

/// Makes a printed `?` or silent reaction cue read as a playable non-verbal expression while retaining its script meaning.
struct SilentReactionCue: View {
    var cueText: String = "?"
    var isMine: Bool = true
    var inPrompter: Bool = false

    private var cueSymbol: String {
        let trimmed = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "?" { return "?" }
        if trimmed == "..." || trimmed == "…" { return "…" }
        if trimmed == "." { return "•" }
        return "•"
    }

    private var headingText: String {
        let trimmed = cueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "?" {
            return isMine ? "Questioning expression" : "Questioning beat"
        } else if trimmed == "..." || trimmed == "…" || trimmed == "." {
            return "Silent pause"
        } else if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
            return String(trimmed.dropFirst().dropLast()).capitalized
        }
        return "Silent reaction"
    }

    private var instructionText: String {
        if inPrompter {
            return isMine ? "React in character · hold your expression" : "Non-verbal beat · continuing..."
        } else {
            return isMine ? "React in character with this expression. No spoken line." : "Non-verbal beat. No reader recording needed."
        }
    }

    var body: some View {
        if inPrompter {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isMine ? OT.prompterGold.opacity(0.22) : OT.reader.opacity(0.22))
                        .frame(width: 38, height: 38)
                    Text(cueSymbol)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(isMine ? OT.prompterGold : OT.reader)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(headingText)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("[ \(cueText) ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Text(instructionText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .center, spacing: 12) {
                Text(cueSymbol)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isMine ? OT.accent : OT.reader)
                    .frame(width: 36, height: 36)
                    .background(isMine ? OT.accentSoft : OT.reader.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(headingText)
                            .font(.otHeadline)
                            .foregroundStyle(OT.labelPrimary)
                        Text("[ \(cueText) ]")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(OT.labelTertiary)
                    }
                    Text(instructionText)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(OT.separator, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }
}

/// First-letter recall text. Each masked word is an individual, accessible hint target.
struct RecallWordHintText: View {
    let text: String
    let revealedWords: Set<Int>
    let font: Font
    let color: Color
    let onRevealWord: (Int) -> Void

    private var words: [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    var body: some View {
        RecallWordsLayout(spacing: 3, lineSpacing: 2) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Button { onRevealWord(index) } label: {
                    Text(revealedWords.contains(index) ? word : masked(word))
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealedWords.contains(index) ? word : "Hidden word, tap to reveal")
                .accessibilityHint("Reveals this word for your practice hint")
            }
        }
    }

    private func masked(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first) + (word.count > 1 ? "—" : "")
    }
}

/// Meaningful-word gaps. Each underscore is tappable and reveals its original word as a clue.
struct RecallGapHintText: View {
    let text: String
    let hiddenWords: Set<Int>
    let revealedWords: Set<Int>
    let font: Font
    let color: Color
    let onToggleWord: (Int) -> Void

    private var words: [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }

    var body: some View {
        RecallWordsLayout(spacing: 3, lineSpacing: 2) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                let isHidden = hiddenWords.contains(index) && !revealedWords.contains(index)
                Button { if hiddenWords.contains(index) { onToggleWord(index) } } label: {
                    Text(isHidden ? masked(word) : word)
                        .font(font)
                        .foregroundStyle(color)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hiddenWords.contains(index))
                .accessibilityLabel(isHidden ? "Hidden word, tap to reveal" : word)
                .accessibilityHint("Shows the full word as a practice clue")
            }
        }
    }

    private func masked(_ word: String) -> String {
        let letters = word.filter(\.isLetter)
        let punctuation = word.filter { !$0.isLetter && !$0.isNumber }
        return String(repeating: "_", count: min(max(2, letters.count), 8)) + punctuation
    }
}

/// A small wrapping layout lets each script word remain tappable without forcing the line into a horizontal scroll view.
private struct RecallWordsLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? max(x - spacing, 0), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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

/// A native iOS highlight style for whole-card buttons (audition cards, first-run card).
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = OT.accent
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.otHeadline)
            .foregroundStyle(OT.labelOnAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isEnabled ? tint : tint.opacity(0.35))
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : (isEnabled ? 1 : 0.55))
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var onDark = false
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.otHeadline)
            .foregroundStyle(onDark ? .white : OT.labelPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(onDark ? Color.white.opacity(0.14) : OT.fillField)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.70 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CompactSecondaryButtonStyle: ButtonStyle {
    var onDark = false
    var cornerRadius: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.otFootnote.weight(.semibold))
            .foregroundStyle(onDark ? .white : OT.labelPrimary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(onDark ? Color.white.opacity(0.14) : OT.fillField)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.70 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Figma's compact glass action for secondary controls. Primary actions keep their solid accent fill.
struct GlassLabelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.otSubhead.weight(.semibold))
            .foregroundStyle(OT.accent)
            .padding(.horizontal, 13)
            .frame(minHeight: 40)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.62), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var otPrimary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var otSecondary: SecondaryButtonStyle { .init() }
    static var otSecondaryDark: SecondaryButtonStyle { .init(onDark: true) }
}
extension ButtonStyle where Self == CompactSecondaryButtonStyle {
    static var otCompact: CompactSecondaryButtonStyle { .init() }
    static var otCompactDark: CompactSecondaryButtonStyle { .init(onDark: true) }
}
extension ButtonStyle where Self == GlassLabelButtonStyle { static var otGlass: GlassLabelButtonStyle { .init() } }

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
            if let leading {
                Button(leading, action: onLeading)
                    .font(.system(size: 17))
                    .foregroundStyle(OT.accent)
                    .frame(minHeight: 44)
            }
            Spacer()
            Text(title).font(.otHeadline)
            Spacer()
            if let trailing {
                Button(trailing, action: onTrailing)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(OT.accent)
                    .frame(minHeight: 44)
            }
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
    var auditionID: UUID? = nil
    var iconSize: CGFloat? = nil
    var onDark: Bool = false
    @Environment(AppStore.self) private var store

    var body: some View {
        let _ = store.headshotVersion
        if let realKey, let real = HeadshotStore.load(key: realKey, auditionID: auditionID) {
            Color.clear
                .overlay {
                    Image(uiImage: real)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .contentShape(Rectangle())
                .id("\(realKey)-\(store.headshotVersion)")
        } else if onDark {
            LinearGradient(colors: [Color(white: 0.28), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                .overlay(Image(systemName: "person.fill").font(.system(size: iconSize ?? 40)).foregroundStyle(.white.opacity(0.35)))
        } else {
            ZStack {
                OT.accentSoft
                Image(systemName: "person.fill")
                    .font(.system(size: iconSize ?? 22, weight: .semibold))
                    .foregroundStyle(OT.accent)
            }
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
                        .overlay(Circle().stroke(OT.accent.opacity(0.25), lineWidth: 1))
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

// MARK: - Native iOS Glass Back Button

struct NativeNavPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CircularIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassBackButton: View {
    var label: String = "Back"
    var onDark: Bool = false
    var action: () -> Void

    private var isDismissStyle: Bool {
        label.caseInsensitiveCompare("Cancel") == .orderedSame ||
        label.caseInsensitiveCompare("Done") == .orderedSame
    }

    private var isCloseStyle: Bool {
        label.caseInsensitiveCompare("Close") == .orderedSame
    }

    var body: some View {
        Button(action: {
            Haptics.tick()
            action()
        }) {
            Group {
                if isDismissStyle {
                    // Standard iOS navigation sheet dismiss text
                    Text(label)
                        .font(.system(size: 17, weight: label == "Done" ? .semibold : .regular))
                        .foregroundStyle(onDark ? .white : OT.accent)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                } else if isCloseStyle {
                    // Circular close button (xmark) for camera/media viewports
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(onDark ? .white : OT.labelPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                } else {
                    // Back is an icon-only glass control throughout the app. Context is kept
                    // accessible without making the visual control look like a text link.
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(onDark ? Color.white : OT.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
            }
            .contentShape(Rectangle())
        }
        .modifier(GlassButtonCompatibility(enabled: !isDismissStyle))
        .accessibilityLabel(label.isEmpty ? "Back" : label)
    }
}

/// Shared circular glass control for floating header actions such as Add and Close.
struct GlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var onDark = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(onDark ? Color.white : OT.labelPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .modifier(GlassButtonCompatibility(enabled: true))
        .accessibilityLabel(accessibilityLabel)
    }
}

struct GlassButtonCompatibility: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if !enabled {
            // Text actions such as Cancel and Done must stay text actions. Applying the legacy
            // circular material fallback here wrapped those labels in a stray circle on iOS 26.
            content.buttonStyle(.plain)
        } else if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.7))
                .buttonStyle(NativeNavPressStyle())
        }
        #else
        if enabled {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.7))
                .buttonStyle(NativeNavPressStyle())
        } else {
            content.buttonStyle(.plain)
        }
        #endif
    }
}

struct GlassCapsuleButtonCompatibility: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            content.buttonStyle(.otGlass)
        }
        #else
        content.buttonStyle(.otGlass)
        #endif
    }
}

/// Prominent native glass action with a branded solid fallback before iOS 26.
struct GlassProminentCapsuleButtonCompatibility: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(OT.accent)
        } else {
            content.buttonStyle(.otPrimary)
        }
        #else
        content.buttonStyle(.otPrimary)
        #endif
    }
}

// MARK: - In-content Navigation Header

struct InContentNavHeader<TrailingContent: View>: View {
    var title: String = ""
    var backLabel: String = "Back"
    var onDark: Bool = false
    var onBack: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> TrailingContent
    @Environment(\.dismiss) private var dismiss

    init(title: String = "", backLabel: String = "Back", onDark: Bool = false, onBack: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> TrailingContent) {
        self.title = title
        self.backLabel = backLabel
        self.onDark = onDark
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            GlassBackButton(label: backLabel, onDark: onDark) {
                if let onBack { onBack() } else { dismiss() }
            }

            Spacer()

            if !title.isEmpty {
                Text(title)
                    .font(.otHeadline)
                    .foregroundStyle(onDark ? OT.cameraLabel : OT.labelPrimary)
                    .lineLimit(1)
            }

            Spacer()

            trailing()
        }
        .frame(minHeight: 44)
    }
}

extension InContentNavHeader where TrailingContent == AnyView {
    init(title: String = "", backLabel: String = "Back", onDark: Bool = false, onBack: (() -> Void)? = nil) {
        self.init(title: title, backLabel: backLabel, onDark: onDark, onBack: onBack) {
            AnyView(Color.clear.frame(width: 44, height: 44).accessibilityHidden(true))
        }
    }
}

// MARK: - Sides Input Tiles & Chips (Native iOS quick action buttons)

struct SidesInputTile: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OT.labelPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(OT.labelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OT.surfaceCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(OT.separator, lineWidth: 1)
        )
    }
}

struct SidesChip: View {
    let title: String
    let value: String
    var isAccent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title + ":")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isAccent ? OT.accent : OT.labelSecondary)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isAccent ? OT.accent : OT.labelPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isAccent ? OT.accentSoft : OT.surfaceCard, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAccent ? OT.accent.opacity(0.3) : OT.separator, lineWidth: 1)
        )
    }
}

// MARK: - Audition Material Kind Picker

struct AuditionMaterialKindPicker: View {
    @Binding var selected: AuditionMaterialKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(AuditionMaterialKind.allCases) { kind in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { selected = kind }
                        Haptics.tick()
                    } label: {
                        Label(kind.shortLabel, systemImage: kind.icon)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: selected.icon)
                        .foregroundStyle(OT.accent)
                    Text(selected.shortLabel)
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OT.labelTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            Text(selected.description)
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
        }
    }
}

// MARK: - Milestone Dates List Card

struct MilestoneDatesListCard: View {
    var dates: [AuditionDate]
    var onAddDate: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Key Dates & Deadlines", systemImage: "calendar.badge.clock")
                    .font(.otCaption.weight(.bold))
                    .foregroundStyle(OT.labelPrimary)
                Spacer()
                if let onAddDate {
                    Button(action: onAddDate) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add date")
                        }
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if dates.isEmpty {
                Text("No additional milestone dates detected.")
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelTertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(dates) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.kind.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.kind == .submissionDeadline ? OT.due : OT.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.label.isEmpty ? item.kind.title : item.label)
                                    .font(.otFootnote.weight(.semibold))
                                    .foregroundStyle(OT.labelPrimary)
                                if let text = item.sourceText, !text.isEmpty {
                                    Text(text)
                                        .font(.system(size: 11))
                                        .foregroundStyle(OT.labelTertiary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(item.formattedDate)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(item.kind == .submissionDeadline ? OT.due : OT.labelSecondary)
                        }
                        .padding(.vertical, 4)
                        if item.id != dates.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(14)
        .otCard(radius: 16)
    }
}

// MARK: - Project Details & Production Info Card

struct ProjectDetailsCard: View {
    var details: AuditionProjectDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("About this project", systemImage: "building.2.crop.circle")
                .font(.otCaption.weight(.bold))
                .foregroundStyle(OT.labelPrimary)

            if let synopsis = details.synopsis, !synopsis.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project summary").font(.system(size: 11, weight: .semibold)).foregroundStyle(OT.labelTertiary)
                    Text(synopsis)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }
            }

            let terms = [
                ("Pay & Terms", details.payTerms, "dollarsign.circle.fill"),
                ("Union Status", details.unionStatus, "person.3.sequence.fill"),
                ("Location", details.productionLocation ?? details.castingArea, "mappin.circle.fill"),
                ("Company / Team", [details.productionCompany, details.producer, details.director].compactMap { $0 }.joined(separator: " · "), "film.fill")
            ].filter { $0.1 != nil && $0.1?.isEmpty == false }

            if !terms.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(terms, id: \.0) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.2)
                                .font(.system(size: 13))
                                .foregroundStyle(OT.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.0)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(OT.labelTertiary)
                                Text(item.1 ?? "")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(OT.labelPrimary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .otCard(radius: 16)
    }
}

// MARK: - Source Evidence & Provenance View

struct FieldEvidenceSection: View {
    var evidence: [AuditionFieldEvidence]
    var sources: [AuditionSource]
    @State private var isExpanded = false

    var body: some View {
        if !evidence.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Every extracted detail is grounded in the original casting notice or sides:")
                        .font(.system(size: 11))
                        .foregroundStyle(OT.labelTertiary)

                    ForEach(evidence) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.field.capitalized)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(OT.accent)
                                Spacer()
                                Text(sourceName(for: item))
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(OT.labelTertiary)
                            }

                            Text("“\(item.excerpt)”")
                                .font(.system(size: 11, design: .serif))
                                .italic()
                                .foregroundStyle(OT.labelSecondary)
                                .padding(8)
                                .background(OT.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        if item.id != evidence.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(OT.accent)
                    Text("Source Evidence & Provenance (\(evidence.count) grounded points)")
                        .font(.otCaption.weight(.semibold))
                        .foregroundStyle(OT.labelPrimary)
                }
            }
            .padding(14)
            .otCard(radius: 16)
        }
    }

    private func sourceName(for item: AuditionFieldEvidence) -> String {
        if let page = item.pageNumber {
            return "Page \(page)"
        }
        if let source = sources.first(where: { $0.id == item.sourceID }) {
            return source.name
        }
        return "Notice"
    }
}

// MARK: - Rich Role Breakdown Card

struct RoleBreakdownCard: View {
    let breakdown: AuditionRoleBreakdown
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                    Text(breakdown.name)
                        .font(.otSubhead.weight(.semibold))
                    Spacer(minLength: 4)
                    let tags = [breakdown.gender, breakdown.ageRange].compactMap { $0 }
                    if !tags.isEmpty {
                        Text(tags.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : OT.labelTertiary)
                    }
                }
                .foregroundStyle(isSelected ? Color.white : OT.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let desc = breakdown.description, !desc.isEmpty {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Text(desc)
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                } label: {
                    Text(isExpanded ? "Hide full description" : "View full role description")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : OT.labelSecondary)
                }
                .tint(isSelected ? .white : OT.accent)
            }
        }
        .padding(12)
        .background(isSelected ? OT.accent : OT.surfaceCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? Color.clear : OT.separator, lineWidth: 1))
    }
}

