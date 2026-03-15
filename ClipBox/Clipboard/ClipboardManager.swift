//
//  ClipboardManager.swift
//  ClipBox
//

import Cocoa
import Combine

/// Responsible for three things:
///   1. **Monitoring** the system clipboard and building a history of copied items.
///   2. **Pasting** a selected history item back into whatever app the user was in.
///   3. **Persisting** history to disk so it survives app restarts.
///
/// Persistence uses `UserDefaults` — the simplest built-in macOS key-value store.
/// History is serialized as JSON and saved every time the array changes.
/// On next launch it is loaded back instantly in `init()`.
class ClipboardManager: ObservableObject {

    // MARK: - Singleton
    static let shared = ClipboardManager()

    // MARK: - Published State

    /// The list of recently copied texts, newest first.
    /// Capped at `maxItems` entries. Persisted to UserDefaults automatically.
    @Published var history: [ClipboardItem] = []

    // MARK: - Private Properties

    private let maxItems = 15
    private let storageKey = "com.clipbox.history"
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    // MARK: - Init

    private init() {
        loadHistory()
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([PersistedItem].self, from: data)
            history = decoded.map { ClipboardItem(text: $0.text, date: $0.date) }
        } catch {
            print("ClipBox: Failed to load history — \(error). Starting fresh.")
            history = []
        }
    }

    private func saveHistory() {
        do {
            let items = history.map { PersistedItem(text: $0.text, date: $0.date) }
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("ClipBox: Failed to save history — \(error)")
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func clearHistory() {
        DispatchQueue.main.async {
            self.history.removeAll()
            self.saveHistory()
            NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
        }
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if history.first?.text == text { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.history.removeAll { $0.text == text }
            self.history.insert(ClipboardItem(text: text), at: 0)
            if self.history.count > self.maxItems {
                self.history = Array(self.history.prefix(self.maxItems))
            }
            self.saveHistory()
            NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
        }
    }

    // MARK: - Pasting

    func paste(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChangeCount = pb.changeCount

        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - PersistedItem

/// Codable helper used only for JSON encoding/decoding.
/// Separate from ClipboardItem because UUID auto-generation shouldn't be persisted.
private struct PersistedItem: Codable {
    let text: String
    let date: Date
}

// MARK: - ClipboardItem restore init

extension ClipboardItem {
    /// Used when restoring items from disk — preserves the original date.
    init(text: String, date: Date) {
        self.text = text
        self.date = date
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let clipBoxHistoryChanged = Notification.Name("clipBoxHistoryChanged")
}
