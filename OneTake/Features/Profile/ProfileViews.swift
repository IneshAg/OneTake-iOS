import SwiftUI

// MARK: - 10 Profile (tab)

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var showSignIn = false
    @AppStorage("slateAtStart") private var slateAtStart = true
    @AppStorage("cleanNoise") private var cleanNoise = true
    @AppStorage("readerVolume") private var readerVolume = "Quieter"
    @AppStorage("export") private var export = "1080p, landscape"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack {
                    Text("Profile").font(.otLargeTitle).foregroundStyle(OT.labelPrimary)
                    Spacer()
                }

                // Slate & Headshot Card
                VStack(alignment: .leading, spacing: 14) {
                    Button { store.push(.editSlate) } label: {
                        HStack(spacing: 14) {
                            HeadshotImage().frame(width: 64, height: 64).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.slate.name).font(.otTitle).foregroundStyle(OT.labelPrimary)
                                Text("\(store.slate.height) · \(store.slate.basedIn) · \(store.slate.representation.isEmpty ? "Self-represented" : store.slate.representation)")
                                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                            }
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(OT.accent).frame(width: 36, height: 36).background(OT.accentSoft, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit slate")

                    Divider()

                    Button { store.push(.headshots) } label: {
                        HStack {
                            Label("Headshots", systemImage: "person.crop.square")
                                .font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Text("1 of 3").font(.otCallout).foregroundStyle(OT.labelTertiary)
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
                        Toggle("Slate at the start", isOn: $slateAtStart)
                            .tint(OT.accent)
                            .foregroundStyle(OT.labelPrimary)
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

                        Divider().padding(.vertical, 4)

                        Toggle("Clean up room noise", isOn: $cleanNoise)
                            .tint(OT.accent)
                            .foregroundStyle(OT.labelPrimary)
                            .frame(minHeight: 48)

                        Divider().padding(.vertical, 4)

                        HStack {
                            Text("Export").font(.otBody).foregroundStyle(OT.labelPrimary)
                            Spacer()
                            Picker("Export", selection: $export) {
                                ForEach(["1080p, landscape", "4K, landscape", "1080p, portrait"], id: \.self) { Text($0) }
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
                        Button { store.push(.notifications) } label: {
                            profileRow(symbol: "bell", title: "Notifications")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 2)

                        Button { store.push(.privacy) } label: {
                            profileRow(symbol: "hand.raised", title: "Privacy & data")
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 2)

                        if store.isSignedIn {
                            Button { store.isOnboarded = false } label: {
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
                                        Text("Only needed to share a link or sync across devices — everything here already works without it.")
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
            SignInView { store.isSignedIn = true; showSignIn = false }
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
                LabeledContent("Private links", value: "Expire after 30 days")
            }
            Section {
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                Button("Delete all local data", role: .destructive) { showConfirmDelete = true }
            } footer: {
                Text("Clears headshots, reader tracks and every take on this iPhone. Sent tapes already delivered aren’t affected.")
            }
        }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Privacy & data")
        .confirmationDialog("Delete all local data?", isPresented: $showConfirmDelete, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every take, headshot and reader recording from this iPhone. It can't be undone.")
        }
    }

    private func deleteAll() {
        MediaStore.deleteAll(["headshots", "takes", "Exports", ReaderTrackPlayer.folder] + store.auditions.map { "audition-\($0.id.uuidString)" } + store.practice.map { "practice-\($0.id.uuidString)" })
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
        store.takes.removeAll()
        for i in store.auditions.indices { store.auditions[i].slateVideoURL = nil; store.auditions[i].fullLengthVideoURL = nil; store.auditions[i].exportedFileURL = nil }
        for i in store.practice.indices { store.practice[i].takesRecorded = 0 }
        Haptics.success()
    }
}

// MARK: - 10c Notifications

struct NotificationSettingsView: View {
    @AppStorage("n.morning") private var morning = true
    @AppStorage("n.twoHours") private var twoHours = true
    @AppStorage("n.callbacks") private var callbacks = true
    @AppStorage("n.messages") private var messages = true
    @AppStorage("n.delivery") private var delivery = true
    @AppStorage("n.practice") private var practice = false

    var body: some View {
        Form {
            Section {
                Toggle("Morning it’s due", isOn: $morning)
                Toggle("Two hours before", isOn: $twoHours)
            } header: {
                Text("Deadlines")
            } footer: {
                Text("Each audition alerts once per change — never the same thing twice.")
            }
            Section("From casting") {
                Toggle("Callbacks and new sides", isOn: $callbacks)
                Toggle("Messages", isOn: $messages)
            }
            Section("Your tapes") {
                Toggle("Delivered or failed", isOn: $delivery)
                Toggle("Practice nudges", isOn: $practice)
            }
        }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Notifications")
    }
}

// MARK: - 08 Headshots

struct HeadshotsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("headshots.count") private var taken = 1

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
        .otCanvas()
        .navigationTitle("Headshots")
        .safeAreaInset(edge: .bottom) {
            Button(taken == 0 ? "Take your headshot" : taken < 3 ? "Add your profiles" : "Retake") {
                store.camera = .headshot
            }
            .buttonStyle(.otPrimary).padding(OT.gutter)
        }
    }

    private func slot(_ title: String, done: Bool, big: Bool) -> some View {
        let key = title == "Front" ? "front" : title == "Left profile" ? "left" : "right"
        return ZStack(alignment: .bottomLeading) {
            if done {
                HeadshotImage(name: title == "Front" ? "Headshot" : title == "Left profile" ? "HeadshotLeft" : "HeadshotRight", realKey: key)
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
    @AppStorage("headshots.count") private var taken = 1
    @State private var camera = CameraController()
    @State private var follower = SpeechFollower()
    @State private var angle: Angle = .front
    @State private var review: UIImage?
    @State private var justCaptured = false

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)
            // Alignment overlay — ghost outline to position against, shifted per angle.
            Ellipse().stroke(OT.due, lineWidth: 1.5).frame(width: 200, height: 270)
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

                Text(angle == .front ? "Hold still — you’re centred" : "Hold still — that’s your profile")
                    .font(.otHeadline).foregroundStyle(.white)
                Text("Tap, or say “Now”").font(.otFootnote).foregroundStyle(.white.opacity(0.7))

                Button { capture() } label: {
                    Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78))
                }
                .scaleEffect(justCaptured ? 0.88 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: justCaptured)
                .accessibilityLabel("Take photo")
                .padding(.bottom, 12)
            }
            .padding(.horizontal, OT.gutter)
        }
        .preferredColorScheme(.dark)
        .task {
            if await CameraController.requestAccess() { camera.configure(position: .front) }
            // Voice shutter — reuses the same "Talk to OneTake" recognizer the recording flow uses,
            // just with a capture command added to its vocabulary. Gesture trigger is a v1.1 candidate.
            if await SpeechFollower.requestAccess() { follower.start() }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if cmd?.word == "now" || cmd?.word == "action" { capture() }
        }
        .onDisappear { camera.stop(); follower.stop() }
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
        let fallbackName = angle == .front ? "Headshot" : angle == .left ? "HeadshotLeft" : "HeadshotRight"
        camera.capturePhoto(fallbackName: fallbackName) { image in
            review = image
            if let image { HeadshotStore.save(image, key: angle.rawValue) }
            taken = max(taken, (Angle.allCases.firstIndex(of: angle) ?? 0) + 1)
            Haptics.success()
            justCaptured = false
            if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
                angle = next
                follower.reset()
            } else {
                dismiss()
            }
        }
    }
}
