import SwiftUI

enum HeadshotAngle: String, CaseIterable, Identifiable, Sendable {
    case front
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: return "Front"
        case .left: return "Left profile"
        case .right: return "Right profile"
        }
    }
}

struct PhotoSourceMenu: View {
    var auditionID: Audition.ID?
    var size: OTControlSize = .medium
    var onPick: (HeadshotAngle) -> Void

    init(auditionID: Audition.ID? = nil, size: OTControlSize = .medium, onPick: @escaping (HeadshotAngle) -> Void) {
        self.auditionID = auditionID
        self.size = size
        self.onPick = onPick
    }

    var body: some View {
        OTMenuButton(
            "Photos",
            systemImage: "photo.on.rectangle",
            size: size
        ) {
            ForEach(HeadshotAngle.allCases) { angle in
                Button {
                    onPick(angle)
                } label: {
                    Label(
                        angle.title,
                        systemImage: HeadshotStore.exists(key: angle.rawValue, auditionID: auditionID)
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                }
            }
        }
    }
}
