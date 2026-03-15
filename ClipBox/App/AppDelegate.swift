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
    }

    // MARK: - Quit

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up: stop the clipboard timer and remove the CGEventTap.
        ClipboardManager.shared.stopMonitoring()
        HotkeyManager.shared.stop()
    }

    // MARK: - Reopen

    /// Returning `false` here prevents macOS from re-showing a window when
    /// the user clicks the (hidden) Dock icon or uses Cmd+Tab.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
