import SwiftUI
import AuthenticationServices
import UserNotifications

/// 01 Welcome → 03 Your slate (skippable) → straight into the app, as a guest.
/// No sign-in wall and no upfront camera/mic/notifications prompts: guest-first, and every
/// permission is asked for at the moment it's actually needed (the camera flows already request
/// access via `CameraController.requestAccess()` right when a shoot starts; notifications are
/// asked for the first time an audition with a due date is added). Sign-in is never offered here,
/// not even as an optional step: it's required only when sending as a private link (see
/// `PackageView`), and never to unlock recording or export.
struct OnboardingFlow: View {
    enum Step: Hashable { case slate }
    @Environment(AppStore.self) private var store
    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.slate) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .slate: SlateDetailsView { finish() }
                    }
                }
        }
    }

    private func finish() {
        // First run: Auditions shows the real empty state, "Add your first audition" — no sample project.
        store.auditions = []
        store.isOnboarded = true
    }
}

// MARK: - 01 Welcome

struct WelcomeView: View {
    var onStart: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("OneTake", systemImage: "movieclapper.fill")
                .font(.otHeadline).foregroundStyle(OT.labelPrimary)
                .padding(.top, 16)

            ScriptPreviewCard()
                .padding(.top, 28)

            Spacer()

            Text("Your best take,\nevery time.")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(OT.labelPrimary)
            Text("Learn your lines, tape with a real reader, and send it the way casting asks.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)
                .padding(.top, 10)

            Spacer().frame(height: 40)
            Button("Get started", action: onStart).buttonStyle(.otPrimary)
            Text("No account needed to start.").font(.otFootnote).foregroundStyle(OT.labelTertiary).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, OT.gutter + 4)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ScriptPreviewCard: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("INT. YOUR ROOM — TONIGHT").font(.otCaption.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                line("YOU", "I got the audition.", mine: true)
                line("READER", "Great. Send a tape by Friday.", mine: false)
                line("YOU", "Tonight. I'm ready.", mine: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .otCard(radius: 20)
            .rotationEffect(.degrees(-2))

            Label("SC 1 · TK 1", systemImage: "circle.fill")
                .font(.otCaption.weight(.bold)).foregroundStyle(.white)
                .labelStyle(RecLabelStyle())
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black, in: Capsule())
                .offset(x: 6, y: -12)
        }
        .padding(.horizontal, 24)
    }

    private func line(_ who: String, _ text: String, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(who).font(.otCaption.weight(.semibold)).foregroundStyle(OT.labelTertiary)
            HStack(spacing: 8) {
                if mine { Capsule().fill(OT.accent).frame(width: 3) }
                Text(text).font(mine ? .otHeadline : .otCallout)
                    .foregroundStyle(mine ? OT.labelPrimary : OT.labelSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RecLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7)).foregroundStyle(OT.recRed)
            configuration.title
        }
    }
}

// MARK: - 02 Sign in

/// "Sign in or create an account" — one screen for both: Apple and Google each sign a returning
/// person in and create an account for a new one. There's no email option: without a server there's
/// no way to verify an address, and an unverified account would be worse than none.
struct SignInView: View {
    /// Why sign-in is being asked for right now, shown under the title.
    var reason = "Back up your auditions and takes, and pick them up on any device."
    var onSignedIn: (Account) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in or create an account")
                    .font(.system(size: 40, weight: .bold)).tracking(-0.8)
                    .foregroundStyle(OT.labelPrimary)
                Text(reason).font(.otCallout).foregroundStyle(OT.labelSecondary)
            }
            .padding(.top, 4)

            VStack(spacing: 16) {
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    finish { try AccountAuth.account(from: result, previous: store.account) }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 54).clipShape(Capsule())

                Button {
                    working = true
                    Task {
                        let outcome: Result<Account, Error>
                        do { outcome = .success(try await AccountAuth.signInWithGoogle()) } catch { outcome = .failure(error) }
                        finish { try outcome.get() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        GoogleMark().frame(width: 18, height: 18)
                        Text("Continue with Google").font(.system(size: 17, weight: .semibold)).tracking(-0.4)
                    }
                    .foregroundStyle(OT.labelPrimary)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(OT.surfaceCard, in: Capsule())
                    .overlay(Capsule().strokeBorder(OT.separator, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(working || !AccountAuth.isGoogleConfigured)
                .opacity(AccountAuth.isGoogleConfigured ? 1 : 0.5)
            }
            .padding(.top, 28)

            if working { ProgressView().frame(maxWidth: .infinity).padding(.top, 16) }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.otFootnote).foregroundStyle(OT.danger).padding(.top, 16)
            }

            Text("New here? Either one creates your account. By continuing you agree to the Terms and Privacy Policy.")
                .font(.otCaption).foregroundStyle(OT.labelTertiary)
                .padding(.top, 20).padding(.horizontal, 4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .otCanvas()
    }

    private func finish(_ make: () throws -> Account) {
        working = false
        do {
            let account = try make()
            errorMessage = nil
            Haptics.success()
            onSignedIn(account)
        } catch AccountAuth.AuthError.cancelled {
            // Backed out of the Apple / Google sheet — nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Google's four-colour "G", drawn from its brand colours (no asset needed).
private struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let lineWidth = size.width * 0.2
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2
            func arc(_ from: Double, _ to: Double, _ color: Color) {
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
            }
            arc(-40, 45, Color(red: 0.26, green: 0.52, blue: 0.96))   // blue
            arc(45, 140, Color(red: 0.20, green: 0.66, blue: 0.33))   // green
            arc(140, 215, Color(red: 0.98, green: 0.74, blue: 0.02))  // yellow
            arc(215, 320, Color(red: 0.92, green: 0.26, blue: 0.21))  // red
            var bar = Path()
            bar.move(to: center)
            bar.addLine(to: CGPoint(x: rect.maxX + lineWidth / 2, y: center.y))
            context.stroke(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), lineWidth: lineWidth)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 03 Your slate

struct SlateDetailsView: View {
    var onContinue: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 16) {
            Text("How casting meets you").font(.otLargeTitle).foregroundStyle(OT.labelPrimary)
            Text("Said at the start of every tape. Tap a line to change it.")
                .font(.otCallout).foregroundStyle(OT.labelSecondary)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel(text: "Slate preview")
                    Spacer()
                    Label("≈ 0:05", systemImage: "waveform").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                }
                slateField($store.slate.name, hint: "from Apple Account")
                slateField($store.slate.height, hint: "height")
                slateField($store.slate.basedIn, hint: "based in")
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text("Representation").font(.otBody)
                        Text("Leave blank if you represent yourself").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                    }
                    Spacer()
                    Button("Add") {}.font(.otHeadline)
                }
            }
            .padding(20).otCard()

            Spacer()
            Button("Continue", action: onContinue).buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Skip", action: onContinue) } }
    }

    private func slateField(_ text: Binding<String>, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TextField("", text: text).font(.system(size: 28, weight: .bold))
            Text(hint).font(.otFootnote).foregroundStyle(OT.labelTertiary)
        }
    }
}

// Camera/mic permission is requested at the moment a shoot actually starts (see
// `CameraController.requestAccess()` in the Shoot/Headshot/Practice-take flows), and notification
// permission is requested the first time an audition with a due date is added (see
// `AddAuditionFlow`) — never upfront during onboarding. A decline here never costs setup progress.
