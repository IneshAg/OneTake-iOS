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
                .padding(.top, 30)

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
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
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
    @State private var showConfirmDeleteAll = false
    @State private var showConfirmDisconnectAccount = false
    @State private var showConfirmClearExports = false
    @State private var showConfirmClearReader = false
    @State private var storageRefreshID = UUID()

    private var rawTakesSize: Int64 {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: MediaStore.documentsURL.path) else { return 0 }
        let takeFolders = entries.filter { ($0.hasPrefix("audition-") || $0.hasPrefix("practice-") || $0 == "takes") && $0 != "Exports" }
        return takeFolders.reduce(Int64(0)) { $0 + MediaStore.sizeOnDisk($1) }
    }
    private var exportsSize: Int64 { MediaStore.sizeOnDisk("Exports") }
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
    private var totalSize: Int64 { rawTakesSize + exportsSize + headshotsSize + readerSize }

    private func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }

    var body: some View {
        List {
            // Privacy Architecture Overview
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(OT.accent)
                            .font(.title3)
                        Text("100% OFFLINE & PRIVATE")
                            .font(.otEyebrow)
                            .foregroundStyle(OT.labelTertiary)
                        Spacer()
                        Text(mb(totalSize))
                            .font(.otHeadline)
                    }
                    Text("All auditions, sides, takes, reader tracks and headshots remain in private on-device storage on this iPhone. OneTake has no servers, no ads, and no tracking.")
                        .font(.otFootnote)
                        .foregroundStyle(OT.labelSecondary)
                }
                .padding(.vertical, 4)
            }

            // Cloud Delivery Overview
            Section {
                LabeledContent("iCloud Drive", value: CloudLink.isAvailable ? "Available" : "Not connected")
                if let account = store.account {
                    LabeledContent("Sign-in Provider", value: account.providerName)
                }
            } header: {
                Text("Cloud Delivery")
            } footer: {
                Text("Casting sites receive files through your Share Sheet. “Email or link” uploads deliverables directly to your personal iCloud Drive container. There is no OneTake server.")
            }

            // Local Storage Breakdown and Actions
            Section {
                LabeledContent("Takes & auditions", value: mb(rawTakesSize))
                LabeledContent("Headshots", value: mb(headshotsSize))
                LabeledContent("Reader tracks", value: mb(readerSize))
                LabeledContent("Exported deliverables", value: mb(exportsSize))

                if exportsSize > 0 {
                    Button("Clear exported deliverables cache") {
                        showConfirmClearExports = true
                    }
                    .foregroundStyle(OT.accent)
                }
                if readerSize > 0 {
                    Button("Clear practice reader audio") {
                        showConfirmClearReader = true
                    }
                    .foregroundStyle(OT.accent)
                }
            } header: {
                Text("On this iPhone")
            } footer: {
                Text("Clearing exported deliverables frees storage space on this device. Your raw takes and sides remain intact so you can re-export anytime.")
            }

            // Account & Session Section
            Section {
                if let account = store.account {
                    LabeledContent("Connected as", value: account.name ?? account.email ?? "Signed in")
                    Button("Disconnect account", role: .destructive) {
                        showConfirmDisconnectAccount = true
                    }
                } else {
                    LabeledContent("Account mode", value: "Guest (No account)")
                }
            } header: {
                Text("Account")
            } footer: {
                Text(store.isSignedIn
                     ? "Disconnecting removes your sign-in credentials from this iPhone."
                     : "You are using OneTake as a guest. An account is only requested when uploading an audition link.")
            }

            // Legal and Data Wipe
            Section {
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
                Button("Delete all local data", role: .destructive) { showConfirmDeleteAll = true }
            } footer: {
                Text("Removes headshots, reader tracks and every take on this iPhone. Sent tapes already delivered aren’t affected.")
            }
        }
        .id(storageRefreshID)
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Privacy & data")
        .confirmationDialog("Clear exported deliverables?", isPresented: $showConfirmClearExports, titleVisibility: .visible) {
            Button("Clear deliverables cache", role: .destructive) {
                clearExports()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes rendered export files from disk to free storage space. Your raw takes and auditions are safe and can be re-exported anytime.")
        }
        .confirmationDialog("Clear reader audio?", isPresented: $showConfirmClearReader, titleVisibility: .visible) {
            Button("Clear reader recordings", role: .destructive) {
                clearReader()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes all practice reader recordings while preserving your script scenes and lines.")
        }
        .confirmationDialog("Disconnect account?", isPresented: $showConfirmDisconnectAccount, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive) {
                store.deleteAccount()
                Haptics.success()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This disconnects your account session from OneTake on this device.")
        }
        .confirmationDialog("Delete all local data?", isPresented: $showConfirmDeleteAll, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every take, headshot and reader recording from this iPhone. It can't be undone.")
        }
    }

    private func clearExports() {
        MediaStore.deleteAll(["Exports"])
        for i in store.auditions.indices {
            store.auditions[i].exportedFileURL = nil
        }
        storageRefreshID = UUID()
        Haptics.success()
    }

    private func clearReader() {
        MediaStore.deleteAll([ReaderTrackPlayer.folder])
        for url in legacyReaderFiles { try? FileManager.default.removeItem(at: url) }
        storageRefreshID = UUID()
        Haptics.success()
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
        storageRefreshID = UUID()
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("n.liveActivity") private var liveActivity = false
    @AppStorage("n.morning") private var morning = true
    @AppStorage("n.twoHours") private var twoHours = true
    @AppStorage("n.delivery") private var delivery = true
    @AppStorage("n.practice") private var practice = false

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var testScheduled = false

    var body: some View {
        Form {
            if authStatus == .denied {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Notifications Disabled in Settings", systemImage: "bell.slash.fill")
                            .font(.otHeadline)
                            .foregroundStyle(OT.warning)
                        Text("iOS is blocking notifications for OneTake. To get morning and deadline alerts, enable notifications in iOS Settings.")
                            .font(.otFootnote)
                            .foregroundStyle(OT.labelSecondary)
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.otSubhead.weight(.semibold))
                        .foregroundStyle(OT.accent)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            } else if authStatus == .notDetermined {
                Section {
                    Button {
                        Task {
                            let granted = await Reminders.requestAuthorization()
                            await refreshStatus()
                            if granted { Reminders.reschedule(store.auditions) }
                        }
                    } label: {
                        HStack {
                            Label("Enable Deadline Reminders", systemImage: "bell.badge.fill")
                                .font(.otBody.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.forward").font(.footnote).foregroundStyle(OT.labelTertiary)
                        }
                    }
                } footer: {
                    Text("Allow OneTake to alert you on deadline mornings and 2 hours before submission.")
                }
            }

            Section {
                Toggle("Morning it’s due", isOn: $morning)
                Toggle("Two hours before", isOn: $twoHours)
                Toggle("Countdown on Lock Screen", isOn: $liveActivity)
            } header: {
                Text("Deadlines")
            } footer: {
                Text("Scheduled on this iPhone, and updated whenever a due date changes or a tape is sent.")
            }

            Section {
                Toggle("Link ready", isOn: $delivery)
                Toggle("Practice nudges · 6 pm", isOn: $practice)
            } header: {
                Text("Your tapes")
            } footer: {
                Text("“Link ready” lets you know if an iCloud link finishes uploading while you're out of the app.")
            }

            Section {
                Button {
                    Reminders.sendTestNotification()
                    testScheduled = true
                    Haptics.success()
                } label: {
                    HStack {
                        Label(testScheduled ? "Test Alert Scheduled (arrives in 3s)" : "Send Test Notification", systemImage: "bell.and.waveform")
                            .font(.otBody)
                        Spacer()
                    }
                }
            } footer: {
                Text("Triggers a test reminder in 3 seconds to verify alerts and sounds on your device.")
            }
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshStatus() }
            }
        }
        .onChange(of: morning) { checkAndReschedule() }
        .onChange(of: twoHours) { checkAndReschedule() }
        .onChange(of: practice) { checkAndReschedule() }
        .onChange(of: liveActivity) { LiveActivitySync.update(store.auditions) }
        .scrollContentBackground(.hidden)
        .otCanvas()
        .navigationTitle("Notifications")
    }

    private func refreshStatus() async {
        let status = await Reminders.authorizationStatus()
        await MainActor.run { self.authStatus = status }
    }

    private func checkAndReschedule() {
        if authStatus == .notDetermined {
            Task {
                await Reminders.requestAuthorization()
                await refreshStatus()
                Reminders.reschedule(store.auditions)
            }
        } else {
            Reminders.reschedule(store.auditions)
        }
    }
}

// MARK: - 08 Headshots

struct HeadshotsView: View {
    /// Set when opened from an audition's checklist, so the screen can continue to its next step.
    var auditionID: Audition.ID? = nil
    @Environment(AppStore.self) private var store
    @State private var framingRatio: FramingRatio?

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
                if taken > 0 {
                    Button("Auto-frame headshots") { framingRatio = .photo }
                        .buttonStyle(.otSecondary)
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
        .sheet(item: $framingRatio) { ratio in
            FramingRatioSheet(ratio: ratio) { selectedRatio in
                for angle in HeadshotStore.taken {
                    if let image = HeadshotStore.load(key: angle.key),
                       let framed = ImageFramer.crop(image, ratio: selectedRatio) {
                        HeadshotStore.replace(framed, key: angle.key)
                    }
                }
                store.headshotVersion += 1
                framingRatio = nil
            }
        }
    }

    private struct FramingRatioSheet: View {
        @Environment(\.dismiss) private var dismiss
        @State var ratio: FramingRatio
        let apply: (CGFloat) -> Void
        @State private var customWidth = "4"
        @State private var customHeight = "3"
        @State private var useCustom = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Auto-frame photos").font(.otTitle)
                Text("Vision keeps the largest face near the center, then crops every saved headshot to the selected ratio. Originals are replaced.")
                    .font(.otCallout).foregroundStyle(OT.labelSecondary)
                Picker("Ratio", selection: $ratio) {
                    ForEach(FramingRatio.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Use custom ratio", isOn: $useCustom)
                HStack {
                    TextField("Width", text: $customWidth).keyboardType(.numberPad)
                    Text(":").foregroundStyle(OT.labelTertiary)
                    TextField("Height", text: $customHeight).keyboardType(.numberPad)
                }
                .padding(12)
                .background(OT.fillField, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("Use the fields for a custom width:height crop.")
                    .font(.otFootnote).foregroundStyle(OT.labelTertiary)
                Spacer()
                Button("Apply") {
                    let width = CGFloat(Double(customWidth) ?? 0)
                    let height = CGFloat(Double(customHeight) ?? 0)
                    apply(useCustom && width > 0 && height > 0 ? width / height : ratio.value)
                }.buttonStyle(.otPrimary)
                Button("Cancel") { dismiss() }.buttonStyle(.otSecondary)
            }
            .padding(OT.gutter)
            .presentationDetents([.height(300)])
        }
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
    @State private var cameraSpeaker = CameraGuidanceSpeaker()
    @State private var voiceAllowed = false
    @State private var voiceGuidanceEnabled = true
    @State private var showMatchGuide = false
    @State private var showGhostOverlay = true
    @State private var angle: Angle = .front
    @State private var justCaptured = false
    @State private var captureFailed = false

    var body: some View {
        ZStack {
            CameraBackground(controller: camera)

            // Alignment overlay — ghost outline to position against, shifted per angle.
            if showGhostOverlay {
                ghostAlignmentOverlay
            }

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

                    // Reference model button — tap to inspect target headshot reference & standards.
                    referenceThumbnail
                }
                .frame(height: 44)
                .padding(.top, 8)

                Spacer()

                // Live status chips (lighting & angle)
                statusChips
                    .padding(.bottom, 6)

                Text(guide.message)
                    .font(.otHeadline).foregroundStyle(guide.aligned ? OT.success : .white)
                Text(follower.isListening ? "Tap, or say “Now”" : "Voice is off — tap the shutter")
                    .font(.otFootnote).foregroundStyle(.white.opacity(0.7))

                ZStack {
                    Button { capture() } label: {
                        Circle().fill(.white).frame(width: 66, height: 66).overlay(Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78))
                    }
                    .scaleEffect(justCaptured ? 0.88 : 1)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: justCaptured)
                    .accessibilityLabel("Take photo")

                    HStack {
                        // Voice guidance speaker toggle (symmetric with camera flip)
                        Button {
                            voiceGuidanceEnabled.toggle()
                            Haptics.tick()
                            if voiceGuidanceEnabled {
                                cameraSpeaker.speak("Voice guidance on", minInterval: 0.1)
                            } else {
                                cameraSpeaker.stop()
                            }
                        } label: {
                            Image(systemName: voiceGuidanceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .foregroundStyle(voiceGuidanceEnabled ? OT.due : .white.opacity(0.7))
                                .frame(width: 44, height: 44).background(OT.cameraGlass, in: Circle())
                        }
                        .accessibilityLabel(voiceGuidanceEnabled ? "Mute voice guidance" : "Turn on voice guidance")

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
        .sheet(isPresented: $showMatchGuide) {
            HeadshotReferenceGuideSheet(
                angle: angle,
                showGhostOverlay: $showGhostOverlay,
                voiceGuidanceEnabled: $voiceGuidanceEnabled
            )
        }
        .task {
            camera.wantsFaceGuidance = true
            if await CameraController.requestVideoAccess() { camera.configure(position: .front) }
            voiceAllowed = await SpeechFollower.requestAccess()
            if voiceAllowed { follower.start() }
            if voiceGuidanceEnabled {
                let initialPrompt: String
                switch angle {
                case .front: initialPrompt = "Front headshot. Look straight at the camera."
                case .left:  initialPrompt = "Left profile. Turn your head to your left."
                case .right: initialPrompt = "Right profile. Turn your head to your right."
                }
                cameraSpeaker.speak(initialPrompt, minInterval: 0.8)
            }
            // Continuous guidance speaker loop to keep assisting actors whose heads are turned
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.5))
                if voiceGuidanceEnabled, camera.state == .ready {
                    speakCurrentGuidance()
                }
            }
        }
        .onChange(of: camera.state) { _, state in
            if state == .ready, voiceAllowed, !follower.isListening { follower.start() }
        }
        .onChange(of: guide.message) { _, _ in
            speakCurrentGuidance()
        }
        .onChange(of: angle) { _, newAngle in
            follower.reset()
            if voiceGuidanceEnabled {
                let prompt: String
                switch newAngle {
                case .front: prompt = "Front headshot. Look straight at the camera."
                case .left:  prompt = "Left profile. Turn your head to your left."
                case .right: prompt = "Right profile. Turn your head to your right."
                }
                cameraSpeaker.speak(prompt, minInterval: 0.1)
            }
        }
        .onChange(of: follower.lastCommand) { _, cmd in
            if cmd?.word == "now" || cmd?.word == "action" { capture() }
        }
        // Volume buttons, Camera Control and AirPods stem press work as the shutter.
        .onCameraCaptureEvent { event in
            if event.phase == .ended { capture() }
        }
        .onDisappear {
            cameraSpeaker.stop()
            camera.stop()
            follower.stop()
            store.syncHeadshotPieces()
        }
        .alert("Couldn’t take that photo", isPresented: $captureFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failureMessage)
        }
    }

    private var ghostAlignmentOverlay: some View {
        ZStack {
            Ellipse()
                .stroke(guide.aligned ? OT.success : OT.due, lineWidth: guide.aligned ? 3 : 1.5)
                .frame(width: 200, height: 270)
                .rotation3DEffect(.degrees(angle == .front ? 0 : 8), axis: (x: 0, y: 1, z: 0))

            // Eye-line alignment notches inside the ellipse
            HStack {
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2)
                Spacer()
                Rectangle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 32, height: 2)
            }
            .frame(width: 170)
            .offset(y: -24)
        }
        .offset(x: angle == .left ? -14 : angle == .right ? 14 : 0, y: -20)
        .animation(.easeOut(duration: 0.15), value: guide.aligned)
    }

    private var statusChips: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(lightColor)
                    .frame(width: 6, height: 6)
                Text(lightText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.black.opacity(0.55), in: Capsule())

            HStack(spacing: 5) {
                Circle()
                    .fill(guide.aligned ? OT.success : OT.due)
                    .frame(width: 6, height: 6)
                Text(angleStatusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.black.opacity(0.55), in: Capsule())
        }
    }

    private var lightColor: Color {
        guard let luma = camera.lightLevel else { return OT.success }
        return (luma < 0.22 || luma > 0.85) ? OT.due : OT.success
    }

    private var lightText: String {
        guard let luma = camera.lightLevel else { return "Light: Good" }
        if luma < 0.22 { return "Low light" }
        if luma > 0.85 { return "Direct glare" }
        return "Light: Soft & even"
    }

    private var angleStatusText: String {
        switch angle {
        case .front: return guide.aligned ? "Angle: Square" : "Face forward"
        case .left:  return guide.aligned ? "Angle: 90° profile" : "Turn left"
        case .right: return guide.aligned ? "Angle: 90° profile" : "Turn right"
        }
    }

    private func speakCurrentGuidance(immediate: Bool = false) {
        guard voiceGuidanceEnabled, camera.state == .ready else { return }
        cameraSpeaker.speak(guide.spoken, minInterval: immediate ? 0.2 : 2.0, repeatInterval: 4.5)
    }

    private var failureMessage: String {
        switch camera.state {
        case .failed(let reason): reason
        case .idle: "The camera hasn’t started. Check Settings › OneTake › Camera is on, then reopen this screen."
        default: "The camera wasn’t ready. Give it a second, then try again."
        }
    }

    /// Live coaching from face detection: is the face framed, the right size, and turned the right amount?
    private var guide: (message: String, spoken: String, aligned: Bool) {
        guard let f = camera.face else {
            return ("Show your face to the camera", "Step into the frame so your face is visible", false)
        }
        if f.height < 0.20 {
            return ("Move closer", "Move closer to the camera", false)
        }
        if f.height > 0.52 {
            return ("Move back a little", "Move back a little", false)
        }
        if f.centerX < 0.38 {
            return ("Too far left — move right", "Move to your right", false)
        }
        if f.centerX > 0.62 {
            return ("Too far right — move left", "Move to your left", false)
        }
        if f.centerY < 0.28 {
            return ("Tilt the phone up a little", "Tilt the phone up a little", false)
        }
        if f.centerY > 0.58 {
            return ("Tilt the phone down a little", "Tilt the phone down a little", false)
        }
        let yaw = f.yaw ?? 0
        switch angle {
        case .front:
            if abs(yaw) > 0.25 {
                return ("Look straight at the camera", "Look straight at the camera", false)
            }
        case .left:
            if f.yaw != nil && abs(yaw) < 0.25 {
                return ("Turn your head to your left", "Turn your head to your left", false)
            }
            if abs(yaw) > 1.15 {
                return ("Turn back a little", "Turn back a little", false)
            }
        case .right:
            if f.yaw != nil && abs(yaw) < 0.25 {
                return ("Turn your head to your right", "Turn your head to your right", false)
            }
            if abs(yaw) > 1.15 {
                return ("Turn back a little", "Turn back a little", false)
            }
        }
        return ("Hold still — that’s it", "Hold still — say Now to shoot", true)
    }

    private var referenceThumbnail: some View {
        Button {
            showMatchGuide = true
            Haptics.tick()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(showMatchGuide ? OT.due : .white.opacity(0.28), lineWidth: 1.5)
                        )

                    if let img = thumbnailImageForCurrentOrPriorAngle() {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Image(systemName: referenceSymbol)
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    // Mini "info" indicator badge in bottom right corner of the thumbnail
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(OT.due)
                                .background(Circle().fill(.black.opacity(0.7)))
                                .offset(x: 3, y: 3)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .frame(width: 44, height: 44)

                HStack(spacing: 2) {
                    Text("Match this")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Match this reference guide for \(angle.rawValue)")
    }

    private func thumbnailImageForCurrentOrPriorAngle() -> UIImage? {
        if let current = HeadshotStore.load(key: angle.rawValue) {
            return current
        }
        if angle == .left, let front = HeadshotStore.load(key: "Front") {
            return front
        }
        if angle == .right {
            return HeadshotStore.load(key: "Left") ?? HeadshotStore.load(key: "Front")
        }
        return nil
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
        cameraSpeaker.stop()
        camera.capturePhoto { image in
            justCaptured = false
            guard let image else { captureFailed = true; Haptics.warning(); return }
            HeadshotStore.save(image, key: angle.rawValue)
            store.headshotVersion += 1
            Haptics.success()
            if let next = Angle.allCases.drop(while: { $0 != angle }).dropFirst().first {
                let saved = angle.rawValue
                let nextName = next.rawValue
                angle = next
                follower.reset()
                if voiceGuidanceEnabled {
                    let prompt = next == .left ? "\(saved) photo saved. Now turn to your left profile." : "\(saved) photo saved. Now turn to your right profile."
                    cameraSpeaker.speak(prompt, minInterval: 0.1)
                }
            } else {
                if voiceGuidanceEnabled {
                    cameraSpeaker.speak("All headshots saved!", minInterval: 0.1)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Match Reference Guide Sheet

struct HeadshotReferenceGuideSheet: View {
    let angle: HeadshotFlow.Angle
    @Binding var showGhostOverlay: Bool
    @Binding var voiceGuidanceEnabled: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Card with angle illustration / preview
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 200)

                            if let saved = HeadshotStore.load(key: angle.rawValue) {
                                Image(uiImage: saved)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            } else {
                                referencePoseIllustration
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )

                        Text(angleTitle)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)

                        Text(angleSummary)
                            .font(.otSubhead)
                            .foregroundStyle(OT.labelSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(.top, 8)

                    // Casting Standards Checklist
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Casting Standards")
                            .font(.otHeadline)
                            .foregroundStyle(.white)

                        guideRow(icon: "eye.fill", title: "Eye-line Alignment", desc: "Align eyes level with the horizontal guide notches. Look straight at the camera lens.")
                        guideRow(icon: "arrow.triangle.2.circlepath", title: "Head Angle", desc: angleAngleDesc)
                        guideRow(icon: "sun.max.fill", title: "Soft & Even Lighting", desc: "Face a window or soft key light. Avoid harsh backlights, hard shadows, or overhead glare.")
                        guideRow(icon: "viewfinder", title: "Framing & Distance", desc: "Hold phone 2–3 feet away at chin level. Head and shoulders should fill the frame with 1–2 inches headroom.")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // Overlay & Voice Guidance Toggles
                    VStack(spacing: 12) {
                        Toggle(isOn: $showGhostOverlay) {
                            Label("Show Alignment Overlay", systemImage: "viewfinder")
                                .font(.otSubhead.weight(.medium))
                        }
                        .tint(OT.due)

                        Divider().overlay(Color.white.opacity(0.1))

                        Toggle(isOn: $voiceGuidanceEnabled) {
                            Label("Spoken Voice Guidance", systemImage: "speaker.wave.2.fill")
                                .font(.otSubhead.weight(.medium))
                        }
                        .tint(OT.due)
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        dismiss()
                    } label: {
                        Text("Got it — Start Matching")
                            .font(.otHeadline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(OT.due, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 4)
                }
                .padding(OT.gutter)
            }
            .background(Color(white: 0.08).ignoresSafeArea())
            .navigationTitle("Match Reference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(OT.due)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var angleTitle: String {
        switch angle {
        case .front: "Front Headshot"
        case .left:  "Left 90° Profile"
        case .right: "Right 90° Profile"
        }
    }

    private var angleSummary: String {
        switch angle {
        case .front: "Direct front-facing portrait. Shoulders square, eyes looking straight at the camera with chin level."
        case .left:  "Full 90-degree turn to your left. Your left ear, nose profile, and jawline should be clearly defined."
        case .right: "Full 90-degree turn to your right. Your right ear, nose profile, and jawline should be clearly defined."
        }
    }

    private var angleAngleDesc: String {
        switch angle {
        case .front: "Face the lens squarely. Keep head level without tilting left or right."
        case .left:  "Turn head 90° to your left until only your left profile is visible. Keep chin parallel to ground."
        case .right: "Turn head 90° to your right until only your right profile is visible. Keep chin parallel to ground."
        }
    }

    private func guideRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(OT.due)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.otSubhead.weight(.semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.otFootnote)
                    .foregroundStyle(OT.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var referencePoseIllustration: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(OT.due.opacity(0.4), lineWidth: 2)
                    .frame(width: 90, height: 90)

                Image(systemName: angle == .front ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(OT.due)
                    .scaleEffect(x: angle == .left ? -1 : 1, y: 1)
            }
            Text("Reference Pose Guide")
                .font(.otCaption.weight(.semibold))
                .foregroundStyle(OT.labelTertiary)
        }
        .frame(height: 180)
    }
}
