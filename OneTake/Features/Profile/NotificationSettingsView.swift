import SwiftUI
import UserNotifications

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
                        VStack(alignment: .leading, spacing: OTSpace.s) {
                            Label("Notifications Disabled in Settings", systemImage: "bell.slash.fill")
                                .font(.otHeadline)
                                .foregroundStyle(OT.warning)
                            Text("Allow notifications in iOS Settings to receive reminders.")
                                .font(.otFootnote)
                                .foregroundStyle(OT.labelSecondary)
                            Button("Open iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.otSubhead.weight(.semibold))
                            .foregroundStyle(OT.accent)
                            .padding(.top, OTSpace.xxs)
                        }
                        .padding(.vertical, OTSpace.xxs)
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
                    }
                }

                Section {
                    Toggle("Morning it’s due", isOn: $morning)
                    Toggle("Two hours before", isOn: $twoHours)
                    Toggle("Countdown on Lock Screen", isOn: $liveActivity)
                } header: {
                    Text("Deadlines")
                }

                Section {
                    Toggle("Link ready", isOn: $delivery)
                    Toggle("Practice nudges · 6 pm", isOn: $practice)
                } header: {
                    Text("Your tapes")
                } footer: {
                    Text("Alerts you when an iCloud upload finishes.")
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
                    Text("Sends a test alert in 3 seconds.")
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
        .navigationBarTitleDisplayMode(.inline)
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
