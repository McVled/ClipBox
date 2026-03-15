//
//  ClipboardManager.swift
//  ClipBox
//

import Cocoa
import Combine

/// Responsible for two things:
///   1. **Monitoring** the system clipboard and building a history of copied items.
///   2. **Pasting** a selected history item back into whatever app the user was in.
///
/// It uses a polling approach — a `Timer` fires every 0.5 seconds and checks
/// whether `NSPasteboard.changeCount` has increased. If it has, a new string
/// was copied and we add it to `history`.
///
/// `ObservableObject` + `@Published` means SwiftUI views (like `PopupView`)
/// will automatically re-render whenever `history` changes.
class ClipboardManager: ObservableObject {

    // MARK: - Singleton

    /// The single shared instance used everywhere in the app.
    /// Using a singleton means all parts of the app read/write the same history.
    static let shared = ClipboardManager()

    // MARK: - Published State

    /// The list of recently copied texts, newest first.
    /// Capped at `maxItems` entries. SwiftUI observes this and redraws the
    /// popup list whenever it changes.
    @Published var history: [ClipboardItem] = []

    // MARK: - Private Properties

    /// Maximum number of items we keep in history.
    private let maxItems = 15

    /// The timer that polls the clipboard every 0.5 seconds.
    private var timer: Timer?

    /// The last known `changeCount` value from `NSPasteboard`.
    /// `changeCount` is an integer that macOS increments every time something
    /// new is written to the clipboard. By comparing it to the previous value,
    /// we know whether to process new content without reading the clipboard data
    /// on every tick (which would be wasteful).
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    // MARK: - Init

    /// Private initialiser enforces the singleton pattern — nobody can create
    /// a second instance by accident.
    private init() {}

    // MARK: - Monitoring

    /// Starts the background timer that watches the clipboard.
    /// Call this once from `AppDelegate.applicationDidFinishLaunching`.
    func startMonitoring() {
        // Snapshot the current changeCount so we don't treat existing clipboard
        // content as a new copy event on first launch.
        lastChangeCount = NSPasteboard.general.changeCount

        // Create a repeating timer on the main run loop.
        // `.common` mode ensures the timer fires even when the user is scrolling
        // or interacting with UI (otherwise the default mode can pause it).
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// Stops the timer. Called when the app is about to quit.
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Removes all items from history. Called from the menu bar "Clear History" action.
    func clearHistory() {
        DispatchQueue.main.async {
            self.history.removeAll()
            NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
        }
    }

    /// Called every 0.5 seconds by the timer.
    /// Checks whether new content was copied and, if so, adds it to history.
    private func checkPasteboard() {
        let pb = NSPasteboard.general

        // Early exit: changeCount hasn't changed, nothing new was copied.
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Try to read the clipboard as a plain string.
        // If the clipboard contains an image or file (not text), we skip it.
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        // Don't add the same text twice in a row (e.g. the user pressed ⌘C
        // multiple times on the same selection).
        if history.first?.text == text { return }

        // Update the published array on the main thread so SwiftUI can safely
        // re-render. Timer callbacks may come from a background thread.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // If this text already exists somewhere in history, remove it first
            // so it moves to the top rather than appearing twice.
            self.history.removeAll { $0.text == text }

            // Insert at index 0 = newest item appears at the top of the list.
            self.history.insert(ClipboardItem(text: text), at: 0)

            // Trim to the maximum allowed size.
            if self.history.count > self.maxItems {
                self.history = Array(self.history.prefix(self.maxItems))
            }

            // Notify the menu bar label to refresh its item count.
            NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
        }
    }

    // MARK: - Pasting

    /// Writes `item` to the clipboard and then simulates a ⌘V keypress so it
    /// gets pasted into whichever app is currently in the foreground.
    ///
    /// **Important:** The caller is responsible for re-activating the target app
    /// *before* calling this method. See `PopupWindow` for the timing sequence.
    func paste(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)

        // Update our own changeCount snapshot so that the next timer tick
        // doesn't see this write as a "new copy" and add it to history again.
        lastChangeCount = pb.changeCount

        // Simulate ⌘V using CGEvent — this is the low-level macOS way to
        // programmatically press a key. keyCode 9 = the 'V' key.
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)

        // Apply the Command modifier flag to both events (makes it ⌘V, not just V).
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand

        // Post the events to the HID (Human Interface Device) event tap, which
        // sends them to whatever app is currently active.
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted whenever `history` is modified (new item added or history cleared).
    /// Used by `AppDelegate` to keep the menu bar item count label up to date.
    static let clipBoxHistoryChanged = Notification.Name("clipBoxHistoryChanged")
}
