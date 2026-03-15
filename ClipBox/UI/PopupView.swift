//
//  PopupView.swift
//  ClipBox
//

import SwiftUI

/// The main SwiftUI view rendered inside the floating popup panel.
///
/// Layout (top to bottom):
///   1. Header — icon, title, shortcut badge
///   2. Divider
///   3. Scrollable list of `ClipboardRowView` items  (or an empty-state message)
///   4. Divider
///   5. Footer — keyboard hint labels
///
/// ## Keyboard navigation
/// Arrow keys and Enter/Escape are forwarded here via `NotificationCenter`
/// from `PopupWindow.KeyablePanel.keyDown`. We use a notification instead of
/// a SwiftUI `onKeyPress` modifier because the panel is a non-activating window
/// and SwiftUI's built-in key handling only works when the view has focus.
struct PopupView: View {

    // MARK: - Dependencies

    /// We observe `ClipboardManager.history` directly so the list updates
    /// in real time whenever a new item is copied.
    @ObservedObject var clipboardManager = ClipboardManager.shared

    // MARK: - State

    /// The index of the currently highlighted row. Starts at 0 (most recent item).
    /// Changed by arrow-key presses; triggers scrolling and highlight updates.
    @State private var selectedIndex: Int = 0

    // MARK: - Callbacks

    /// Called when the popup should close (Escape key or external click).
    var onClose: () -> Void

    /// Called when the user selects an item to paste (click or Enter key).
    var onPaste: (ClipboardItem) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("Clipboard History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                // Small pill showing the keyboard shortcut, purely decorative.
                Text("⌘⇧V")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            // ── List or empty state ───────────────────────────────────────
            if clipboardManager.history.isEmpty {
                // Nothing has been copied yet — show a gentle placeholder.
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("History is empty")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30)

            } else {
                // `ScrollViewReader` lets us programmatically scroll to any row
                // by its ID when `selectedIndex` changes (arrow key navigation).
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            // `enumerated()` gives us both the index and the item,
                            // which we need to pass `isSelected` and the badge number.
                            ForEach(Array(clipboardManager.history.enumerated()), id: \.element.id) { index, item in
                                ClipboardRowView(
                                    item: item,
                                    index: index,
                                    isSelected: index == selectedIndex,
                                    onSelect: {
                                        // User clicked this row — paste it.
                                        onPaste(item)
                                    }
                                )
                                // Tag each row with its index so ScrollViewReader
                                // can scroll to it by calling proxy.scrollTo(index).
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    // Whenever selectedIndex changes, smoothly scroll the list
                    // so the highlighted row is visible.
                    .onChange(of: selectedIndex) { newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            // ── Footer ────────────────────────────────────────────────────
            // Only shown when there are items to interact with.
            if !clipboardManager.history.isEmpty {
                Divider()
                HStack(spacing: 12) {
                    Label("Navigate", systemImage: "arrow.up.arrow.down")
                    Label("Select",   systemImage: "return")
                    Label("Close",    systemImage: "escape")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 340)
        .frame(minHeight: 60, maxHeight: 380)
        // `.regularMaterial` gives us the frosted-glass look that automatically
        // adapts to the user's light/dark mode setting.
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            // A subtle 1pt border that helps the popup stand out against
            // any background without being visually heavy.
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        // The shadow is applied here in SwiftUI (the NSPanel has `hasShadow = false`)
        // so it respects the rounded corners.
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)

        // ── Keyboard event handler ────────────────────────────────────────
        // `PopupWindow.KeyablePanel` intercepts key events and posts them here
        // via NotificationCenter because SwiftUI can't directly receive keyboard
        // input from a non-activating window.
        .onReceive(NotificationCenter.default.publisher(for: .clipBoxKeyDown)) { notification in
            guard let keyCode = notification.userInfo?["keyCode"] as? UInt16 else { return }
            handleKey(keyCode: keyCode)
        }
    }

    // MARK: - Keyboard Handling

    /// Translates a raw macOS key code into a navigation or action.
    ///
    /// Key codes are hardware constants (the same on every Mac keyboard layout):
    /// - 125 = Arrow Down
    /// - 126 = Arrow Up
    /// - 36  = Return
    /// - 76  = Numpad Enter
    /// - 53  = Escape
    private func handleKey(keyCode: UInt16) {
        let count = clipboardManager.history.count
        guard count > 0 else { return }

        switch keyCode {
        case 125: // Arrow Down — move selection one row down
            selectedIndex = min(selectedIndex + 1, count - 1)

        case 126: // Arrow Up — move selection one row up
            selectedIndex = max(selectedIndex - 1, 0)

        case 36, 76: // Return / Numpad Enter — paste the selected item
            onPaste(clipboardManager.history[selectedIndex])

        case 53: // Escape — dismiss the popup without pasting
            onClose()

        default:
            break // Any other key is ignored
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    /// Posted by `PopupWindow.KeyablePanel.keyDown` whenever the user presses
    /// a key while the popup is open. The `userInfo` dictionary contains a
    /// `"keyCode"` key with a `UInt16` value.
    static let clipBoxKeyDown = Notification.Name("clipBoxKeyDown")
}
