//
//  PopupWindow.swift
//  ClipBox
//

import Cocoa
import SwiftUI

// MARK: - KeyablePanel

/// A custom `NSPanel` subclass that can receive keyboard input even though
/// it uses `.nonactivatingPanel` style.
///
/// ## The problem this solves
/// We want the popup to:
///   - Accept key presses (Esc, arrow keys, Enter) so the user can navigate.
///   - NOT steal focus from the app the user was working in (so paste goes
///     to the right place).
///
/// The standard approach is `.nonactivatingPanel`, which keeps focus in the
/// previous app. However, a non-activating panel is never made the "key window",
/// which means `NSEvent.addLocalMonitorForEvents` never delivers keys to it.
/// Using `addGlobalMonitorForEvents` almost works, but Apple deliberately blocks
/// Escape (keyCode 53) from global monitors for security reasons.
///
/// ## The fix
/// By subclassing `NSPanel` and overriding `canBecomeKey = true`, we let the
/// panel become the key window (so it directly receives key events through
/// `keyDown`) while `nonactivatingPanel` in the style mask still prevents
/// ClipBox from becoming the *active application* — the previous app remains
/// frontmost in `NSWorkspace`.
private class KeyablePanel: NSPanel {

    /// Called by PopupWindow to forward key presses to SwiftUI via NotificationCenter.
    var onKeyDown: ((UInt16) -> Void)?

    /// Returning `true` allows `makeKeyAndOrderFront` to promote this panel
    /// to key window status, enabling direct `keyDown` delivery.
    override var canBecomeKey: Bool { true }

    /// We never want this panel to be the main window (that would affect menu
    /// bar state), so we keep this false.
    override var canBecomeMain: Bool { false }

    /// Called by macOS for every key press while this panel is the key window.
    /// We forward the key code to our closure instead of calling `super`
    /// (which would trigger the default beep for unhandled keys).
    override func keyDown(with event: NSEvent) {
        onKeyDown?(event.keyCode)
    }
}

// MARK: - PopupWindow

/// Manages the lifecycle of the floating clipboard history popup.
///
/// Responsibilities:
/// - Creating and positioning the `KeyablePanel` near the cursor.
/// - Storing which app was active before the popup opened.
/// - Closing the popup on outside clicks.
/// - Orchestrating the activate-then-paste sequence when the user picks an item.
class PopupWindow {

    // MARK: - Singleton

    static let shared = PopupWindow()

    // MARK: - Private State

    /// The panel currently on screen, or `nil` when the popup is closed.
    private var panel: KeyablePanel?

    /// A global event monitor that watches for mouse clicks anywhere on screen.
    /// Used to dismiss the popup when the user clicks outside it.
    private var mouseMonitor: Any?

    /// Tracks whether the popup is currently displayed. Used as a guard to
    /// prevent duplicate `show()` or `close()` calls.
    private var isVisible = false

    /// The app that was frontmost *before* we opened the popup.
    /// We restore focus to this app before sending the ⌘V paste event, so
    /// the text lands in the right place.
    private var previousApp: NSRunningApplication?

    /// The last position where the popup was shown. Used when "Follow Cursor" is off.
    private var lastPosition: NSPoint?

    /// UserDefaults key for the follow cursor preference.
    private static let followCursorKey = "com.clipbox.followCursor"

    /// Whether the popup should open at the cursor position or at its last location.
    var followCursor: Bool {
        get { UserDefaults.standard.object(forKey: Self.followCursorKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.followCursorKey) }
    }

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Opens the popup if closed, or closes it if already open.
    func toggle() {
        isVisible ? close() : show()
    }

    // MARK: - Show

    func show() {
        guard !isVisible else { return }
        isVisible = true

        // ① Capture the frontmost app NOW, before we do anything that might
        //   change which app macOS considers active.
        previousApp = NSWorkspace.shared.frontmostApplication

        // ② Capture cursor position for placement. We read this early so even
        //   if the user moves the mouse during panel setup it stays where expected.
        let mouseLocation = NSEvent.mouseLocation

        // ③ Build the SwiftUI view, passing closures for close and paste actions.
        let popupView = PopupView(
            onClose: { [weak self] in
                self?.close()
            },
            onPaste: { [weak self] item in
                guard let self = self else { return }

                // Snapshot previousApp before closing (close() may run async code).
                let appToRestore = self.previousApp
                self.close()

                // Timing sequence:
                //   T+0ms    — popup is closed / ordered out
                //   T+80ms   — re-activate the previous app
                //   T+200ms  — send ⌘V (app must be fully active first)
                //
                // Without the delay between activate and paste, macOS may not
                // have finished switching focus and the paste goes nowhere.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    appToRestore?.activate(options: .activateIgnoringOtherApps)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        ClipboardManager.shared.paste(item: item)
                    }
                }
            }
        )

        // ④ Create the panel.
        let newPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [
                .borderless,          // No title bar, no resize handles.
                .nonactivatingPanel   // Does NOT make ClipBox the active app.
            ],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false          // Required for clear/transparent background.
        newPanel.backgroundColor = .clear  // Let SwiftUI's .regularMaterial show through.
        newPanel.level = .floating         // Always on top of regular windows.
        newPanel.hasShadow = false         // Shadow is handled in SwiftUI for clean corners.
        newPanel.isMovableByWindowBackground = true
        newPanel.ignoresMouseEvents = false // We need clicks to register for row selection.
        newPanel.collectionBehavior = [
            .canJoinAllSpaces,       // Show on every Space (virtual desktop).
            .fullScreenAuxiliary     // Also show when another app is in full-screen.
        ]
        newPanel.contentView = NSHostingView(rootView: popupView)

        // ⑤ Wire up key forwarding from the panel to SwiftUI via NotificationCenter.
        newPanel.onKeyDown = { [weak self] keyCode in
            guard self?.isVisible == true else { return }
            NotificationCenter.default.post(
                name: .clipBoxKeyDown,
                object: nil,
                userInfo: ["keyCode": keyCode]
            )
        }

        // ⑥ Position near the cursor (or at last position if Follow Cursor is off).
        if !followCursor, let lastPos = lastPosition {
            newPanel.setFrameOrigin(lastPos)
        } else {
            positionPanel(newPanel, at: mouseLocation)
        }

        // `makeKeyAndOrderFront` makes the panel the key window (so it gets keyDown)
        // AND shows it on screen. Because of `.nonactivatingPanel`, ClipBox does NOT
        // become the active application — the previous app stays focused in the Dock
        // and menu bar.
        newPanel.makeKeyAndOrderFront(nil)
        self.panel = newPanel

        // ⑦ Global mouse monitor to close popup on outside click.
        //   We use the *global* monitor because our panel is non-activating — local
        //   monitors don't fire for clicks that land in other apps' windows.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.close()
        }
    }

    // MARK: - Close

    /// Hides the popup and cleans up all event monitors.
    func close() {
        guard isVisible else { return }
        isVisible = false

        // Always remove monitors before releasing the panel, to avoid dangling callbacks.
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }

        // Save position before closing so we can reopen here if Follow Cursor is off.
        if let frame = panel?.frame {
            lastPosition = frame.origin
        }

        panel?.orderOut(nil) // Hides the panel without destroying it.
        panel = nil
    }

    // MARK: - Positioning

    /// Calculates the best origin point for the panel so it appears next to
    /// `cursor` without overflowing any edge of the screen.
    ///
    /// Default placement: just right of and slightly below the cursor.
    /// If that would clip a screen edge, we mirror to the opposite side.
    private func positionPanel(_ panel: NSPanel, at cursor: CGPoint) {
        let size   = NSSize(width: 340, height: 380)
        let offset: CGFloat = 10

        // Find which screen the cursor is on. Fall back to the main screen.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursor, $0.frame, false) })
                ?? NSScreen.main else {
            panel.setFrameOrigin(cursor)
            return
        }

        // `visibleFrame` excludes the menu bar and Dock, so we don't overlap them.
        let sf = screen.visibleFrame

        // Default: place to the right of the cursor and above the cursor.
        // (macOS Y axis goes up, so subtracting the height moves origin downward.)
        var x = cursor.x + offset
        var y = cursor.y - size.height - offset

        // Clamp right edge: if the panel would go off the right side, flip to the left.
        if x + size.width > sf.maxX { x = cursor.x - size.width - offset }

        // Clamp bottom edge: if the panel would go below the Dock, flip upward.
        if y < sf.minY { y = cursor.y + offset }

        // Clamp top edge: if the panel would exceed the menu bar, pin to top.
        if y + size.height > sf.maxY { y = sf.maxY - size.height - offset }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
