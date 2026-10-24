import SwiftUI
import WidgetKit

// MARK: - Timeline

struct NextAuditionEntry: TimelineEntry {
    let date: Date
    /// Soonest unsent audition, and the one after it (for the medium widget's "Then ·" line).
    let next: WidgetSnapshot.Item?
    let then: WidgetSnapshot.Item?
    let relevance: TimelineEntryRelevance?
}

struct NextAuditionProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextAuditionEntry {
        NextAuditionEntry(date: .now, next: .preview, then: nil, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextAuditionEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now, from: WidgetSnapshot.load()))
    }

    /// One entry an hour for the next day, so "13h" keeps counting down without the app running.
    /// The app reloads timelines whenever its data changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextAuditionEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date.now
        let entries = (0..<24).map { entry(at: now.addingTimeInterval(Double($0) * 3600), from: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, from snapshot: WidgetSnapshot?) -> NextAuditionEntry {
        let upcoming = (snapshot?.upcoming ?? []).filter { $0.due > date }
        let next = upcoming.first
        // Smart Stack: the closer the deadline, the more relevant this widget is.
        let relevance = next.map { TimelineEntryRelevance(score: Float(max(0, 72 - $0.due.timeIntervalSince(date) / 3600))) }
        return NextAuditionEntry(date: date, next: next, then: upcoming.dropFirst().first, relevance: relevance)
    }
}

// MARK: - Widget

struct NextAuditionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextAudition", provider: NextAuditionProvider()) { entry in
            NextAuditionWidgetView(entry: entry)
        }
        .configurationDisplayName("Next audition")
        .description("How long until your next tape is due, and what's left to shoot.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NextAuditionWidgetView: View {
    let entry: NextAuditionEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let next = entry.next {
                switch family {
                case .systemMedium:         medium(next)
                case .accessoryRectangular: lockScreen(next)
                default:                    small(next)
                }
            } else {
                empty
            }
        }
        .widgetURL(entry.next?.url)
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular { AccessoryWidgetBackground() } else { OT.surfaceCard }
        }
    }

    // 23 · Widget · small
    private func small(_ item: WidgetSnapshot.Item) -> some View {
        let left = otTimeLeft(until: item.due, from: entry.date)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Due in")
                .font(.system(size: 12, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                .foregroundStyle(OT.due)
            TimeLeft(number: left.number, unit: left.unit, numberSize: 52, unitSize: 20)
            Text(item.project)
                .font(.system(size: 15, weight: .semibold)).tracking(-0.2)
                .foregroundStyle(OT.labelPrimary).lineLimit(1)
            HStack(spacing: 6) {
                ReadinessDots(pieces: item.pieces)
                Text("\(item.readyCount) of \(item.pieces.count)")
                    .font(.system(size: 12)).foregroundStyle(OT.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 23 · Widget · medium
    private func medium(_ item: WidgetSnapshot.Item) -> some View {
        let left = otTimeLeft(until: item.due, from: entry.date)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("NEXT UP")
                        .font(.system(size: 13, weight: .semibold)).tracking(0.6)
                        .foregroundStyle(OT.labelTertiary).padding(.horizontal, 4)
                    Text(item.project)
                        .font(.system(size: 17, weight: .semibold)).tracking(-0.4)
                        .foregroundStyle(OT.labelPrimary).lineLimit(1)
                    Text(item.due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.system(size: 13)).tracking(-0.1).foregroundStyle(OT.labelSecondary)
                }
                Spacer(minLength: 8)
                TimeLeft(number: left.number, unit: left.unit, numberSize: 44, unitSize: 17)
            }
            PieceBar(pieces: item.pieces, showLabels: true)
            if let then = entry.then {
                Text("Then · \(then.project) · \(then.due.formatted(.dateTime.weekday(.abbreviated)))")
                    .font(.system(size: 12)).foregroundStyle(OT.labelTertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 23 · Lock Screen · rectangular
    private func lockScreen(_ item: WidgetSnapshot.Item) -> some View {
        let left = otTimeLeft(until: item.due, from: entry.date)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(left.number)\(left.unit) · \(item.project)")
                .font(.system(size: 13, weight: .semibold)).tracking(-0.1).lineLimit(1)
            Text(item.progressLine)
                .font(.system(size: 11, weight: .semibold)).tracking(0.06)
                .foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "movieclapper.fill").foregroundStyle(OT.accent)
            Text("No auditions due").font(.system(size: 15, weight: .semibold)).foregroundStyle(OT.labelPrimary)
            if family != .accessoryRectangular {
                Text("Add one in OneTake").font(.system(size: 12)).foregroundStyle(OT.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Pieces

/// "13 h" in the due colour, baseline-aligned like the design.
struct TimeLeft: View {
    let number: String
    let unit: String
    let numberSize: CGFloat
    let unitSize: CGFloat
    var color: Color = OT.due

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(number).font(.system(size: numberSize, weight: .bold)).tracking(-0.8).monospacedDigit()
            Text(unit).font(.system(size: unitSize, weight: .semibold)).tracking(-0.4)
        }
        .foregroundStyle(color)
    }
}

/// One dot per piece: filled when done, half-tone for the next one, outlined still to do.
struct ReadinessDots: View {
    let pieces: [WidgetSnapshot.Piece]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(pieces.prefix(8).enumerated()), id: \.offset) { _, piece in
                switch piece.status {
                case .done: Circle().fill(OT.accent).frame(width: 7, height: 7)
                case .next: Circle().fill(OT.accent.opacity(0.45)).frame(width: 7, height: 7)
                case .todo: Circle().strokeBorder(OT.labelTertiary, lineWidth: 1.2).frame(width: 7, height: 7)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pieces.filter { $0.status == .done }.count) of \(pieces.count) ready")
    }
}

/// The tape in order — one segment per piece, labelled underneath in the medium widget.
struct PieceBar: View {
    let pieces: [WidgetSnapshot.Piece]
    var showLabels = false
    var spacing: CGFloat = 4
    var doneColor: Color = OT.accent
    var nextColor: Color = OT.accent.opacity(0.4)
    var todoColor: Color = OT.fillQuiet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: spacing) {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    RoundedRectangle(cornerRadius: 3).fill(color(piece.status)).frame(height: 6)
                }
            }
            if showLabels {
                HStack(spacing: spacing) {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                        Text(piece.title)
                            .font(.system(size: 12, weight: piece.status == .next ? .semibold : .regular))
                            .foregroundStyle(piece.status == .next ? OT.accent : piece.status == .done ? OT.labelSecondary : OT.labelTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func color(_ status: WidgetSnapshot.Piece.Status) -> Color {
        switch status {
        case .done: doneColor
        case .next: nextColor
        case .todo: todoColor
        }
    }
}

extension WidgetSnapshot.Item {
    /// Placeholder / gallery preview only — never shown as real data.
    static var preview: WidgetSnapshot.Item {
        WidgetSnapshot.Item(id: UUID(), project: "The Last Summer", role: "Arjun", due: .now.addingTimeInterval(13 * 3600), pieces: [
            .init(title: "Headshot", status: .done), .init(title: "Slate", status: .done),
            .init(title: "Scene 1", status: .next), .init(title: "Scene 2", status: .todo)
        ])
    }
}

#Preview(as: .systemSmall) { NextAuditionWidget() } timeline: {
    NextAuditionEntry(date: .now, next: .preview, then: nil, relevance: nil)
}

#Preview(as: .systemMedium) { NextAuditionWidget() } timeline: {
    NextAuditionEntry(date: .now, next: .preview, then: nil, relevance: nil)
}
