import AppKit
import Carbon
import SwiftUI

// MARK: - A key combination

struct Shortcut: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = flags.intersection(Shortcut.relevantFlags).rawValue
    }

    init(_ keyCode: Int, _ flags: NSEvent.ModifierFlags = []) {
        self.init(keyCode: UInt16(keyCode), flags: flags)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        var code = event.keyCode
        // Treat the keypad Enter key like Return.
        if code == UInt16(kVK_ANSI_KeypadEnter) && keyCode == UInt16(kVK_Return) { code = keyCode }
        return code == keyCode && event.modifierFlags.intersection(Shortcut.relevantFlags) == flags
    }

    var hasCommandLikeModifier: Bool {
        !flags.intersection([.command, .option, .control]).isEmpty
    }

    var display: String { KeyNames.symbols(for: flags) + KeyNames.name(for: keyCode) }

    var carbonModifiers: UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }
}

// MARK: - Everything that can have a shortcut

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case openPasta
    case copySelected
    case moveDown
    case moveUp
    case togglePin
    case deleteItem
    case clearOrClose
    case openSettings

    var id: String { rawValue }

    /// Global shortcuts work from any app; the rest work while Pasta is open.
    var isGlobal: Bool { self == .openPasta }

    var title: String {
        switch self {
        case .openPasta: return "Open Pasta"
        case .copySelected: return "Copy selected item"
        case .moveDown: return "Select next item"
        case .moveUp: return "Select previous item"
        case .togglePin: return "Pin / unpin"
        case .deleteItem: return "Delete item"
        case .clearOrClose: return "Clear search / close"
        case .openSettings: return "Open Settings"
        }
    }

    var detail: String? {
        switch self {
        case .openPasta: return "Show or hide the history from anywhere"
        case .copySelected: return "Copies it and returns you to your app"
        case .clearOrClose: return "Clears the search first, then closes"
        default: return nil
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .openPasta: return Shortcut(kVK_ANSI_V, [.command, .shift])
        case .copySelected: return Shortcut(kVK_Return)
        case .moveDown: return Shortcut(kVK_DownArrow)
        case .moveUp: return Shortcut(kVK_UpArrow)
        case .togglePin: return Shortcut(kVK_ANSI_P, [.command])
        case .deleteItem: return Shortcut(kVK_Delete, [.command])
        case .clearOrClose: return Shortcut(kVK_Escape)
        case .openSettings: return Shortcut(kVK_ANSI_Comma, [.command])
        }
    }
}

/// Modifier used with the number keys 1–9 to copy an item quickly.
enum QuickCopyModifier: String, CaseIterable, Identifiable {
    case command, option, control, commandOption, off

    var id: String { rawValue }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .command: return [.command]
        case .option: return [.option]
        case .control: return [.control]
        case .commandOption: return [.command, .option]
        case .off: return []
        }
    }

    var symbol: String? { self == .off ? nil : KeyNames.symbols(for: flags) }

    var label: String {
        guard let s = symbol else { return "Off" }
        return "\(s)1 … \(s)9"
    }
}

// MARK: - Storage, recording and validation

final class ShortcutCenter: ObservableObject {
    static let shared = ShortcutCenter()

    /// A missing entry means "no shortcut".
    @Published private(set) var map: [ShortcutAction: Shortcut]
    @Published var quickCopy: QuickCopyModifier {
        didSet { UserDefaults.standard.set(quickCopy.rawValue, forKey: "quickCopy") }
    }
    @Published private(set) var recordingAction: ShortcutAction?
    @Published private(set) var recordingError: String?

    private var monitor: Any?

    static var defaults: [ShortcutAction: Shortcut] {
        var d: [ShortcutAction: Shortcut] = [:]
        for a in ShortcutAction.allCases { d[a] = a.defaultShortcut }
        return d
    }

    private init() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: "shortcuts"),
           let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            var m: [ShortcutAction: Shortcut] = [:]
            for (key, value) in saved {
                if let action = ShortcutAction(rawValue: key) { m[action] = value }
            }
            // Actions added in newer versions start with their default.
            let known = Set(ud.stringArray(forKey: "shortcutsKnown") ?? [])
            for a in ShortcutAction.allCases where !known.contains(a.rawValue) {
                m[a] = a.defaultShortcut
            }
            map = m
        } else {
            map = ShortcutCenter.defaults
        }
        quickCopy = QuickCopyModifier(rawValue: ud.string(forKey: "quickCopy") ?? "") ?? .command
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? { map[action] }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        map[action] = shortcut
        save()
    }

    func resetAll() {
        stopRecording()
        map = ShortcutCenter.defaults
        quickCopy = .command
        save()
    }

    /// Describes another shortcut that uses the same keys, if any.
    func conflict(for action: ShortcutAction) -> String? {
        guard let s = map[action] else { return nil }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && map[$0] == s }) {
            return other.title
        }
        if quickCopy != .off, s.flags == quickCopy.flags, KeyNames.digitCodes.contains(s.keyCode) {
            return "Quick copy"
        }
        return nil
    }

    // Recording

    func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recordingAction = action
        recordingError = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.record(event)
            return nil
        }
    }

    func stopRecording() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        recordingAction = nil
    }

    private func record(_ event: NSEvent) {
        guard let action = recordingAction else { return }
        let shortcut = Shortcut(keyCode: event.keyCode, flags: event.modifierFlags)

        if let problem = validate(shortcut, for: action) {
            // A plain Esc cancels when it can't be used anyway.
            if event.keyCode == UInt16(kVK_Escape) && shortcut.flags.isEmpty {
                stopRecording()
                return
            }
            recordingError = problem
            NSSound.beep()
            return
        }
        map[action] = shortcut
        save()
        stopRecording()
    }

    private func validate(_ s: Shortcut, for action: ShortcutAction) -> String? {
        if action.isGlobal {
            if !s.hasCommandLikeModifier && !KeyNames.functionKeys.contains(s.keyCode) {
                return "Shortcuts that work everywhere need ⌘, ⌥ or ⌃ (or an F-key)."
            }
        } else if !s.hasCommandLikeModifier && !KeyNames.plainAllowed.contains(s.keyCode) {
            return "Add ⌘, ⌥ or ⌃. Plain letters are used for typing in search."
        }
        return nil
    }

    private func save() {
        var out: [String: Shortcut] = [:]
        for (k, v) in map { out[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(out) {
            UserDefaults.standard.set(data, forKey: "shortcuts")
        }
        UserDefaults.standard.set(ShortcutAction.allCases.map { $0.rawValue }, forKey: "shortcutsKnown")
    }
}

// MARK: - Key names

enum KeyNames {
    static func symbols(for f: NSEvent.ModifierFlags) -> String {
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        return s
    }

    static let digitCodes: [UInt16] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ].map { UInt16($0) }

    static let functionKeys: Set<UInt16> = Set([
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
    ].map { UInt16($0) })

    /// Keys that are fine without ⌘/⌥/⌃ inside Pasta (they don't type text).
    static let plainAllowed: Set<UInt16> = functionKeys.union([
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape,
        kVK_UpArrow, kVK_DownArrow, kVK_PageUp, kVK_PageDown, kVK_Home, kVK_End,
    ].map { UInt16($0) })

    static let special: [UInt16: String] = {
        let pairs: [(Int, String)] = [
            (kVK_Return, "↩"), (kVK_ANSI_KeypadEnter, "⌤"), (kVK_Tab, "⇥"), (kVK_Space, "Space"),
            (kVK_Delete, "⌫"), (kVK_ForwardDelete, "⌦"), (kVK_Escape, "Esc"),
            (kVK_LeftArrow, "←"), (kVK_RightArrow, "→"), (kVK_UpArrow, "↑"), (kVK_DownArrow, "↓"),
            (kVK_Home, "↖"), (kVK_End, "↘"), (kVK_PageUp, "⇞"), (kVK_PageDown, "⇟"),
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"),
            (kVK_F5, "F5"), (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"),
            (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]
        var d: [UInt16: String] = [:]
        for (k, n) in pairs { d[UInt16(k)] = n }
        return d
    }()

    /// The key's label on the current keyboard layout (so it's right for Turkish, German, etc.).
    static func name(for keyCode: UInt16) -> String {
        if let s = special[keyCode] { return s }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

// MARK: - Recorder control used in Settings

struct ShortcutRecorder: View {
    let action: ShortcutAction
    @ObservedObject var center: ShortcutCenter = .shared

    private var recording: Bool { center.recordingAction == action }
    private var current: Shortcut? { center.map[action] }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                if recording { center.stopRecording() } else { center.startRecording(action) }
            } label: {
                Text(recording ? "Press keys…" : (current?.display ?? "None"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(recording ? Color.accentColor : (current == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 110)
            }
            .help(recording ? "Press the new keys now — click again to cancel" : "Click to record a new shortcut")

            Button { center.set(nil, for: action) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .disabled(current == nil)
            .opacity(current == nil ? 0.3 : 1)
            .help("Remove shortcut")

            Button { center.set(action.defaultShortcut, for: action) } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(current == action.defaultShortcut)
            .help("Reset to default (\(action.defaultShortcut.display))")
        }
    }
}
