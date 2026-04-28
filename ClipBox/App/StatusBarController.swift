//
//  StatusBarController.swift
//  ClipBox
//

import AppKit
import Combine

/// Manages the optional menu-bar (status bar) icon. When visible, clicking
/// the icon toggles the popup anchored directly below it.
///
/// Visibility is driven by the `showInMenuBar` user setting. Call
/// `applyCurrentSetting()` once on launch; use `setVisible(_:)` when the
/// Settings toggle flips.
final class StatusBarController {

    // MARK: - Singleton

    static let shared = StatusBarController()

    // MARK: - UserDefaults

    static let showInMenuBarKey     = "com.clipbox.showInMenuBar"
    static let showInMenuBarDefault = false

    /// Current persisted preference. Reads `true` when unset so first-time
    /// users discover the icon.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: showInMenuBarKey) as? Bool ?? showInMenuBarDefault
    }

    // MARK: - Private State

    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    /// Applies whatever visibility is currently stored in UserDefaults.
    /// Call once from `applicationDidFinishLaunching`.
    func applyCurrentSetting() {
        setVisible(Self.isEnabled)
    }

    /// Shows or hides the status item and persists the preference.
    func setVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: Self.showInMenuBarKey)

        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(statusItemClicked(_:))
            }
            statusItem = item

            setupIconUpdates()
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItem = nil
            cancellables.removeAll()
        }
    }

    private func setupIconUpdates() {
        updateStatusIcon()

        ClipboardManager.shared.$history
            .merge(with: ClipboardManager.shared.$pinnedItems)
            .debounce(for: 0.1, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusIcon()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let hasItems = !ClipboardManager.shared.history.isEmpty ||
                       !ClipboardManager.shared.pinnedItems.isEmpty
        let iconName = hasItems ? "doc.on.clipboard.fill" : "doc.on.clipboard"

        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "ClipBox") {
            image.isTemplate = true
            button.image = image
        }
    }

    // MARK: - Click Handler

    /// Toggles the popup anchored just below the status item.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // The status item button lives in its own borderless window at the top
        // of the screen. Its window frame (in screen coordinates) is the anchor
        // rect we position the popup against.
        let anchor = sender.window?.frame
        PopupWindow.shared.toggle(from: anchor)
    }
}
