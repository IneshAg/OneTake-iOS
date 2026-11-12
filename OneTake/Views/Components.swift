import SwiftUI

// MARK: - Section label (v2/Section Label)

typealias SectionLabel = OTSectionLabel

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
        String(word.map { $0.isLetter || $0.isNumber ? "_" : $0 })
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
            if x > 0, x + spacing + size.width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + (x > 0 ? spacing : 0)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
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

typealias ProgressRing = OTProgressRing

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



// MARK: - Legacy aliases for design system migration

typealias ScheduleRow = OTScheduleRow
typealias InlineStatus = OTStatusLine
typealias SheetHeader = OTSheetHeader
typealias IconRow = OTIconRow

// MARK: - Headshot photo

struct HeadshotImage: View {
    /// Which of the actor's own headshots to show (`front`, `left`, `right`). Without one taken —
    /// or with no key — it's a neutral silhouette, never a stand-in photo of someone else.
    var realKey: String? = nil
    var auditionID: UUID? = nil
    var iconSize: CGFloat? = nil
    var onDark: Bool = false

    var body: some View {
        if let realKey, let real = HeadshotStore.load(key: realKey, auditionID: auditionID) {
            Color.clear
                .overlay {
                    Image(uiImage: real)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .contentShape(Rectangle())
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

// MARK: - Navigation components (legacy compatibility)

struct GlassBackButton: View {
    var label: String = "Back"
    var onDark: Bool = false
    var action: () -> Void

    var body: some View {
        OTIconButton("chevron.left", accessibilityLabel: label, action: action)
            .otSurface(onDark ? .camera : .standard)
    }
}

struct GlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var onDark = false
    var action: () -> Void

    var body: some View {
        OTIconButton(systemName, accessibilityLabel: accessibilityLabel, action: action)
            .otSurface(onDark ? .camera : .standard)
    }
}

struct GlassButtonCompatibility: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.7))
                .buttonStyle(OTPressStyle(.nav))
        } else {
            content.buttonStyle(.plain)
        }
    }
}

typealias InContentNavHeader = OTNavHeader

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

