import SwiftUI
import AVKit

// MARK: - 10 Profile (tab)

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("appearance") private var appearance = "system"
    @State private var showSignIn = false
    @AppStorage("slateAtStart") private var slateAtStart = true
    @AppStorage("readerVolume") private var readerVolume = "Quieter"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack(alignment: .center) {
                    Text("Profile").font(.otLargeTitle).foregroundStyle(OT.labelPrimary)
                    Spacer()
                    Button("Done") {
                        store.showProfile = false
                    }
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(OT.labelPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(OT.fillField, in: Capsule())
                }

                // Slate & Headshot Card
                VStack(alignment: .leading, spacing: 14) {
                    Button { store.push(.editSlate) } label: {
                        HStack(spacing: 14) {
                            HeadshotImage(realKey: "front").id(store.headshotVersion).frame(width: 64, height: 64).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.slate.name.isEmpty ? "Add your name" : store.slate.name).font(.otTitle).foregroundStyle(OT.labelPrimary)
                                Text(store.slate.summary)
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(OT.accent).frame(width: 36, height: 36).background(OT.accentSoft, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit slate")

                    Divider()

                    Button { store.push(.headshots(for: nil)) } label: {
                        HStack {
                            Label("Headshots", systemImage: "person.crop.square")
                                .font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Text("\(HeadshotStore.taken.count) of 3").font(.otCallout).foregroundStyle(OT.labelTertiary).id(store.headshotVersion)
                            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .otCard(radius: 20)

                // Every time you record
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Every time you record")

                    VStack(spacing: 0) {
                        // "Room noise" and "Export" settings used to sit here; nothing ever applied
                        // them, so they're gone until there's processing behind them.
                        Toggle(isOn: $slateAtStart) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Slate at the start").font(.otBody).foregroundStyle(OT.labelPrimary)
                                Text(slateAtStart ? "Slate and full length open the tape" : "Slate and full length close the tape")
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                        }
                            .tint(OT.accent)
                            .frame(minHeight: 48)

                        Divider().padding(.vertical, 4)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reader volume").font(.otBody).foregroundStyle(OT.labelPrimary)
                                Text("Casting should hear you first").font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Picker("Reader volume", selection: $readerVolume) {
                                ForEach(["Same as me", "Quieter", "Much quieter"], id: \.self) { Text($0) }
                            }
                            .tint(OT.accent)
                        }
                        .frame(minHeight: 48)

                    }
                    .padding(18)
                    .otCard(radius: 20)
                }

                // More section
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "More")

                    VStack(spacing: 0) {
                        HStack {
                            Label("Appearance", systemImage: "circle.lefthalf.filled")
                                .font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Picker("Appearance", selection: $appearance) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .labelsHidden()
                        }
                        .frame(minHeight: 44)

                        Divider().padding(.vertical, 2)

                        Button { store.push(.notifications) } label: {
                            profileRow(symbol: "bell", title: "Notifications")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 2)

                        Button { store.push(.privacy) } label: {
                            profileRow(symbol: "hand.raised", title: "Privacy & data")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .otCard(radius: 20)
                }

                // Account section (moved down)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Account")

                    VStack(spacing: 0) {
                        if let account = store.account {
                            HStack {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(account.name ?? account.email ?? "Signed in").font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                                        Text("With \(account.providerName)" + (account.name != nil ? (account.email.map { " · \($0)" } ?? "") : ""))
                                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                } icon: { Image(systemName: "person.crop.circle.fill").foregroundStyle(OT.accent) }
                                Spacer()
                            }
                            .frame(minHeight: 44)

                            Divider().padding(.vertical, 2)

                            // Signs out only — onboarding, auditions and takes stay exactly as they are.
                            Button { store.signOut(); Haptics.tick() } label: {
                                HStack {
                                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.otBody.weight(.medium))
                                        .foregroundStyle(OT.danger)
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button { showSignIn = true } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Label("Sign in", systemImage: "person.crop.circle.badge.plus")
                                            .font(.otBody.weight(.medium)).foregroundStyle(OT.labelPrimary)
                                        Text("With Apple or Google. Only needed to send a tape as a link — everything else works without it.")
                                            .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .otCard(radius: 20)
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 120)
        }
        .otCanvas()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSignIn) {
            SignInView { account in store.account = account; showSignIn = false }
        }
    }

    private func profileRow(symbol: String, title: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.otBody).foregroundStyle(OT.labelPrimary)
            Spacer()
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(OT.labelTertiary)
        }
        .frame(minHeight: 44)
    }
}

// MARK: - 10.1 Edit slate

struct EditSlateView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section("Name") { TextField("Name", text: $store.slate.name) }
            Section { HStack { TextField("Height", text: $store.slate.height); TextField("Based in", text: $store.slate.basedIn) } } header: { Text("Height · Based in") }
            Section { TextField("Self-represented", text: $store.slate.representation) } header: { Text("Representation") } footer: { Text("Said at the start of every tape, in this order. Change it any time.") }
            Section { Text(store.slate.spoken).font(.otHeadline) } header: { Text("Preview") }
        }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Edit slate")
    }
}

// MARK: - 10b Privacy & data

struct PrivacyView: View {
    @Environment(AppStore.self) private var store
    @State private var showConfirmDelete = false
    @State private var showConfirmDeleteAccount = false

    private var takesSize: Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path) else { return 0 }
        let takeFolders = entries.filter { $0.hasPrefix("audition-") || $0.hasPrefix("practice-") || $0 == "Exports" }
        return takeFolders.reduce(Int64(0)) { $0 + MediaStore.sizeOnDisk($1) }
    }
    private var headshotsSize: Int64 { MediaStore.sizeOnDisk("headshots") }
    private var readerSize: Int64 { MediaStore.sizeOnDisk(ReaderTrackPlayer.folder) + legacyReaderFiles.reduce(Int64(0)) { total, url in
        total + ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0)
    } }
    /// Reader lines from before tracks were scoped per audition lived loose in Documents as
    /// `reader-line-N.m4a`; still counted and deleted so they don't linger invisibly.
    private var legacyReaderFiles: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path)) ?? []
        return entries.filter { $0.hasPrefix("reader-line-") }.map { MediaStore.documentsURL.appendingPathComponent($0) }
    }
    private var totalSize: Int64 { takesSize + headshotsSize + readerSize }

    private func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("ON THIS IPHONE").font(.otEyebrow).foregroundStyle(OT.labelTertiary); Spacer(); Text(mb(totalSize)).font(.otHeadline) }
                }
            }
            Section {
                LabeledContent("Takes & recordings", value: mb(takesSize))
                LabeledContent("Headshots", value: mb(headshotsSize))
                LabeledContent("Reader recordings", value: mb(readerSize))
            }
            Section("Sent tapes") {
                LabeledContent("Links", value: "Hosted in your iCloud · expiry shown per tape")
            }
            Section {
                if let account = store.account {
                    LabeledContent("Signed in with", value: account.providerName)
                    LabeledContent("Account", value: account.name ?? account.email ?? "Connected")
                    Button("Delete account", role: .destructive) {
                        showConfirmDeleteAccount = true
                    }
                } else {
                    LabeledContent("Account status", value: "Guest (no account)")
                    Button("Delete account", role: .destructive) {
                        showConfirmDeleteAccount = true
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text(store.isSignedIn
                     ? "Deleting your account disconnects your sign-in credentials and revokes cloud link sharing."
                     : "You are using OneTake as a guest without an account. Deleting clears any cached session data.")
            }
            Section {
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
                Button("Delete all local data", role: .destructive) { showConfirmDelete = true }
            } footer: {
                Text("Clears headshots, reader tracks and every take on this iPhone. Sent tapes already delivered aren’t affected.")
            }
        }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Privacy & data")
        .confirmationDialog("Delete account?", isPresented: $showConfirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                store.deleteAccount()
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.isSignedIn
                 ? "Are you sure you want to delete your account? This will permanently delete your account connection from OneTake on this device."
                 : "Are you sure you want to clear your guest session data?")
        }
        .confirmationDialog("Delete all local data?", isPresented: $showConfirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every take, headshot and reader recording from this iPhone. It can't be undone.")
        }
    }

    private func deleteAll() {
        MediaStore.deleteAll(["headshots", "takes", "Exports", ReaderTrackPlayer.folder] + store.auditions.map { "audition-\($0.id.uuidString)" } + store.practice.map { "practice-\($0.id.uuidString)" })
        HeadshotStore.clearCache()
        store.headshotVersion += 1
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
        store.takes.removeAll()
        for i in store.auditions.indices {
            store.auditions[i].slateVideoURL = nil; store.auditions[i].fullLengthVideoURL = nil; store.auditions[i].exportedFileURL = nil
            // The recordings and headshots behind these pieces are gone, so unsent auditions go back
            // to "not done" rather than claiming to be ready. Sent ones keep their history (and link).
            guard store.auditions[i].status != .sent else { continue }
            for j in store.auditions[i].pieces.indices { store.auditions[i].pieces[j].isDone = false }
            store.auditions[i].status = .due
        }
        for i in store.practice.indices { store.practice[i].takesRecorded = 0 }
        Haptics.success()
    }
}

// MARK: - Privacy policy

/// What OneTake does with your data, in the app itself — there's no website for it to point at.
/// Keep it in step with the code: every claim here should stay true.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("No servers, no tracking", "OneTake has no server. It doesn't collect analytics, show ads or track you, and nothing you add or record is sent to us.")
                section("Signing in", "You never need an account to add auditions, record or export. Signing in with Apple or Google is only asked for when you send a tape as a link. OneTake keeps the name and email that Apple or Google share on this iPhone to show who's signed in; it isn't sent anywhere else. Sign out from Profile at any time.")
                section("What stays on this iPhone", "Your auditions, sides, takes, slate, headshots, reader recordings and practice are stored in OneTake's own storage on this iPhone. Your iPhone's backups (iCloud Backup, or a computer) include them, the same as any app's data.")
                section("Reading notices and sides", "Text in photos, scans and PDFs is read on this iPhone with Apple's Vision and PDFKit. Nothing is uploaded to do it.")
                section("Voice commands and the prompter", "Speech recognition runs on this iPhone where it's supported. On iPhones that can't do it on the device, Apple's speech recognition service processes the audio under Apple's privacy policy. OneTake only listens on the camera, Run Lines and drill screens.")
                section("Sending a tape", "A tape only leaves this iPhone when you send it. Through the Share Sheet it goes to the app or person you pick. \"Email or link\" uploads it to your own iCloud Drive and makes a download link; anyone with the link can download the tape until iCloud expires it.")
                section("Reminders and widgets", "Deadline reminders are scheduled on this iPhone. Widgets and the Lock Screen countdown read a small summary (project, role, due date, progress) that OneTake keeps on this iPhone for them.")
                section("Deleting your data", "Privacy & data → Delete all local data removes every take, headshot and reader recording. Deleting the app removes everything OneTake stored. Links you've already sent stay in your iCloud Drive until you delete them there.")
            }
            .padding(.horizontal, OT.gutter)
            .padding(.vertical, 12)
        }
        .otCanvas()
        .navigationTitle("Privacy policy")
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.otHeadline).foregroundStyle(OT.labelPrimary)
            Text(body).font(.otCallout).foregroundStyle(OT.labelSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 10c Notifications

struct NotificationSettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("n.liveActivity") private var liveActivity = false
    @AppStorage("n.morning") private var morning = true
    @AppStorage("n.twoHours") private var twoHours = true
    @AppStorage("n.delivery") private var delivery = true
    @AppStorage("n.practice") private var practice = false

    var body: some View {
        Form {
            Section {
                Toggle("Morning it’s due", isOn: $morning)
                Toggle("Two hours before", isOn: $twoHours)
                Toggle("Countdown on Lock Screen", isOn: $liveActivity)
            } header: {
                Text("Deadlines")
            } footer: {
                Text("Scheduled on this iPhone, and updated whenever a due date changes or a tape is sent.")
            }
            // No "from casting" alerts: there's no server that could hear from them.
            Section {
                Toggle("Link ready", isOn: $delivery)
                Toggle("Practice nudges · 6 pm", isOn: $practice)
            } header: {
                Text("Your tapes")
            } footer: {
                Text("“Link ready” lets you know if an iCloud link finishes uploading while you're out of the app.")
            }
        }
        .onChange(of: morning) { Reminders.reschedule(store.auditions) }
        .onChange(of: twoHours) { Reminders.reschedule(store.auditions) }
        .onChange(of: practice) { Reminders.reschedule(store.auditions) }
        .onChange(of: liveActivity) { LiveActivitySync.update(store.auditions) }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Notifications")
    }
}

// MARK: - 08 Headshots

struct HeadshotsView: View {
    /// Set when opened from an audition's checklist, so the screen can continue to its next step.
    var auditionID: Audition.ID? = nil
    @Environment(AppStore.self) private var store

    /// Counted from the real files on disk — the old stored counter defaulted to 1, so the front
    /// headshot showed as taken before it ever was.
    private var taken: Int { HeadshotStore.angles.prefix { HeadshotStore.exists(key: $0.key) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Front is what casting sees first. Profiles help on commercial calls.").font(.otCallout).foregroundStyle(OT.labelSecondary)
                HStack(spacing: 10) {
                    slot("Front", done: taken >= 1, big: true)
                    VStack(spacing: 10) {
                        slot("Left profile", done: taken >= 2, big: false)
                        slot("Right profile", done: taken >= 3, big: false)
                    }
                }
                .frame(height: 300)

                HStack(alignment: .top) {
                    tip("square.split.bottomrightquarter", "Face a window", "not a lamp")
                    tip("rectangle", "Plain wall", "an arm’s length behind")
                    tip("iphone", "Eye level", "a little above is fine")
                }
            }
            .padding(.horizontal, OT.gutter)
            .padding(.bottom, 120)
        }
        .id(store.headshotVersion)
        .otCanvas()
        .navigationTitle("Headshots")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 4) {
                if let auditionID, taken > 0, let a = store.audition(auditionID) {
                    Button("Next: \(a.nextAction)") { store.continueAudition(auditionID) }.buttonStyle(.otPrimary)
                    Button(taken < 3 ? "Add your profiles" : "Retake") { store.camera = .headshot }
                        .font(.otHeadline).foregroundStyle(OT.labelPrimary).frame(maxWidth: .infinity, minHeight: 48)
                } else {
                    Button(taken == 0 ? "Take your headshot" : taken < 3 ? "Add your profiles" : "Retake") {
                        store.camera = .headshot
                    }
                    .buttonStyle(.otPrimary)
                }
            }
            .padding(OT.gutter)
        }
        .onAppear { store.syncHeadshotPieces() }
    }

    private func slot(_ title: String, done: Bool, big: Bool) -> some View {
        let key = title == "Front" ? "front" : title == "Left profile" ? "left" : "right"
        return ZStack(alignment: .bottomLeading) {
            if done {
                HeadshotImage(realKey: key)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                Label(title, systemImage: "checkmark").font(.otFootnote.weight(.semibold)).foregroundStyle(.white).padding(12)
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                    .foregroundStyle(OT.labelTertiary)
                VStack { Image(systemName: "person.crop.square"); Text(title).font(.otHeadline); Text("Not taken").font(.otFootnote).foregroundStyle(OT.labelTertiary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func tip(_ s: String, _ t: String, _ d: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: s).foregroundStyle(OT.labelSecondary)
            Text(t).font(.otSubhead.weight(.semibold))
            Text(d).font(.otFootnote).foregroundStyle(OT.labelTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 09 Headshot capture: front → left → right → crop

struct HeadshotFlow: View {
    enum Angle: String, CaseIterable { case front = "Front", left = "Left", right = "Right" }

    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var camera = CameraController()
    @State private var follower = SpeechFollower()
    @State private var voiceAllowed = false
    @State private var angle: Angle = .front
    @State private var justCaptured = false
    @State private var captureFailed = false

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)
            // Alignment overlay — ghost outline to position against, shifted per angle.
            Ellipse().stroke(guide.aligned ? OT.success : OT.due, lineWidth: guide.aligned ? 3 : 1.5).frame(width: 200, height: 270)
                .animation(.easeOut(duration: 0.15), value: guide.aligned)
                .rotation3DEffect(.degrees(angle == .front ? 0 : 8), axis: (x: 0, y: 1, z: 0))
                .offset(x: angle == .left ? -14 : angle == .right ? 14 : 0, y: -20)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                    }
                    .accessibilityLabel("Close")

                    Spacer()

                    Picker("Angle", selection: $angle) {
                        ForEach(Angle.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Spacer()

                    // Reference model — a small example of this angle, to match against.
                    referenceThumbnail
                }
                .frame(height: 44)
                .padding(.top, 8)

                Spacer()

                Text(guide.message)
                    .font(.otHeadline).foregroundStyle(guide.aligned ? OT.success : .white)
                Text(follower.isListening ? "Tap, or say “Now”" : "Voice is off — tap the shutter").font(.otFootnote).foregroundStyle(.white.opacity(0.7))

                ZStack {
                    Button { capture() } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78))
                    }
                    .scaleEffect(justCaptured ? 0.88 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: justCaptured)
                    .accessibilityLabel("Take photo")

                    HStack {
                        Spacer()
                        Button {
                            camera.switchCamera()
                            Haptics.tick()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera").foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                        }
                        .disabled(camera.state != .ready)
                        .accessibilityLabel("Switch camera")
                    }
                }
                .padding(.bottom, 12)
            }
            .padding(.horizontal, OT.gutter)
        }
        .preferredColorScheme(.dark)
        .task {
            camera.wantsFaceGuidance = true
            if await CameraController.requestVideoAccess() { camera.configure(position: .front) }
            // Voice shutter — reuses the same "Talk to OneTake" recognizer the recording flow uses,
            // just with a capture command added to its vocabulary. Gesture trigger is a v1.1 candidate.
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
        }
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening { follower.start() }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if cmd?.word == "now" || cmd?.word == "action" { capture() }
        }
        // Volume buttons, Camera Control and AirPods stem press work as the shutter.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { capture() }
        }
        .onDisappear { camera.stop(); follower.stop(); store.syncHeadshotPieces() }
        .alert("Couldn’t take that photo", isPresented: $captureFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage)
        }
    }

    private var failureMessage: String {
        switch camera.state {
        case .failed(let reason): reason
        case .idle: "The camera hasn’t started. Check Settings › OneTake › Camera is on, then reopen this screen."
        default: "The camera wasn’t ready. Give it a second, then try again."
        }
    }

    /// Live coaching from face detection: is the face framed, the right size, and turned the right amount?
    private var guide: (message: String, aligned: Bool) {
        guard let f = camera.face else { return ("Show your face to the camera", false) }
        if f.height < 0.2 { return ("Move closer", false) }
        if f.height > 0.5 { return ("Move back a little", false) }
        if f.centerX < 0.4 { return ("Too far left — move right", false) }
        if f.centerX > 0.6 { return ("Too far right — move left", false) }
        if f.centerY < 0.3 { return ("Tilt the phone up a little", false) }
        if f.centerY > 0.56 { return ("Tilt the phone down a little", false) }
        let yaw = abs(f.yaw ?? 0)
        switch angle {
        case .front:
            if yaw > 0.22 { return ("Look straight at the camera", false) }
        case .left, .right:
            if f.yaw == nil || yaw < 0.35 { return ("Turn your head a little more to the side", false) }
            if yaw > 1.0 { return ("Turn back a little", false) }
        }
        return ("Hold still — that’s it", true)
    }

    private var referenceThumbnail: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12))
                Image(systemName: referenceSymbol).font(.system(size: 18)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: 44, height: 44)
            Text("Match this").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var referenceSymbol: String {
        switch angle {
        case .front: "person.crop.circle"
        case .left:  "person.crop.circle.badge.checkmark"
        case .right: "person.crop.circle.badge.checkmark"
        }
    }

    private func capture() {
        guard !justCaptured else { return }
        justCaptured = true
        camera.capturePhoto { image in
            justCaptured = false
            // Nothing captured means nothing saved and no moving on — never a stand-in photo.
            guard let image else { captureFailed = true; Haptics.warning(); return }
            HeadshotStore.save(image, key: angle.rawValue)
            store.headshotVersion += 1
            Haptics.success()
            if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
                angle = next
                follower.reset()
            } else {
                dismiss()
            }
        }
    }
}
