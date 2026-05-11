//
//  AppDelegate.swift
//  ClipBox
//

import Cocoa
import SwiftUI

/// The application delegate — the first code that runs after launch.
///
/// Its job is to wire together all the major components:
///   - Start `ClipboardManager` so it begins recording copies.
///   - Register the global hotkey in `HotkeyManager` so ⌘⇧V works anywhere.
///   - Tell `PopupWindow` to open when the hotkey fires.
///
/// Clear History and Quit are handled directly inside `PopupView`, so
/// AppDelegate stays minimal — no menu bar icon needed.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State

    /// Observer that disables the pop-in animation on every NSPopover the app
    /// presents. Kept as a property so we can deregister it on terminate.
    private var popoverAnimationObserver: NSObjectProtocol?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the default empty SwiftUI window.
        // ClipBox lives entirely in the floating popup — there's no main window.
        if let window = NSApp.windows.first {
            window.orderOut(nil)
        }

        // Start polling NSPasteboard every 0.5s so we build up history.
        ClipboardManager.shared.startMonitoring()

        // Register ⌘⇧V system-wide. When pressed, toggle the popup.
        HotkeyManager.shared.onTrigger = {
            PopupWindow.shared.toggle()
        }
        HotkeyManager.shared.start()

        // Install the optional menu-bar icon if the user has it enabled.
        StatusBarController.shared.applyCurrentSetting()

        // Disable popover animations app-wide.  SwiftUI's `.popover()` modifier
        // creates a stock NSPopover whose `animates` flag defaults to true,
        // producing a small but noticeable pop-in animation.  We catch every
        // popover at willShow time — before NSPopover reads the flag to set
        // up its appearance — and turn it off so popovers appear instantly.
        popoverAnimationObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.willShowNotification,
            object:  nil,
            queue:   .main
        ) { note in
            (note.object as? NSPopover)?.animates = false
        }
    }

    // MARK: - Quit

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up: stop the clipboard timer and remove the CGEventTap.
        ClipboardManager.shared.stopMonitoring()
        HotkeyManager.shared.stop()

        if let obs = popoverAnimationObserver {
            NotificationCenter.default.removeObserver(obs)
            popoverAnimationObserver = nil
        }
    }

    // MARK: - Reopen

    /// Returning `false` here prevents macOS from re-showing a window when
    /// the user clicks the (hidden) Dock icon or uses Cmd+Tab.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
