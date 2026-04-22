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

    /// When true, the settings slide-over is shown instead of the history list.
    @State private var showingSettings: Bool = false

    /// When true, the next keyDown captured by the panel is recorded as the
    /// new global shortcut instead of being used for navigation.
    @State private var isRecording: Bool = false

    /// The current global shortcut. Mirrors `HotkeyManager.shared.currentShortcut`
    /// so the UI updates immediately when recording finishes.
    @State private var shortcut: Shortcut = HotkeyManager.shared.currentShortcut

    /// Maximum number of history items. Persisted in UserDefaults and read by
    /// ClipboardManager; stored here so Settings can bind to it and Reset can
    /// restore the default without re-reading UserDefaults.
    @State private var historyLimit: Int = {
        let v = UserDefaults.standard.integer(forKey: ClipboardManager.historyLimitKey)
        return v > 0 ? v : ClipboardManager.historyLimitDefault
    }()

    /// Whether the menu-bar status icon is visible. Mirrors
    /// `StatusBarController.isEnabled` so the Settings toggle updates live.
    @State private var showInMenuBar: Bool = StatusBarController.isEnabled


    // MARK: - Callbacks

    /// Called when the popup should close (Escape key or external click).
    var onClose: () -> Void

    /// Called when the user selects an item to paste (click or Enter key).
    var onPaste: (ClipboardItem) -> Void

    // MARK: - Body

    var body: some View {
        ZStack {
            if showingSettings {
                SettingsView(
                    shortcut:      $shortcut,
                    followCursor:  $followCursor,
                    isRecording:   $isRecording,
                    historyLimit:  $historyLimit,
                    showInMenuBar: $showInMenuBar,
                    onBack: {
                        if isRecording {
                            isRecording = false
                            HotkeyManager.shared.isRecording = false
                        }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            showingSettings = false
                        }
                    },
                    onReset: {
                        shortcut = .default
                        HotkeyManager.shared.currentShortcut = .default
                        followCursor = false
                        PopupWindow.shared.followCursor = false
                        historyLimit = ClipboardManager.historyLimitDefault
                        UserDefaults.standard.set(
                            ClipboardManager.historyLimitDefault,
                            forKey: ClipboardManager.historyLimitKey
                        )
                        ClipboardManager.shared.applyHistoryLimit()
                        showInMenuBar = StatusBarController.showInMenuBarDefault
                        StatusBarController.shared.setVisible(
                            StatusBarController.showInMenuBarDefault
                        )
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainView
                    .transition(.move(edge: .leading).combined(with: .opacity))
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
            let flagsRaw = notification.userInfo?["flags"] as? UInt ?? 0
            let chars    = notification.userInfo?["chars"] as? String ?? ""
            handleKey(
                keyCode: keyCode,
                flags:   NSEvent.ModifierFlags(rawValue: flagsRaw),
                chars:   chars
            )
        }
    }

    // MARK: - Main (history/pinned) view

    private var mainView: some View {
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

                // ── Settings ─────────────────────────────────────────────
                Button(action: {
                    shortcut = HotkeyManager.shared.currentShortcut
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showingSettings = true
                    }
                }) {
                    Text("Settings")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

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
                .help("Settings")
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
                                // For history rows, look up an existing pinned
                                // copy so the row can show an accent-tinted pin
                                // icon and offer an Unpin action instead of a
                                // silently-failing re-pin.
                                let existingPin: ClipboardItem? = selectedTab == .history
                                    ? clipboardManager.existingPin(for: item)
                                    : nil

                                let unpinAction: (() -> Void)? = {
                                    if selectedTab == .pinned {
                                        return { clipboardManager.unpinItem(item) }
                                    }
                                    if let pinned = existingPin {
                                        return { clipboardManager.unpinItem(pinned) }
                                    }
                                    return nil
                                }()

                                ClipboardRowView(
                                    item:      item,
                                    index:     index,
                                    isSelected: index == selectedIndex,
                                    isPinned:  selectedTab == .pinned,
                                    onSelect:  { onPaste(item) },
                                    // History: show Public/Private popover on pin tap,
                                    //          or "Already pinned — Unpin" if matched.
                                    // Pinned:  no onPin, direct unpin button instead.
                                    onPin: selectedTab == .history ? { description, isHidden in
                                        clipboardManager.pinItem(
                                            item,
                                            description: description,
                                            isHidden: isHidden
                                        )
                                    } : nil,
                                    onUnpin: unpinAction,
                                    existingPin: existingPin,
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

        // Capture the tab NOW so a mid-animation tab switch can't redirect
        // the clear to the wrong list (e.g. starting on History, switching to
        // Pinned before the ~600 ms animation finishes → pinned would be wiped).
        let tabToClean = selectedTab

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            if tabToClean == .history {
                ClipboardManager.shared.clearHistory()
            } else {
                ClipboardManager.shared.clearPinnedItems()
            }
            self.isClearing = false
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
    ///
    /// Important: Escape (53) is handled BEFORE the `count > 0` guard so it
    /// always works, even when the history list is empty.
    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String) {
        // ── Recording mode ────────────────────────────────────────────────
        // Capture whatever combo the user presses as the new global shortcut.
        if isRecording {
            handleRecordingKey(keyCode: keyCode, flags: flags, chars: chars)
            return
        }

        // ── Escape ────────────────────────────────────────────────────────
        // In settings: go back. In list: close popup. Always handled first so
        // it works even when the list is empty.
        if keyCode == 53 {
            if showingSettings {
                withAnimation(.easeInOut(duration: 0.22)) {
                    showingSettings = false
                }
            } else {
                onClose()
            }
            return
        }

        // While Settings is visible, ignore navigation keys — they'd move an
        // invisible selection in the hidden list.
        if showingSettings { return }

        // ── Tab switching (← →) ───────────────────────────────────────────
        // Handled before the count guard so it works even on an empty tab.
        if keyCode == 123 { // Arrow Left → History
            selectedTab = .history
            return
        }
        if keyCode == 124 { // Arrow Right → Pinned
            selectedTab = .pinned
            return
        }

        let items = currentItems
        let count = items.count
        guard count > 0 else { return }

        // Clamp selectedIndex in case items were removed (delete/unpin) while
        // the selection was pointing to the last row — otherwise pressing Enter
        // right after a delete would index out of bounds and crash.
        if selectedIndex >= count { selectedIndex = count - 1 }

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

    // MARK: - Recording

    /// Consumes the next keypress during shortcut recording. Escape cancels,
    /// modifier-only presses are ignored, and combinations without any modifier
    /// are rejected (pressing plain "V" would otherwise hijack normal typing).
    private func handleRecordingKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String) {
        // Escape cancels recording without saving.
        if keyCode == 53 {
            isRecording = false
            HotkeyManager.shared.isRecording = false
            return
        }

        // Build label. Prefer a known-key mapping first (arrows, F-keys, etc.)
        // because charactersIgnoringModifiers returns private-use unicode for
        // those keys. Fall back to the character only if it's printable ASCII.
        let label: String
        if let known = specialKeyName(for: keyCode) {
            label = known
        } else {
            let trimmed = chars.trimmingCharacters(in: .whitespacesAndNewlines)
            if let scalar = trimmed.unicodeScalars.first,
               scalar.value >= 0x20 && scalar.value < 0x7F {
                label = trimmed.uppercased()
            } else {
                label = "Key \(keyCode)"
            }
        }

        let new = Shortcut(
            command: flags.contains(.command),
            shift:   flags.contains(.shift),
            option:  flags.contains(.option),
            control: flags.contains(.control),
            keyCode: keyCode,
            keyLabel: label
        )

        // Require at least one modifier — otherwise the user would block their
        // own typing (e.g. pressing a plain letter would trigger the popup).
        guard new.hasModifier else {
            // Stay in recording mode so they can try again.
            return
        }

        shortcut = new
        HotkeyManager.shared.currentShortcut = new
        isRecording = false
        HotkeyManager.shared.isRecording = false
    }

    /// Human-readable labels for common non-character keys (arrows, F-keys, etc.).
    private func specialKeyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36:  return "↩"
        case 48:  return "⇥"
        case 49:  return "Space"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return nil
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
