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

    /// True if at least one modifier is set. We require this so the user can't
    /// accidentally bind a plain letter, which would intercept normal typing.
    var hasModifier: Bool {
        command || shift || option || control
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
