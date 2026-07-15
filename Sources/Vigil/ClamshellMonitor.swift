import Foundation
import IOKit

/// Watches the lid (clamshell) state via an IOPMrootDomain interest notification —
/// event-driven, no polling.
final class ClamshellMonitor {
    /// kIOPMMessageClamshellStateChange from IOPMPrivate.h:
    /// iokit_family_msg(sub_iokit_powermanagement, 0x100)
    private static let clamshellStateChangeMessage: UInt32 = 0xE003_4100
    /// kClamshellStateBit — set in the message argument while the lid is closed
    private static let clamshellStateBit: UInt = 1

    private let onChange: (_ isClosed: Bool) -> Void
    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var rootDomain: io_service_t = IO_OBJECT_NULL

    init?(onChange: @escaping (_ isClosed: Bool) -> Void) {
        self.onChange = onChange

        rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return nil }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            IOObjectRelease(rootDomain)
            return nil
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)

        let callback: IOServiceInterestCallback = { refcon, _, messageType, messageArgument in
            guard messageType == ClamshellMonitor.clamshellStateChangeMessage, let refcon else { return }
            let monitor = Unmanaged<ClamshellMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let state = UInt(bitPattern: messageArgument)
            monitor.onChange(state & ClamshellMonitor.clamshellStateBit != 0)
        }

        let result = IOServiceAddInterestNotification(
            port,
            rootDomain,
            kIOGeneralInterest,
            callback,
            Unmanaged.passUnretained(self).toOpaque(),
            &notifier
        )
        guard result == KERN_SUCCESS else {
            IONotificationPortDestroy(port)
            IOObjectRelease(rootDomain)
            return nil
        }
    }

    deinit {
        if notifier != IO_OBJECT_NULL {
            IOObjectRelease(notifier)
        }
        if let notificationPort {
            IONotificationPortDestroy(notificationPort)
        }
        if rootDomain != IO_OBJECT_NULL {
            IOObjectRelease(rootDomain)
        }
    }
}
