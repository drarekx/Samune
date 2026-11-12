import AppKit
import Carbon
import Combine

/// A global key combination: a virtual key code plus Cocoa modifiers.
struct Hotkey: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    /// ⌥Space.
    static let `default` = Hotkey(keyCode: UInt32(kVK_Space), modifiers: [.option])

    /// Modifiers a hotkey may use.
    static let allowedModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Hotkey.allowedModifiers)
    }

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// Key caps in macOS order: ⌃ ⌥ ⇧ ⌘ and the key.
    @MainActor
    var caps: [String] {
        var caps: [String] = []
        if modifiers.contains(.control) { caps.append("⌃") }
        if modifiers.contains(.option) { caps.append("⌥") }
        if modifiers.contains(.shift) { caps.append("⇧") }
        if modifiers.contains(.command) { caps.append("⌘") }
        caps.append(KeyNames.name(for: keyCode))
        return caps
    }
}

/// Human names of virtual key codes.
@MainActor
enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    static func name(for keyCode: UInt32) -> String {
        if Int(keyCode) == kVK_Space { return tr("Espacio") }
        if let name = special[Int(keyCode)] { return name }
        if let typed = translate(keyCode), !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return typed.uppercased()
        }
        return "#\(keyCode)"
    }

    /// The character the key types with the current keyboard layout (letters, digits, punctuation).
    private static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Registers the global shortcut with Carbon `RegisterEventHotKey` (needs no permissions)
/// and records new combinations for the settings card.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    @Published private(set) var hotkey: Hotkey
    /// False when the system refused the combination (taken by the system or another app).
    @Published private(set) var isRegistered = false
    @Published private(set) var isRecording = false

    /// Called on the main actor when the shortcut is pressed.
    var onPress: (() -> Void)?

    private static let keyCodeKey = "hotkeyKeyCode"
    private static let modifiersKey = "hotkeyModifiers"
    private static let signature: OSType = 0x534D_4E45 // "SMNE"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var recordMonitor: Any?

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.keyCodeKey) != nil {
            hotkey = Hotkey(keyCode: UInt32(clamping: defaults.integer(forKey: Self.keyCodeKey)),
                            modifiers: NSEvent.ModifierFlags(rawValue: UInt(clamping: defaults.integer(forKey: Self.modifiersKey))))
        } else {
            hotkey = .default
        }
    }

    /// Installs the Carbon handler and registers the saved shortcut.
    func start() {
        installHandler()
        register()
    }

    func set(_ newValue: Hotkey) {
        hotkey = newValue
        UserDefaults.standard.set(Int(newValue.keyCode), forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(newValue.modifiers.rawValue), forKey: Self.modifiersKey)
        if !isRecording { register() }
    }

    func reset() { set(.default) }

    // MARK: - Recording

    /// Listens for the next key-down with ⌃, ⌥ or ⌘ in this app. Esc cancels.
    /// The global shortcut is off meanwhile, so pressing the current one can record it again.
    func startRecording() {
        guard !isRecording else { return }
        unregister()
        isRecording = true
        recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.record(event) ?? false }
            return handled ? nil : event
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        if let recordMonitor { NSEvent.removeMonitor(recordMonitor) }
        recordMonitor = nil
        isRecording = false
        register()
    }

    private func record(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(Hotkey.allowedModifiers)
        if Int(event.keyCode) == kVK_Escape, modifiers.isEmpty {
            stopRecording()
            return true
        }
        // Shift alone would steal capital letters everywhere.
        guard !modifiers.intersection([.control, .option, .command]).isEmpty else {
            NSSound.beep()
            return true
        }
        set(Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers))
        stopRecording()
        return true
    }

    // MARK: - Carbon

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotkeyManager.shared.onPress?() }
            }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    private func register() {
        unregister()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = status == noErr ? ref : nil
        isRegistered = hotKeyRef != nil
    }

    private func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
