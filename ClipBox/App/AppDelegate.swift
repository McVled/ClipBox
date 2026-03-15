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
///   - Create a small menu bar icon so the user can quit the app cleanly.
///
/// Even though ClipBox has no Dock icon (`LSUIElement = YES`), it shows a
/// subtle icon in the menu bar (the system tray area on the right). Clicking
/// it reveals a small menu with "Open ClipBox" and "Quit" options.
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// The item that lives in the macOS menu bar (top-right area).
    /// Keeping a strong reference here prevents it from being deallocated.
    private var statusItem: NSStatusItem?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the default empty SwiftUI window.
        // ClipBox lives entirely in the floating popup — there's no main window.
        if let window = NSApp.windows.first {
            window.orderOut(nil)
        }

        // Build the menu bar icon and its dropdown menu.
        setupMenuBarIcon()

        // Start polling NSPasteboard every 0.5s so we build up history.
        ClipboardManager.shared.startMonitoring()

        // Register ⌘⇧V system-wide. When pressed, toggle the popup.
        HotkeyManager.shared.onTrigger = {
            PopupWindow.shared.toggle()
        }
        HotkeyManager.shared.start()
    }

    // MARK: - Menu Bar

    /// Creates the status bar item (the small icon in the top-right menu bar)
    /// and attaches a dropdown menu with basic controls.
    private func setupMenuBarIcon() {
        // `NSStatusBar.system.statusItem` allocates a slot in the menu bar.
        // `.variableLength` lets the icon size itself naturally.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        // Use a clipboard SF Symbol as the icon.
        // `.template` tint means macOS automatically inverts the icon for
        // light/dark menu bar and applies the correct active/inactive tint.
        button.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "ClipBox"
        )
        button.image?.isTemplate = true
        button.toolTip = "ClipBox — Clipboard History"

        // Build the dropdown menu that appears when the user clicks the icon.
        let menu = NSMenu()

        // ── Open ClipBox ──────────────────────────────────────────────────
        // Same action as pressing ⌘⇧V — shows the popup near the menu bar.
        let openItem = NSMenuItem(
            title: "Open ClipBox",
            action: #selector(openClipBox),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // ── History count label (informational, not clickable) ────────────
        let infoItem = NSMenuItem(
            title: "Clipboard history: \(ClipboardManager.shared.history.count) items",
            action: nil,
            keyEquivalent: ""
        )
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        menu.addItem(.separator())

        // ── Clear History ─────────────────────────────────────────────────
        let clearItem = NSMenuItem(
            title: "Clear History",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        // ── Quit ──────────────────────────────────────────────────────────
        let quitItem = NSMenuItem(
            title: "Quit ClipBox",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Keep history count label up to date whenever history changes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateHistoryCount),
            name: .clipBoxHistoryChanged,
            object: nil
        )
    }

    // MARK: - Menu Actions

    /// Opens the clipboard popup — same as pressing ⌘⇧V.
    @objc private func openClipBox() {
        PopupWindow.shared.toggle()
    }

    /// Wipes all stored clipboard history.
    @objc private func clearHistory() {
        ClipboardManager.shared.clearHistory()
    }

    /// Refreshes the "X items" label in the menu whenever history changes.
    @objc private func updateHistoryCount() {
        guard let menu = statusItem?.menu else { return }
        // The info item is at index 2 (Open, separator, info…)
        if let infoItem = menu.item(at: 2) {
            infoItem.title = "Clipboard history: \(ClipboardManager.shared.history.count) items"
        }
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
