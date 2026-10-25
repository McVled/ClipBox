//
//  Shortcut.swift
//  ClipBox
//

import AppKit

/// Represents a user-configurable global keyboard shortcut.
///
/// Stored in `UserDefaults` as JSON so the user's choice survives restarts.
/// `keyLabel` is captured at record time from `NSEvent.charactersIgnoringModifiers`
/// so we can display the key (e.g. "V", "F2") without doing a keycode → key map
/// lookup (which varies by keyboard layout).
struct Shortcut: Codable, Equatable {

    var command: Bool
    var shift:   Bool
    var option:  Bool
    var control: Bool

    /// Hardware key code (same across all keyboard layouts).
    var keyCode: UInt16

    /// Display label for the key (e.g. "V", "F2", "↑"). Captured at record time.
    var keyLabel: String

    /// Default: ⌘⇧V
    static let `default` = Shortcut(
        command: true,
        shift:   true,
        option:  false,
        control: false,
        keyCode: 9,
        keyLabel: "V"
    )

    /// Hardware key codes for F1–F12. These keys never produce text, so they
    /// are safe to bind with ⇧ alone.
    private static let functionKeyCodes: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
    ]

    /// True if the combination is safe to intercept globally. It must include
    /// ⌘, ⌥ or ⌃ — ⇧ alone is not enough for a typing key, because ⇧A or ⇧1
    /// would swallow every capital A or "!" typed system-wide. ⇧ alone is
    /// accepted only for F1–F12.
    var hasModifier: Bool {
        if command || option || control { return true }
        return shift && Self.functionKeyCodes.contains(keyCode)
    }

    /// Pretty string for the UI, e.g. "⌃⌥⇧⌘V".
    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option  { s += "⌥" }
        if shift   { s += "⇧" }
        if command { s += "⌘" }
        s += keyLabel
        return s
    }

    /// Each component as a separate string, used to render individual key badges.
    /// e.g. ["⌘", "⇧", "V"]
    var displayComponents: [String] {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option  { parts.append("⌥") }
        if shift   { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(keyLabel)
        return parts
    }
}
