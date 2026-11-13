import SwiftUI

/// Export finishes here: the selected deliverable is ready to hand off.
struct DeliveryReadyView: View {
    let audition: Audition
    let destination: Destination
    let deliverable: PackageDeliverable
    var onShare: () -> Void
    var onBack: () -> Void

    @State private var copiedNoticeToast: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.l) {
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44)) // ot-lint:allow
                        .foregroundStyle(OT.success)
                    Text("Your tape is ready.").font(.otLargeTitle)
                    Text(readySubtitle)
                        .font(.otSubhead)
                        .foregroundStyle(OT.labelSecondary)
                }
                .padding(.top, OTSpace.m)

                // Deliverable Summary Card
                VStack(alignment: .leading, spacing: OTSpace.s) {
                    HStack(spacing: OTSpace.m) {
                        Image(systemName: deliverable.icon)
                            .font(.system(size: 24, weight: .semibold)) // ot-lint:allow
                            .foregroundStyle(OT.accent)
                        VStack(alignment: .leading, spacing: OTSpace.xxs) {
                            Text(deliverable.rawValue)
                                .font(.otHeadline)
                            Text(deliverable.subtitle)
                                .font(.otCaption)
                                .foregroundStyle(OT.labelSecondary)
                        }
                        Spacer()
                    }

                    Divider()

                    HStack {
                        Label(destination.rawValue, systemImage: destination.icon)
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.labelPrimary)
                        Spacer()
                        if destination == .email, let email = audition.castingEmail {
                            Text(email).font(.otCaption).foregroundStyle(OT.accent)
                        }
                    }
                }
                .otCard(.grouped)

                // Primary Action Button
                Button {
                    onShare()
                } label: {
                    Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                        .font(.otHeadline)
                }
                .buttonStyle(.otPrimary)

                // Change choices by returning to package review; alternate formats aren't
                // generated behind the scenes and must not silently change what gets shared.
                VStack(spacing: OTSpace.s) {
                    Button("Change format or destination", action: onBack)
                        .buttonStyle(.otSecondary)

                    if destination == .email {
                        Button {
                            let text = audition.emailBody(slate: SlateInfo())
                            UIPasteboard.general.string = text
                            copiedNoticeToast = true
                            Haptics.tick()
                            Task {
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                copiedNoticeToast = false
                            }
                        } label: {
                            HStack {
                                Label(
                                    copiedNoticeToast ? "Copied Cover Letter!" : "Copy Cover Letter Text",
                                    systemImage: copiedNoticeToast ? "checkmark" : "doc.on.doc"
                                )
                                Spacer()
                            }
                        }
                        .buttonStyle(.ot(.secondary, size: .medium))
                    }
                }

                Spacer(minLength: OTSpace.l)

                Button("Back to package", action: onBack)
                    .buttonStyle(.otSecondary)
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .navigationBarBackButtonHidden(true)
    }

    private var readySubtitle: String {
        switch destination {
        case .email:
            return "Prepared for direct email to \(audition.castingOffice.isEmpty ? "casting" : audition.castingOffice)."
        case .localFiles:
            return "Ready to save to your iPhone Files or AirDrop to your computer."
        case .actorsAccess:
            return "Formatted for Actors Access Eco Cast submission."
        case .backstage:
            return "Formatted for Backstage application upload."
        case .castingNetworks:
            return "Formatted for Casting Networks submission."
        case .spotlight:
            return "Formatted for Spotlight submission."
        case .emailOrLink:
            return "Hosted and ready to share via link."
        }
    }

    private var primaryButtonTitle: String {
        switch destination {
        case .email: return "Send via Email"
        case .localFiles: return "Save to Files / AirDrop"
        default: return "Share \(deliverable.shortTitle)"
        }
    }

    private var primaryButtonIcon: String {
        switch destination {
        case .email: return "envelope.fill"
        case .localFiles: return "folder.fill"
        default: return "square.and.arrow.up"
        }
    }
}
