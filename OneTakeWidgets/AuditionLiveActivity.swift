import ActivityKit
import SwiftUI
import WidgetKit

/// 22 · Live Activity (Lock Screen) and the Dynamic Island states beside it: compact countdown,
/// expanded, and uploading.
struct AuditionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AuditionActivityAttributes.self) { context in
            LockScreenActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(OT.cameraGlass)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            let state = context.state
            let left = otTimeLeft(until: context.attributes.due)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "movieclapper.fill").foregroundStyle(OT.due)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.project)
                        .font(.system(size: 17, weight: .semibold)).tracking(-0.4)
                        .foregroundStyle(.white).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let progress = state.uploadProgress {
                        Text("\(Int(progress * 100))%").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    } else {
                        Text("\(left.number)\(left.unit) left").font(.system(size: 17, weight: .semibold)).foregroundStyle(OT.due)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        PieceBar(pieces: state.pieces, spacing: 3, nextColor: OT.due, todoColor: OT.cameraGlass)
                        Text(state.uploadProgress != nil
                             ? "Uploading your tape to iCloud"
                             : "\(state.progressLine) · due \(context.attributes.due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                            .font(.system(size: 12)).foregroundStyle(OT.cameraLabel2).lineLimit(1)
                    }
                }
            } compactLeading: {
                if state.uploadProgress != nil {
                    Image(systemName: "arrow.up.circle.fill").foregroundStyle(OT.accent)
                } else {
                    Image(systemName: "movieclapper.fill").foregroundStyle(OT.due)
                }
            } compactTrailing: {
                if let progress = state.uploadProgress {
                    Text("\(Int(progress * 100))%").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text("\(left.number)\(left.unit)").font(.system(size: 13, weight: .semibold)).foregroundStyle(OT.due)
                }
            } minimal: {
                Image(systemName: state.uploadProgress != nil ? "arrow.up.circle.fill" : "movieclapper.fill")
                    .foregroundStyle(state.uploadProgress != nil ? OT.accent : OT.due)
            }
            .keylineTint(OT.accent)
            .widgetURL(context.attributes.url)
        }
    }
}

struct LockScreenActivityView: View {
    let attributes: AuditionActivityAttributes
    let state: AuditionActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(attributes.project)
                        .font(.system(size: 17, weight: .semibold)).tracking(-0.4)
                        .foregroundStyle(OT.cameraLabel).lineLimit(1)
                    Text("\(attributes.role) · due \(attributes.due.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(.system(size: 13)).tracking(-0.1).foregroundStyle(OT.cameraLabel2).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    if let progress = state.uploadProgress {
                        Text("\(Int(progress * 100))%").font(.system(size: 36, weight: .bold)).tracking(-0.8)
                        Text("sent").font(.system(size: 13)).foregroundStyle(OT.cameraLabel2)
                    } else if attributes.due > .now {
                        // Ticks down live without the app updating it.
                        Text(timerInterval: Date.now...attributes.due, countsDown: true)
                            .font(.system(size: 36, weight: .bold)).tracking(-0.8).monospacedDigit()
                            .multilineTextAlignment(.trailing).frame(maxWidth: 150, alignment: .trailing)
                        Text("left").font(.system(size: 13)).foregroundStyle(OT.cameraLabel2)
                    } else {
                        Text("Due now").font(.system(size: 20, weight: .bold))
                    }
                }
                .foregroundStyle(OT.cameraLabel)
            }
            PieceBar(pieces: state.pieces, spacing: 3, nextColor: OT.accent.opacity(0.45), todoColor: OT.cameraStroke)
            Text(state.uploadProgress != nil ? "Uploading your tape to iCloud" : state.progressLine)
                .font(.system(size: 13)).tracking(-0.1).foregroundStyle(OT.cameraLabel2).lineLimit(1)
        }
        .padding(16)
    }
}
