import AppKit
import ServiceManagement
import SwiftUI

struct ExternalCaffeinate: Identifiable, Equatable {
    let pid: Int32
    let parentName: String
    let hasTimeout: Bool
    /// Estimated end date when hasTimeout is true (derived from start time and the -t value)
    let endDate: Date?

    var id: Int32 { pid }
}

@MainActor
final class AwakeState: ObservableObject {
    static let shared = AwakeState()

    private static let sudoersPath = "/etc/sudoers.d/vigil"
    private static let autoOffEndDateKey = "autoOffEndDate"
    private static let lockOnLidCloseKey = "lockOnLidClose"

    private static var sudoersRuleExists: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    @Published private(set) var sleepDisabled = false
    /// Seconds until sleep is automatically re-enabled; nil when no auto-off is scheduled
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var externalCaffeinates: [ExternalCaffeinate] = []
    @Published private(set) var sudoersInstalled = AwakeState.sudoersRuleExists

    /// 0 means indefinitely
    @Published var durationMinutes = 60 {
        didSet {
            guard durationMinutes != oldValue else { return }
            if sleepDisabled {
                scheduleAutoOff()
            }
        }
    }

    /// While Keep Awake is on, lock and turn off the display when the lid closes
    /// (disablesleep also suppresses the display-off that normally accompanies lid close)
    @Published var lockOnLidClose: Bool {
        didSet {
            UserDefaults.standard.set(lockOnLidClose, forKey: Self.lockOnLidCloseKey)
        }
    }

    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            let enabled = SMAppService.mainApp.status == .enabled
            guard launchAtLogin != enabled else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var clamshellMonitor: ClamshellMonitor?
    private var countdownTimer: Timer?
    /// Persisted so the auto-off deadline survives an app restart
    private var autoOffEndDate: Date? {
        didSet {
            if let autoOffEndDate {
                UserDefaults.standard.set(autoOffEndDate, forKey: Self.autoOffEndDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.autoOffEndDateKey)
            }
        }
    }

    private init() {
        lockOnLidClose = UserDefaults.standard.object(forKey: Self.lockOnLidCloseKey) as? Bool ?? true
        clamshellMonitor = ClamshellMonitor { [weak self] isClosed in
            guard let self, isClosed, self.sleepDisabled, self.lockOnLidClose else { return }
            Self.lockAndTurnOffDisplay()
        }
    }

    var isActive: Bool { sleepDisabled }

    var menuBarImage: NSImage {
        Self.candleImage(active: isActive)
    }

    /// Candle from the bundled SVG (same artwork as the app icon).
    /// Inactive renders as a template image; active is lit orange.
    private static func candleImage(active: Bool) -> NSImage {
        let base = candleSVG
        guard active else {
            let image = base.copy() as! NSImage
            image.isTemplate = true
            return image
        }
        return NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.systemOrange.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private static let candleSVG: NSImage = {
        let fallbackSize = NSSize(width: 10, height: 18)
        guard let url = Bundle.module.url(forResource: "candle", withExtension: "svg"),
              let image = NSImage(contentsOf: url), image.size.height > 0
        else { return NSImage(size: fallbackSize) }
        let height: CGFloat = 18
        image.size = NSSize(width: image.size.width * height / image.size.height, height: height)
        return image
    }()

    // MARK: - Keep Awake (pmset disablesleep + auto-off timer)

    func setKeepAwake(_ on: Bool) {
        setSleepDisabled(on)
        if on {
            scheduleAutoOff()
        } else {
            cancelAutoOff()
        }
    }

    func refreshSleepDisabled() {
        Task.detached {
            let output = Self.run("/usr/bin/pmset", ["-g"]).output
            let disabled = output.split(separator: "\n").contains { line in
                line.contains("SleepDisabled") && line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
            }
            await MainActor.run {
                let state = AwakeState.shared
                state.sleepDisabled = disabled
                state.reconcileAutoOff()
            }
        }
    }

    private func setSleepDisabled(_ on: Bool, interactive: Bool = true) {
        let value = on ? "1" : "0"
        sleepDisabled = on
        Task.detached {
            // With the sudoers rule installed this succeeds immediately without a password
            var result = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])
            if result.status != 0, interactive {
                let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
                result = Self.run("/usr/bin/osascript", ["-e", script])
            }
            await MainActor.run {
                AwakeState.shared.refreshSleepDisabled()
            }
        }
    }

    /// Bring the auto-off timer in line with the actual disablesleep state,
    /// including a deadline persisted across an app restart.
    private func reconcileAutoOff() {
        guard sleepDisabled else {
            cancelAutoOff()
            return
        }
        guard autoOffEndDate == nil,
              let stored = UserDefaults.standard.object(forKey: Self.autoOffEndDateKey) as? Date
        else { return }
        if stored > Date() {
            resumeAutoOff(until: stored)
        } else {
            // The deadline passed while the app wasn't running; re-enable sleep
            // silently (succeeds only when the sudoers rule is installed)
            UserDefaults.standard.removeObject(forKey: Self.autoOffEndDateKey)
            setSleepDisabled(false, interactive: false)
        }
    }

    private func scheduleAutoOff() {
        cancelAutoOff()
        guard durationMinutes > 0 else { return }
        resumeAutoOff(until: Date().addingTimeInterval(TimeInterval(durationMinutes * 60)))
    }

    private func resumeAutoOff(until endDate: Date) {
        autoOffEndDate = endDate
        updateRemaining()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func cancelAutoOff() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        autoOffEndDate = nil
        remainingSeconds = nil
    }

    private func tick() {
        updateRemaining()
        if let remainingSeconds, remainingSeconds <= 0 {
            cancelAutoOff()
            setSleepDisabled(false)
        }
    }

    private func updateRemaining() {
        guard let autoOffEndDate else { return }
        remainingSeconds = max(0, Int(autoOffEndDate.timeIntervalSinceNow.rounded()))
    }

    /// Called from applicationWillTerminate — always re-enable sleep before quitting.
    /// Runs synchronously because the process exits right after this returns.
    func turnOffBeforeQuit() {
        cancelAutoOff()
        guard sleepDisabled else { return }
        let result = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
        if result.status != 0 {
            let script = "do shell script \"/usr/bin/pmset -a disablesleep 0\" with administrator privileges"
            _ = Self.run("/usr/bin/osascript", ["-e", script])
        }
    }

    // MARK: - Lock on lid close

    nonisolated private static func lockAndTurnOffDisplay() {
        lockScreen()
        // Give the lock screen a moment to come up before sleeping the display
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            _ = run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    /// SACLockScreenImmediate from the private login.framework — same as the
    /// "Lock Screen" menu item; the session locks but processes keep running
    nonisolated private static func lockScreen() {
        typealias LockScreenFunc = @convention(c) () -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate")
        else { return }
        let lock = unsafeBitCast(symbol, to: LockScreenFunc.self)
        _ = lock()
    }

    // MARK: - External caffeinate (display only)

    /// Detect caffeinate processes running on the system (display only)
    func refreshExternalCaffeinate() {
        Task.detached {
            let processes = Self.findExternalCaffeinates()
            await MainActor.run {
                AwakeState.shared.externalCaffeinates = processes
            }
        }
    }

    nonisolated private static func findExternalCaffeinates() -> [ExternalCaffeinate] {
        let output = run("/usr/bin/pgrep", ["-x", "caffeinate"]).output
        let pids = output.split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        guard !pids.isEmpty else { return [] }

        var result: [ExternalCaffeinate] = []
        for pid in pids {
            let info = run("/bin/ps", ["-o", "ppid=,etime=,args=", "-p", String(pid)]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !info.isEmpty else { continue }
            let tokens = info.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 2, let ppid = Int32(tokens[0]) else { continue }
            let elapsed = parseElapsedTime(tokens[1])
            let args = Array(tokens.dropFirst(2))

            var hasTimeout = false
            var endDate: Date?
            if let tIndex = args.firstIndex(of: "-t"), tIndex + 1 < args.count,
               let timeout = Double(args[tIndex + 1]) {
                hasTimeout = true
                if let elapsed {
                    endDate = Date(timeIntervalSinceNow: timeout - Double(elapsed))
                }
            }

            result.append(ExternalCaffeinate(
                pid: pid,
                parentName: parentProcessName(of: ppid),
                hasTimeout: hasTimeout,
                endDate: endDate
            ))
        }
        return result
    }

    /// Convert ps etime ([[dd-]hh:]mm:ss) to seconds
    nonisolated private static func parseElapsedTime(_ etime: String) -> Int? {
        var days = 0
        var hms = etime
        let dayParts = etime.split(separator: "-")
        if dayParts.count == 2 {
            guard let d = Int(dayParts[0]) else { return nil }
            days = d
            hms = String(dayParts[1])
        }
        let fields = hms.split(separator: ":")
        let numbers = fields.compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count == fields.count else { return nil }
        var seconds = 0
        for n in numbers {
            seconds = seconds * 60 + n
        }
        return days * 86_400 + seconds
    }

    nonisolated private static func parentProcessName(of pid: Int32) -> String {
        let comm = run("/bin/ps", ["-o", "comm=", "-p", String(pid)]).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comm.isEmpty else { return "unknown" }
        return (comm as NSString).lastPathComponent
    }

    // MARK: - sudoers

    /// Install a sudoers rule (with admin authentication) that allows toggling pmset
    /// without a password. Scoped to the pmset -a disablesleep commands only.
    func installSudoersRule() {
        let user = NSUserName()
        let line = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        let shell = [
            "echo '\(line)' > /private/tmp/vigil.sudoers",
            "/usr/sbin/visudo -cf /private/tmp/vigil.sudoers",
            "/bin/mv /private/tmp/vigil.sudoers \(Self.sudoersPath)",
            "/usr/sbin/chown root:wheel \(Self.sudoersPath)",
            "/bin/chmod 440 \(Self.sudoersPath)",
        ].joined(separator: " && ")
        let script = "do shell script \"\(shell)\" with administrator privileges"
        Task.detached {
            _ = Self.run("/usr/bin/osascript", ["-e", script])
            await MainActor.run {
                AwakeState.shared.sudoersInstalled = Self.sudoersRuleExists
            }
        }
    }

    // MARK: - Shell

    nonisolated private static func run(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
