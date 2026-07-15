import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var state: AwakeState

    private var keepAwakeBinding: Binding<Bool> {
        Binding(
            get: { state.sleepDisabled },
            set: { state.setKeepAwake($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: keepAwakeBinding) {
                    Text("Keep Awake")
                        .font(.headline)
                }
                .toggleStyle(.switch)
                Text("pmset disablesleep — stays awake even with the lid closed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Duration", selection: $state.durationMinutes) {
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
                Text("4 hours").tag(240)
                Text("8 hours").tag(480)
                Text("12 hours").tag(720)
                Text("Indefinitely").tag(0)
            }
            .pickerStyle(.menu)

            Toggle(isOn: $state.lockOnLidClose) {
                Text("Lock & screen off on lid close")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if state.sleepDisabled {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleExternalCaffeinates(at: context.date)) { process in
                        Text("caffeinate running: \(process.parentName) · \(externalTimeText(process, at: context.date))")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            Toggle(isOn: $state.launchAtLogin) {
                Text("Launch at login")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if !state.sudoersInstalled {
                Button {
                    state.installSudoersRule()
                } label: {
                    Text("Allow toggling without password…")
                        .font(.caption)
                }
                .buttonStyle(.link)
                .help("Installs a sudoers rule scoped to pmset -a disablesleep at /etc/sudoers.d/vigil (requires admin authentication, once)")
            }

            Button("Quit Vigil") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            state.refreshSleepDisabled()
            state.refreshExternalCaffeinate()
        }
    }

    private var statusText: String {
        guard let seconds = state.remainingSeconds else {
            return "Active — no auto-off"
        }
        return "Sleep re-enabled in " + Self.formatDuration(seconds)
    }

    /// Hide entries whose end date has passed
    private func visibleExternalCaffeinates(at now: Date) -> [ExternalCaffeinate] {
        state.externalCaffeinates.filter { process in
            guard let endDate = process.endDate else { return true }
            return endDate > now
        }
    }

    private func externalTimeText(_ process: ExternalCaffeinate, at now: Date) -> String {
        guard process.hasTimeout else { return "indefinite" }
        guard let endDate = process.endDate else { return "time unknown" }
        return Self.formatDuration(max(0, Int(endDate.timeIntervalSince(now).rounded()))) + " left"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours) hr \(minutes) min" : "\(hours) hr"
        } else if minutes > 0 {
            return secs > 0 ? "\(minutes) min \(secs) sec" : "\(minutes) min"
        } else {
            return "\(secs) sec"
        }
    }
}
