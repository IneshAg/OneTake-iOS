import SwiftUI
import OneTakeUI

// MARK: - Post-Take & Slate Done Overlays

extension ShootFlow {
    @ViewBuilder
    func slateDoneOverlay(for a: Audition) -> some View {
        if isAnalyzingSlate {
            VStack(spacing: OTSpace.s) {
                ProgressView().tint(.white)
                Text("Checking for long silent edges…")
                    .font(.otCallout)
                    .foregroundStyle(Color.white) // ot-lint:allow
            }
            .padding(OTSpace.cardInset)
            .background(OT.cameraGlass, in: RoundedRectangle(cornerRadius: OTRadius.card))
        } else {
            let hasPreview = store.currentPath.contains {
                if case .preview(let id) = $0, id == auditionID { return true }
                return false
            }
            resultCard(
                title: "Slate’s done.",
                detail: "\(Int(camera.elapsed)) s · saved · opens every scene in \(a.project)",
                primary: slateDonePrimaryAction(for: a),
                secondary: ("Redo slate", { stage = .slate }),
                more: [("Review slate by itself", { finish(goTo: .elementReview(a.id, element: .slate)) })]
                    + (hasPreview ? [("Check the tape", { finish(goTo: .tapeCheck(a.id)) })] : [])
            )
        }
    }

    func slateDonePrimaryAction(for a: Audition) -> (String, () -> Void) {
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasPreview {
            return ("Back to preview", { finish(goTo: .preview(a.id)) })
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasTapeCheck {
            return ("Back to tape check", { finish(goTo: .tapeCheck(a.id)) })
        }
        if let next = nextCameraFlowPiece(in: store.audition(a.id) ?? a) {
            switch next.kind {
            case .fullLength:
                return ("Next: full-body shot", { stage = .fullLength })
            case .scene:
                if let nextScene = a.scenes.firstIndex(where: { $0.title == next.title }) {
                    return ("Next: \(next.title)", { moveToScene(nextScene) })
                }
            case .headshot:
                return ("Add headshots", { finish(goTo: .headshots(for: a.id)) })
            case .slate:
                return ("Continue to slate", { stage = .slate })
            }
        }
        if let unshot = nextUnshotScene(in: a) {
            return ("Next: \(a.scenes[unshot].title)", { moveToScene(unshot) })
        }
        return ("Check the tape", { finish(goTo: .tapeCheck(a.id)) })
    }

    func isSceneOptional(title: String, in a: Audition) -> Bool {
        for piece in a.pieces {
            if piece.kind == .scene && piece.title == title {
                return piece.isOptional
            }
        }
        return false
    }

    func requiresSeparateFullBodyShot(_ audition: Audition) -> Bool {
        audition.pieces.contains { $0.kind == .fullLength }
            || audition.asks.contains("Full length")
    }

    func savedPrimaryAction(for a: Audition) -> (String, () -> Void) {
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasPreview {
            return ("Back to preview", { finish(goTo: .preview(a.id)) })
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }
        if hasTapeCheck {
            return ("Back to tape check", { finish(goTo: .tapeCheck(a.id)) })
        }
        return ("Review takes", { finish(goTo: .takes(a.id, sceneIndex: sceneIndex)) })
    }

    @ViewBuilder
    func savedOverlay(for a: Audition) -> some View {
        let hasPreview = store.currentPath.contains {
            if case .preview(let id) = $0, id == auditionID { return true }
            return false
        }
        let hasTapeCheck = store.currentPath.contains {
            if case .tapeCheck(let id) = $0, id == auditionID { return true }
            return false
        }

        if let next = nextUnshotScene(in: a) {
            let nextTitle = a.scenes[next].title
            let isOpt = isSceneOptional(title: nextTitle, in: a)
            let primaryTitle = isOpt ? "Next: \(nextTitle) (Optional)" : "Next: \(nextTitle)"
            let moreActions: [(String, () -> Void)] = [
                ("Review this scene by itself", { finish(goTo: .elementReview(a.id, element: .scene(sceneIndex))) }),
                ("Watch take \(takeNumber)", { finish(goTo: .takes(a.id, sceneIndex: sceneIndex)) }),
                hasPreview ? ("Back to preview", { finish(goTo: .preview(a.id)) }) : nil,
                hasTapeCheck ? ("Back to tape check", { finish(goTo: .tapeCheck(a.id)) }) : nil,
                ("Done for now", { finish(goTo: nil) })
            ].compactMap { $0 }

            resultCard(
                title: "Take \(takeNumber), in the can.",
                detail: "\(Int(camera.elapsed)) s · \(nextTitle) is still to shoot",
                primary: (primaryTitle, { moveToScene(next) }),
                secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                more: moreActions
            )
        } else {
            resultCard(
                title: "Take \(takeNumber), in the can.",
                detail: "\(Int(camera.elapsed)) s · saved on this iPhone",
                primary: savedPrimaryAction(for: a),
                secondary: ("Go again", { lineIndex = 0; stage = .scene }),
                more: [
                    ("Review this scene by itself", { finish(goTo: .elementReview(a.id, element: .scene(sceneIndex))) }),
                    ("Check the tape", { finish(goTo: .tapeCheck(a.id)) }),
                    ("Done for now", { finish(goTo: nil) })
                ]
            )
        }
    }
}
