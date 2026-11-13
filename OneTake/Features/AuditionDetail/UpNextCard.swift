import SwiftUI

struct UpNextCard: View {
    let audition: Audition
    @Environment(AppStore.self) private var store

    var body: some View {
        let next = audition.nextPiece
        VStack(alignment: .leading, spacing: OTSpace.m) {
            if next?.kind == .headshot {
                let isOpt = next?.isOptional ?? false
                OTSectionLabel(isOpt ? "Up next · Headshots (Optional)" : "Up next · Headshots")
                Text("Audition headshots").font(.otTitle)
                quoteLine(isOpt ? "Sent alongside your video tape as photos." : "Required in package · 3 photos (front, left, right profile).")
                HStack(spacing: OTSpace.s) {
                    let photoCount = HeadshotStore.taken(auditionID: audition.id).count
                    Button(photoCount == 0 ? "Add headshots" : "Manage headshots") {
                        store.push(.headshots(for: audition.id))
                    }
                    .buttonStyle(.otPrimary)

                    if isOpt {
                        Button("Skip for now") {
                            if let pieceID = next?.id {
                                store.markPieceDone(audition.id, pieceID: pieceID)
                                Haptics.tick()
                            }
                        }
                        .buttonStyle(.otSecondary)
                    }
                }
            } else if next?.kind == .slate || next?.kind == .fullLength {
                let isOpt = next?.isOptional ?? false
                let title = next?.kind == .slate ? "Slate" : "Full-body shot"
                OTSectionLabel(isOpt ? "Up next · \(title) (Optional)" : "Up next · \(title)")
                if next?.kind == .slate {
                    Text("Record the slate").font(.otTitle)
                    quoteLine(store.slate.spoken)
                } else {
                    Text("Full-body shot").font(.otTitle)
                    Text("Record a separate head-to-toe view, as requested.")
                        .font(.otCallout).foregroundStyle(OT.labelSecondary)
                }
                HStack(spacing: OTSpace.s) {
                    Button("Set up the camera") { store.push(.shootSetup(audition.id)) }
                        .buttonStyle(.otPrimary)
                    if isOpt {
                        Button(next?.kind == .slate ? "Skip slate" : "Skip full-body shot") {
                            if let pieceID = next?.id {
                                store.markPieceDone(audition.id, pieceID: pieceID)
                                Haptics.tick()
                            }
                        }
                        .buttonStyle(.otSecondary)
                    }
                }
            } else if let next, next.kind == .scene, let sceneIndex = audition.scenes.firstIndex(where: { $0.title == next.title }) {
                let scene = audition.scenes[sceneIndex]
                let isOpt = next.isOptional
                OTSectionLabel(isOpt ? "Up next · scene \(scene.number) of \(audition.scenes.count) (Optional)" : "Up next · scene \(scene.number) of \(audition.scenes.count)")
                Text(scene.title).font(.otTitle)
                Text(scene.heading).font(.otCaption).foregroundStyle(OT.labelTertiary)
                if let first = scene.lines.first(where: \.isMine) { quoteLine(first.text) }
                HStack(spacing: OTSpace.s) {
                    Button("Prepare scene \(scene.number)") { store.push(.prepare(audition.id, sceneIndex: sceneIndex)) }
                        .buttonStyle(.otPrimary)
                    Button("Practice") {
                        store.practicePiece(for: audition.id, sceneIndex: sceneIndex)
                        store.push(.runLines(audition.id, sceneIndex: sceneIndex))
                    }
                    .buttonStyle(.otSecondary)
                    if isOpt {
                        Button("Skip for now") {
                            store.markPieceDone(audition.id, pieceID: next.id)
                            Haptics.tick()
                        }
                        .buttonStyle(.otSecondary)
                    }
                }
            } else if next?.kind == .scene {
                OTSectionLabel("Up next · \(next?.title ?? "scene")")
                Text("Add your sides below").font(.otTitle)
                Text("Attach your script sides to prepare and shoot this scene.").font(.otCallout).foregroundStyle(OT.labelSecondary)
            } else {
                OTSectionLabel("Everything's in")
                Text("Watch it once, then send").font(.otTitle)
                Button("Review the package") { store.push(.package(audition.id)) }
                    .buttonStyle(.otPrimary)
            }
        }
        .padding(OTSpace.l)
        .otCard(.grouped)
    }

    private func quoteLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: OTSpace.s) {
            Capsule().fill(OT.accent).frame(width: 3) // ot-lint:allow
            Text(text).font(.otHeadline).foregroundStyle(OT.labelPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
