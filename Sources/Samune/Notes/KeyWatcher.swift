import AppKit
import Carbon.HIToolbox

/// Optional double ⌘C detection from the keyboard, for apps that don't write the clipboard again
/// when the text hasn't changed (iTerm2). Listen-only event tap: needs Input Monitoring, never
/// changes or blocks keys. When it runs, `ClipboardWatcher` stops detecting double copies itself.
@MainActor
final class KeyWatcher: ObservableObject {
    static let shared = KeyWatcher()

    /// The tap is installed and receiving keys.
    @Published private(set) var isRunning = false
    /// Input Monitoring is granted.
    @Published private(set) var hasPermission = CGPreflightListenEventAccess()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastCommandC: Date?
    private var retryTimer: Timer?

    /// Starts or stops the tap to match the setting. `ask` shows the system permission prompt.
    func refresh(ask: Bool = false) {
        hasPermission = CGPreflightListenEventAccess()
        guard NotesSettings.shared.keyboardDetection, NotesSettings.shared.doubleCopy else { stop(); return }
        if !hasPermission && ask {
            CGRequestListenEventAccess()
            hasPermission = CGPreflightListenEventAccess()
        }
        if hasPermission && tap == nil { start() }
        // Permission granted later in System Settings: pick it up without relaunching.
        if !isRunning && retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                MainActor.assumeIsolated { KeyWatcher.shared.refresh() }
            }
        } else if isRunning {
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    private func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: keyCallback, userInfo: nil) else {
            isRunning = false
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        isRunning = true
    }

    private func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isRunning = false
        lastCommandC = nil
    }

    /// The system disables slow taps: turn it back on.
    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    fileprivate func commandC() {
        let now = Date()
        if let last = lastCommandC, now.timeIntervalSince(last) <= NotesSettings.shared.doubleCopyWindow {
            lastCommandC = nil
            // Give the app time to write the clipboard after the key.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                ClipboardWatcher.shared.saveCurrent()
            }
        } else {
            lastCommandC = now
        }
    }
}

private func keyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { MainActor.assumeIsolated { KeyWatcher.shared.reenable() } }
    } else if type == .keyDown,
              event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_ANSI_C),
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if flags == .maskCommand {
            DispatchQueue.main.async { MainActor.assumeIsolated { KeyWatcher.shared.commandC() } }
        }
    }
    return Unmanaged.passUnretained(event)
}
