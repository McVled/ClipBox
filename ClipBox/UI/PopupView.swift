//
//  PopupView.swift
//  ClipBox
//

import SwiftUI

/// The main SwiftUI view rendered inside the floating popup panel.
///
/// Layout (top to bottom):
///   1. Header — title on the left, Clear History + Quit buttons on the right
///   2. Divider
///   3. Scrollable list of `ClipboardRowView` items (or an empty-state message)
///   4. Divider  (only when list has items)
///   5. Footer — keyboard hint labels (only when list has items)
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

    /// Which tab is currently active.
    enum Tab: String, CaseIterable {
        case history = "History"
        case pinned  = "Pinned"
    }

    @State private var selectedTab: Tab = .history

    /// The index of the currently highlighted row. Starts at 0 (most recent item).
    @State private var selectedIndex: Int = 0

    /// Tracks whether a clear animation is in progress.
    @State private var isClearing: Bool = false

    /// Whether the popup follows the cursor or stays at its last position.
    @State private var followCursor: Bool = PopupWindow.shared.followCursor


    // MARK: - Callbacks

    /// Called when the popup should close (Escape key or external click).
    var onClose: () -> Void

    /// Called when the user selects an item to paste (click or Enter key).
    var onPaste: (ClipboardItem) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 8) {

                // Left side — app icon + title
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("ClipBox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                // ── Follow Cursor toggle ─────────────────────────────────
                Button(action: {
                    followCursor.toggle()
                    PopupWindow.shared.followCursor = followCursor
                }) {
                    Label("Follow", systemImage: "cursorarrow.motionlines")
                        .font(.system(size: 11))
                        .foregroundColor(followCursor ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(followCursor ? "Follow Cursor: On" : "Follow Cursor: Off")

                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 2)

                // ── Clear All button ─────────────────────────────────────
                Button(action: {
                    triggerClearWithAnimation()
                }) {
                    Text("Clear All")
                        .font(.system(size: 11))
                        .foregroundColor(currentItems.isEmpty ? .secondary.opacity(0.35) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(currentItems.isEmpty || isClearing)

                Divider()
                    .frame(height: 12)
                    .padding(.horizontal, 2)

                // ── Quit button ───────────────────────────────────────────
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Quit App")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // ── Tab Picker ───────────────────────────────────────────────
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .onChange(of: selectedTab) { _ in
                selectedIndex = 0
            }

            Divider()

            // ── List or empty state ───────────────────────────────────────
            if currentItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: selectedTab == .history ? "doc.on.clipboard" : "pin")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(selectedTab == .history ? "History is empty" : "No pinned items")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(selectedTab == .history ? "Copy something to get started" : "Pin items from History to keep them here")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30)

            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(currentItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardRowView(
                                    item: item,
                                    index: index,
                                    isSelected: index == selectedIndex,
                                    isPinned: selectedTab == .pinned,
                                    onSelect: {
                                        onPaste(item)
                                    },
                                    onTogglePin: {
                                        if selectedTab == .history {
                                            clipboardManager.pinItem(item)
                                        } else {
                                            clipboardManager.unpinItem(item)
                                        }
                                    },
                                    onDelete: selectedTab == .history ? {
                                        clipboardManager.deleteHistoryItem(item)
                                    } : nil
                                )
                                .id(item.id)
                                .opacity(isClearing ? 0 : 1)
                                .animation(
                                    .easeIn(duration: 0.25).delay(Double(index) * 0.04),
                                    value: isClearing
                                )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { newIndex in
                        guard newIndex < currentItems.count else { return }
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(currentItems[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            // ── Footer — keyboard hints ───────────────────────────────────
            if !currentItems.isEmpty {
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
        // `.regularMaterial` gives the frosted-glass look that automatically
        // adapts to the user's light/dark mode setting.
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        // Shadow is applied here in SwiftUI (NSPanel has hasShadow = false)
        // so it correctly follows the rounded corners.
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

    // MARK: - Computed Properties

    /// Returns items for the currently active tab.
    private var currentItems: [ClipboardItem] {
        selectedTab == .history ? clipboardManager.history : clipboardManager.pinnedItems
    }

    // MARK: - Clear Animation

    /// Triggers a staggered fade-out on all rows, then clears history and
    /// closes the popup after the animation completes.
    ///
    /// Timeline:
    ///   T+0ms     — `isClearing = true` → rows start fading top-to-bottom
    ///   T+~550ms  — last row has faded (0.25s duration + 14 rows × 40ms stagger)
    ///   T+600ms   — history wiped + popup closes
    private func triggerClearWithAnimation() {
        guard !isClearing else { return }
        isClearing = true

        // Wait for the stagger animation to finish before wiping data and closing.
        // The total animation time = duration (0.25s) + last row delay (items × 0.04s).
        // We add a small extra buffer (0.1s) so the last row fully fades before close.
        let itemCount = currentItems.count
        let totalDelay = 0.25 + Double(itemCount) * 0.04 + 0.1

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            
            if self.selectedTab == .history {
                ClipboardManager.shared.clearHistory()
            } else {
                ClipboardManager.shared.clearPinnedItems()
            }
        }
        self.isClearing = false
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
    ///
    /// Important: Escape (53) is handled BEFORE the `count > 0` guard so it
    /// always works, even when the history list is empty.
    private func handleKey(keyCode: UInt16) {
        // Escape is always handled — regardless of whether history is empty.
        // Previously this was inside the `guard count > 0` block, which meant
        // Escape did nothing when the list was empty. Fixed by checking it first.
        if keyCode == 53 {
            onClose()
            return
        }

        let items = currentItems
        let count = items.count
        guard count > 0 else { return }

        switch keyCode {
        case 125: // Arrow Down
            selectedIndex = min(selectedIndex + 1, count - 1)

        case 126: // Arrow Up
            selectedIndex = max(selectedIndex - 1, 0)

        case 36, 76: // Return / Numpad Enter
            onPaste(items[selectedIndex])

        default:
            break
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
