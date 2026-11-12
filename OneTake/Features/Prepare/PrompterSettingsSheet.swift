import SwiftUI
import OneTakeUI

// MARK: - 11.2 Teleprompter settings

struct PrompterSettingsSheet: View {
    @AppStorage("prompter.size") private var size = 1
    @AppStorage("prompter.followVoice") private var followVoice = true
    /// Off by default: mirrored text only makes sense behind a beam-splitter mirror rig
    @AppStorage("prompter.mirror") private var mirror = false

    var body: some View {
        VStack(alignment: .leading, spacing: OTSpace.l) {
            Text("Teleprompter").font(.otHeadline)
            Text("Because every time I tried")
                .font(.system(size: [18, 26, 38][min(max(size, 0), 2)], weight: .semibold)) // ot-lint:allow
                .foregroundStyle(Color.white) // ot-lint:allow
                .frame(maxWidth: .infinity, minHeight: 72) // ot-lint:allow
                .background(Color.black, in: RoundedRectangle(cornerRadius: OTRadius.l, style: .continuous)) // ot-lint:allow
                .scaleEffect(x: mirror ? -1 : 1, y: 1)

            OTSectionLabel("Text size")
            Picker("Size", selection: $size) {
                Text("Regular").tag(0)
                Text("Big").tag(1)
                Text("Huge").tag(2)
            }
            .pickerStyle(.segmented)

            OTSectionLabel("Scroll")
            Picker("Scroll", selection: $followVoice) {
                Text("Follows my voice").tag(true)
                Text("Continuous").tag(false)
            }
            .pickerStyle(.segmented)

            DisclosureGroup("Advanced teleprompter options") {
                Toggle("Mirror text for teleprompter glass", isOn: $mirror)
                Text("Turn this on only when using a beam-splitter teleprompter attachment over the lens.")
                    .font(.otCaption).foregroundStyle(OT.labelSecondary)
            }
        }
        .padding(OTSpace.gutter)
    }
}
