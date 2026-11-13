import SwiftUI
import AuthenticationServices
import UserNotifications

/// 01 Welcome → 03 Your slate (skippable) → straight into the app, as a guest.
struct OnboardingFlow: View {
    enum Step: Hashable { case slate }
    @Environment(AppStore.self) private var store
    @State private var path: [Step] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.slate) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .slate: SlateDetailsView(onBack: { path = [] }, onContinue: { finish() })
                    }
                }
        }
    }

    private func finish() {
        store.isOnboarded = true
    }
}

// MARK: - 01 Welcome

struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("OneTake", systemImage: "movieclapper.fill")
                .font(.otHeadline)
                .foregroundStyle(OT.labelPrimary)
                .padding(.top, OTSpace.m)

            ScriptPreviewCard()
                .padding(.top, OTSpace.l)

            Spacer()

            Text("Your best take,\nevery time.")
                .font(.system(size: 40, weight: .bold)) // ot-lint:allow
                .foregroundStyle(OT.labelPrimary)
            Text("Learn your lines, tape with a real reader, and send it the way casting asks.")
                .font(.otCallout)
                .foregroundStyle(OT.labelSecondary)
                .padding(.top, OTSpace.s)

            Spacer().frame(height: 40) // ot-lint:allow

            Button("Get started", action: onStart)
                .buttonStyle(.otPrimary)
        }
        .padding(.horizontal, OTSpace.gutter)
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
        .navigationBarBackButtonHidden(true)
    }
}

private struct ScriptPreviewCard: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: OTSpace.s) {
                Text("INT. YOUR ROOM — TONIGHT")
                    .font(.otCaption.weight(.semibold))
                    .foregroundStyle(OT.labelTertiary)
                line("YOU", "I got the audition.", mine: true)
                line("READER", "Great. Send a tape by Friday.", mine: false)
                line("YOU", "Tonight. I'm ready.", mine: true)
            }
            .padding(OTSpace.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .otCard(.grouped)
            .rotationEffect(.degrees(-2))

            Label("SC 1 · TK 1", systemImage: "circle.fill")
                .font(.otCaption.weight(.bold))
                .foregroundStyle(.white)
                .labelStyle(RecLabelStyle())
                .padding(.horizontal, 10) // ot-lint:allow
                .padding(.vertical, 6) // ot-lint:allow
                .background(.black, in: Capsule())
                .offset(x: 6, y: -12) // ot-lint:allow
        }
        .padding(.horizontal, OTSpace.xl)
    }

    private func line(_ who: String, _ text: String, mine: Bool) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.xxs) {
            Text(who).font(.otCaption.weight(.semibold)).foregroundStyle(OT.labelTertiary)
            HStack(spacing: OTSpace.s) {
                if mine { Capsule().fill(OT.accent).frame(width: 3) // ot-lint:allow
                }
                Text(text).font(mine ? .otHeadline : .otCallout)
                    .foregroundStyle(mine ? OT.labelPrimary : OT.labelSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct RecLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { // ot-lint:allow
            configuration.icon.font(.system(size: 7)) // ot-lint:allow
                .foregroundStyle(OT.recRed)
            configuration.title
        }
    }
}

// MARK: - 02 Sign in

struct SignInView: View {
    var reason = "Back up your auditions and takes, and pick them up on any device."
    var onSignedIn: (Account) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                Text("Sign in or create an account")
                    .font(.system(size: 40, weight: .bold)) // ot-lint:allow
                    .tracking(-0.8)
                    .foregroundStyle(OT.labelPrimary)
                Text(reason).font(.otCallout).foregroundStyle(OT.labelSecondary)
            }
            .padding(.top, OTSpace.xs)

            VStack(spacing: OTSpace.m) {
                if AccountAuth.isAppleConfigured {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        finish { try AccountAuth.account(from: result, previous: store.account) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 54) // ot-lint:allow
                    .clipShape(Capsule())
                } else {
                    unavailableProviderRow(symbol: "apple.logo", title: "Continue with Apple")
                }

                Button {
                    working = true
                    Task {
                        let outcome: Result<Account, Error>
                        do { outcome = .success(try await AccountAuth.signInWithGoogle()) } catch { outcome = .failure(error) }
                        finish { try outcome.get() }
                    }
                } label: {
                    HStack(spacing: OTSpace.s) {
                        GoogleMark().frame(width: 18, height: 18) // ot-lint:allow
                        Text("Continue with Google")
                            .font(.system(size: 17, weight: .semibold)) // ot-lint:allow
                            .tracking(-0.4)
                    }
                    .foregroundStyle(OT.labelPrimary)
                    .frame(maxWidth: .infinity, minHeight: 50) // ot-lint:allow
                }
                .buttonStyle(.ot(.secondary, size: .large))
                .disabled(working || !AccountAuth.isGoogleConfigured)
                .opacity(AccountAuth.isGoogleConfigured ? 1 : 0.5)

                if !AccountAuth.canSignIn {
                    VStack(alignment: .leading, spacing: 6) { // ot-lint:allow
                        Label("Sign-in isn't available in this build", systemImage: "info.circle")
                            .font(.otFootnote.weight(.semibold))
                            .foregroundStyle(OT.labelSecondary)
                        Text("Apple sign-in needs a paid Apple Developer account, and Google needs OAuth credentials. Everything else in OneTake works as a guest; only sending a tape as a link needs an account.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OTSpace.m)
                    .otCard(.grouped)
                }
            }
            .padding(.top, 120) // ot-lint:allow

            if working {
                ProgressView().frame(maxWidth: .infinity).padding(.top, OTSpace.m)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.otFootnote)
                    .foregroundStyle(OT.danger)
                    .padding(.top, OTSpace.m)
            }

            Text(AccountAuth.canSignIn
                 ? "New here? Either one creates your account. By continuing you agree to the Terms and Privacy Policy."
                 : "By continuing you agree to the Terms and Privacy Policy.")
                .font(.otCaption)
                .foregroundStyle(OT.labelTertiary)
                .padding(.top, OTSpace.l)
                .padding(.horizontal, OTSpace.xs)
                Spacer()
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .otCanvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func unavailableProviderRow(symbol: String, title: String) -> some View {
        HStack(spacing: OTSpace.s) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium)) // ot-lint:allow
            Text(title)
                .font(.system(size: 17, weight: .semibold)) // ot-lint:allow
                .tracking(-0.4)
            Text("Unavailable")
                .font(.otCaption.weight(.semibold))
                .padding(.horizontal, OTSpace.s)
                .padding(.vertical, 3) // ot-lint:allow
                .background(OT.separator.opacity(0.5), in: Capsule())
        }
        .foregroundStyle(OT.labelSecondary)
        .frame(maxWidth: .infinity, minHeight: 50) // ot-lint:allow
        .otCard(.grouped)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). Unavailable in this build.")
    }

    private func finish(_ make: () throws -> Account) {
        working = false
        do {
            let account = try make()
            errorMessage = nil
            Haptics.success()
            onSignedIn(account)
        } catch AccountAuth.AuthError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

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
            arc(-40, 45, Color(red: 0.26, green: 0.52, blue: 0.96)) // ot-lint:allow
            arc(45, 140, Color(red: 0.20, green: 0.66, blue: 0.33)) // ot-lint:allow
            arc(140, 215, Color(red: 0.98, green: 0.74, blue: 0.02)) // ot-lint:allow
            arc(215, 320, Color(red: 0.92, green: 0.26, blue: 0.21)) // ot-lint:allow
            var bar = Path()
            bar.move(to: center)
            bar.addLine(to: CGPoint(x: rect.maxX + lineWidth / 2, y: center.y))
            context.stroke(bar, with: .color(Color(red: 0.26, green: 0.52, blue: 0.96)), lineWidth: lineWidth) // ot-lint:allow
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 03 Your slate

struct SlateDetailsView: View {
    var onBack: (() -> Void)? = nil
    var onContinue: () -> Void
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: OTSpace.m) {
                Text("How casting meets you")
                    .font(.otLargeTitle)
                    .foregroundStyle(OT.labelPrimary)
                Text("Said at the start of every tape. Tap a line to change it.")
                    .font(.otCallout)
                    .foregroundStyle(OT.labelSecondary)

                VStack(alignment: .leading, spacing: OTSpace.m) {
                    HStack {
                        OTSectionLabel("Slate preview")
                        Spacer()
                        Label("≈ 0:05", systemImage: "waveform")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelTertiary)
                    }
                    slateField($store.slate.name, placeholder: "Your name", hint: "name")
                        .textContentType(.name)
                    slateField($store.slate.height, placeholder: "5′ 9″", hint: "height")
                    slateField($store.slate.basedIn, placeholder: "City", hint: "based in")
                        .textContentType(.addressCity)
                    Divider()
                    VStack(alignment: .leading, spacing: OTSpace.xxs) {
                        Text("Representation").font(.otBody)
                        TextField("Leave blank if you represent yourself", text: $store.slate.representation)
                            .font(.otCallout)
                    }
                }
                .padding(OTSpace.l)
                .otCard(.grouped)
            }
            .padding(.horizontal, OTSpace.gutter)
            .padding(.top, OTSpace.s)
            .padding(.bottom, OTSpace.xl)
        }
        .otCanvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Skip", action: onContinue)
            }
        }
        .otBottomBar {
            Button("Continue", action: onContinue)
                .buttonStyle(.otPrimary)
        }
    }

    private func slateField(_ text: Binding<String>, placeholder: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            TextField(placeholder, text: text)
                .font(.system(size: 28, weight: .bold)) // ot-lint:allow
            Text(hint)
                .font(.otFootnote)
                .foregroundStyle(OT.labelTertiary)
        }
    }
}
