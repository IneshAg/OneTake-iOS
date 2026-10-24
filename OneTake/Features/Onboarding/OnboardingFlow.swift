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

struct SignInView: View {
    /// Why sign-in is being asked for right now, shown under the title.
    var reason = "Your auditions, reader tracks and takes, on every device you own."
    var onContinue: () -> Void
    @State private var email = ""
    @Environment(\.colorScheme) private var colorScheme

    /// Sign-in gates link sharing, so only a real result counts — a cancelled Apple sheet or an
    /// empty email field must not sign anyone in.
    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        return trimmed[trimmed.index(after: at)...].contains(".")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sign in or create an account").font(.otLargeTitle).foregroundStyle(OT.labelPrimary)
            Text(reason)
                .font(.otCallout).foregroundStyle(OT.labelSecondary)

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                if case .success = result { onContinue() }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52).clipShape(Capsule())
            .padding(.top, 8)

            HStack { line; Text("or").font(.otFootnote).foregroundStyle(OT.labelTertiary); line }

            Text("Email").font(.otFootnote.weight(.semibold)).foregroundStyle(OT.labelSecondary)
            TextField("you@example.com", text: $email)
                .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                .padding(.horizontal, 16).frame(height: 52)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button("Continue with email", action: onContinue).buttonStyle(.otSecondary)
                .disabled(!isValidEmail)

            Label("Takes stay on this iPhone until you send them.", systemImage: "lock.fill")
                .font(.otFootnote).foregroundStyle(OT.labelSecondary)
            Spacer()
        }
        .padding(.horizontal, OT.gutter)
        .otCanvas()
    }

    private var line: some View { Rectangle().fill(OT.separator).frame(height: 1) }
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
                slateField($store.slate.name, placeholder: "Your name", hint: "name")
                    .textContentType(.name)
                slateField($store.slate.height, placeholder: "5′ 9″", hint: "height")
                slateField($store.slate.basedIn, placeholder: "City", hint: "based in")
                    .textContentType(.addressCity)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Representation").font(.otBody)
                    TextField("Leave blank if you represent yourself", text: $store.slate.representation)
                        .font(.otCallout)
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

    private func slateField(_ text: Binding<String>, placeholder: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TextField(placeholder, text: text).font(.system(size: 28, weight: .bold))
            Text(hint).font(.otFootnote).foregroundStyle(OT.labelTertiary)
        }
    }
}

// Camera/mic permission is requested at the moment a shoot actually starts (see
// `CameraController.requestAccess()` in the Shoot/Headshot/Practice-take flows), and notification
// permission is requested the first time an audition with a due date is added (see
// `AddAuditionFlow`) — never upfront during onboarding. A decline here never costs setup progress.
