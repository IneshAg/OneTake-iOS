import SwiftUI
import AuthenticationServices
import UserNotifications

/// Introduces OneTake before entering the app as a guest.
struct OnboardingFlow: View {
    var onFinish: () -> Void
    @Environment(AppStore.self) private var store
    @State private var showTour = false

    var body: some View {
        NavigationStack {
            WelcomeView { showTour = true }
                .navigationDestination(isPresented: $showTour) {
                    OnboardingTour(
                        onFinish: finish
                    )
                }
        }
    }

    private func finish() {
        store.tab = .auditions
        store.auditionsPath.removeAll()
        store.isOnboarded = true
        store.flushPersistence()
        onFinish()
    }
}

// MARK: - 01 Welcome

private struct WelcomeView: View {
    var onStart: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 64.0
    @ScaledMetric(relativeTo: .title2) private var taglineSize = 24.0

    var body: some View {
        VStack(spacing: 6) {
            Text("OneTake")
                .font(.system(size: titleSize, weight: .bold)) // ot-lint:allow
                .tracking(-2)
                .accessibilityAddTraits(.isHeader)

            Text("From first take to final cut")
                .font(.system(size: taglineSize, weight: .bold)) // ot-lint:allow
        }
        .foregroundStyle(.black)
        .multilineTextAlignment(.center)
        .padding(.horizontal, OTSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            Button("Continue", action: onStart)
                .buttonStyle(.otPrimary)
                .padding(.horizontal, OTSpace.xl)
                .padding(.bottom, OTSpace.xl)
        }
        .background {
            GeometryReader { geometry in
                Image("OnboardingFilmstrip")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
    }
}

// MARK: - Feature tour

private struct OnboardingTour: View {
    private enum Page: Int, CaseIterable {
        case auditions, recording, rehearsal

        var image: String {
            switch self {
            case .auditions: "OnboardingAuditions"
            case .recording: "OnboardingRecording"
            case .rehearsal: "OnboardingRehearsal"
            }
        }

        var title: String {
            switch self {
            case .auditions: "Auditions\ndone right."
            case .recording: "Your take.\nOn your terms."
            case .rehearsal: "From first line\nto final take"
            }
        }

        var detail: String {
            switch self {
            case .auditions: "Create headshots, slates and scenes with professional tools built for actors"
            case .recording: "Check your framing, lighting and sound so every take feels studio ready"
            case .rehearsal: "Rehearse with guided practice designed to make every dialogue feel effortless"
            }
        }
    }

    var onFinish: () -> Void
    @State private var selection = Page.auditions
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 48.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let canvas = Color(red: 250 / 255, green: 248 / 255, blue: 244 / 255) // ot-lint:allow
    private let ink = Color(red: 22 / 255, green: 20 / 255, blue: 22 / 255) // ot-lint:allow

    var body: some View {
        GeometryReader { geometry in
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.bottom
            let heroHeight = fullHeight * (dynamicTypeSize.isAccessibilitySize ? 0.40 : 0.57)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Page.allCases, id: \.self) { page in
                        pageContent(page, heroHeight: heroHeight)
                            .containerRelativeFrame(.horizontal)
                            .frame(height: geometry.size.height)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding<Page?>(
                get: { selection },
                set: { if let page = $0 { selection = page } }
            ))
        }
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .topTrailing) {
            Button("Skip", action: onFinish)
                .font(.body)
                .foregroundStyle(.black)
                .padding(.horizontal, OTSpace.l)
                .frame(minHeight: OTControlSize.small.hitHeight)
                .background(.regularMaterial, in: Capsule())
                .padding(.trailing, OTSpace.xl)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
                .background(canvas.ignoresSafeArea(edges: .bottom))
        }
        .background(canvas.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .toolbar(.hidden, for: .navigationBar) // ot-lint:allow
    }

    private func pageContent(_ page: Page, heroHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                GeometryReader { geometry in
                    Image(page.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: heroHeight)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [canvas.opacity(0), canvas],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 56) // ot-lint:allow
                        }
                }
                .frame(height: heroHeight)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 26) {
                    Text(page.title)
                        .font(.system(size: titleSize, weight: .bold)) // ot-lint:allow
                        .tracking(-1.6)
                        .accessibilityAddTraits(.isHeader)

                    Text(page.detail)
                        .font(.body)
                }
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OTSpace.xl)
                .padding(.vertical, OTSpace.xl)
            }
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Page.allCases, id: \.self) { page in
                    Button {
                        withAnimation { selection = page }
                    } label: {
                        Circle()
                            .fill(ink.opacity(selection == page ? 1 : 0.35))
                            .frame(width: 8, height: 8)
                            .frame(width: OTControlSize.small.hitHeight, height: OTControlSize.small.hitHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
                    .accessibilityAddTraits(selection == page ? .isSelected : [])
                }
            }

            Button(selection == .rehearsal ? "Get started" : "Next") {
                switch selection {
                case .auditions: withAnimation { selection = .recording }
                case .recording: withAnimation { selection = .rehearsal }
                case .rehearsal: onFinish()
                }
            }
            .buttonStyle(.otPrimary)
            .padding(.horizontal, OTSpace.xl)
            .padding(.bottom, OTSpace.s)
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
