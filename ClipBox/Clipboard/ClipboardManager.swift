//
//  ClipboardManager.swift
//  ClipBox
//

import Cocoa
import Combine

/// Monitors the clipboard, stores history (text + images), and handles paste.
///
/// ## Image handling
/// Images are resized to max 1024px before being stored in memory and saved
/// to disk. This keeps memory usage low while preserving enough quality for
/// most use cases. Images are saved as PNG files in Application Support
/// (not UserDefaults, which has a size limit unsuitable for image data).
/// Text items continue to be saved in UserDefaults as JSON.
///
/// ## Persistence
/// - Text history  → UserDefaults (JSON array)
/// - Image history → ~/Library/Application Support/ClipBox/images/ (PNG files)
/// - A single index file (JSON) in Application Support ties everything together
///   and preserves order and timestamps across restarts.
class ClipboardManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ClipboardManager()

    // MARK: - Published State

    @Published var history: [ClipboardItem] = []

    // MARK: - Private Properties

    /// Maximum items in history (text + images combined).
    private let maxItems = 15

    /// Maximum pixel size (longest edge) for stored images.
    private let maxImageDimension: CGFloat = 1024

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    /// Folder where image PNG files are stored on disk.
    private lazy var imagesDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("ClipBox/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// UserDefaults key for the history index (order + metadata).
    private let indexKey = "com.clipbox.historyIndex"

    // MARK: - Init

    private init() {
        loadHistory()
    }

    // MARK: - Persistence: Save

    /// Saves the full history to disk.
    /// Text is stored in UserDefaults; images as PNG files in Application Support.
    private func saveHistory() {
        var indexEntries: [[String: String]] = []

        for item in history {
            switch item.content {
            case .text(let text):
                // Text entries are stored inline in the index.
                indexEntries.append([
                    "type": "text",
                    "value": text,
                    "date": ISO8601DateFormatter().string(from: item.date)
                ])

            case .image(let image):
                // Images are saved as PNG files named by their item ID.
                let filename = "\(item.id).png"
                let fileURL  = imagesDirectory.appendingPathComponent(filename)

                if let pngData = image.pngData() {
                    try? pngData.write(to: fileURL)
                }

                indexEntries.append([
                    "type": "image",
                    "filename": filename,
                    "date": ISO8601DateFormatter().string(from: item.date)
                ])
            }
        }

        if let data = try? JSONEncoder().encode(indexEntries) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }

        // Clean up any orphaned image files not referenced by current history.
        pruneOrphanedImageFiles()
    }

    /// Removes PNG files from disk that are no longer in the history index.
    private func pruneOrphanedImageFiles() {
        let activeFilenames = Set(history.compactMap { item -> String? in
            guard case .image = item.content else { return nil }
            return "\(item.id).png"
        })

        let allFiles = (try? FileManager.default.contentsOfDirectory(
            atPath: imagesDirectory.path
        )) ?? []

        for file in allFiles where !activeFilenames.contains(file) {
            try? FileManager.default.removeItem(
                at: imagesDirectory.appendingPathComponent(file)
            )
        }
    }

    // MARK: - Persistence: Load

    /// Restores history from disk on launch.
    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: indexKey),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return }

        let formatter = ISO8601DateFormatter()
        var loaded: [ClipboardItem] = []

        for entry in entries {
            guard let type = entry["type"],
                  let dateStr = entry["date"],
                  let date = formatter.date(from: dateStr)
            else { continue }

            switch type {
            case "text":
                if let text = entry["value"] {
                    loaded.append(ClipboardItem(content: .text(text), date: date))
                }

            case "image":
                if let filename = entry["filename"] {
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    if let image = NSImage(contentsOf: fileURL) {
                        loaded.append(ClipboardItem(content: .image(image), date: date))
                    }
                }

            default:
                break
            }
        }

        history = loaded
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

        // ── Try image first ───────────────────────────────────────────────
        // Check for image types before text, since some apps (e.g. Finder)
        // write both an image and a filename string; we want the image.
        if let image = pb.readImage() {
            let resized = image.resized(toMaxDimension: maxImageDimension)
            let key = ClipboardItem(image: resized).deduplicationKey

            if history.first?.deduplicationKey == key { return }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.history.removeAll { $0.deduplicationKey == key }
                self.history.insert(ClipboardItem(image: resized), at: 0)
                self.trimAndSave()
            }
            return
        }

        // ── Fall back to text ─────────────────────────────────────────────
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if history.first?.text == text { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.history.removeAll { $0.text == text }
            self.history.insert(ClipboardItem(text: text), at: 0)
            self.trimAndSave()
        }
    }

    /// Trims history to `maxItems` and persists to disk.
    private func trimAndSave() {
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
        saveHistory()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    // MARK: - Pasting

    /// Writes the item back to the clipboard and simulates ⌘V.
    func paste(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.content {
        case .text(let text):
            pb.setString(text, forType: .string)

        case .image(let image):
            // Write PNG data to clipboard — accepted by most macOS apps.
            if let data = image.pngData() {
                pb.setData(data, forType: .png)
            }
        }

        lastChangeCount = pb.changeCount

        let src      = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9
        let keyDown  = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        let keyUp    = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags   = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

// MARK: - NSPasteboard extension

private extension NSPasteboard {
    /// Returns the first image on the clipboard, or nil if none exists.
    func readImage() -> NSImage? {
        // Check for standard image types in priority order.
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic")
        ]
        for type in imageTypes {
            if let data = data(forType: type), let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }
}

// MARK: - NSImage extensions

extension NSImage {
    /// Resizes the image so its longest edge is at most `maxDimension` pixels.
    /// If the image is already smaller, it's returned unchanged.
    func resized(toMaxDimension maxDimension: CGFloat) -> NSImage {
        let originalSize = self.size
        let longestEdge  = max(originalSize.width, originalSize.height)

        // No resize needed if already within the limit.
        guard longestEdge > maxDimension else { return self }

        let scale      = maxDimension / longestEdge
        let newSize    = NSSize(
            width:  (originalSize.width  * scale).rounded(),
            height: (originalSize.height * scale).rounded()
        )

        // Draw the original image into a new bitmap at the reduced size.
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    /// Converts the image to PNG `Data`, suitable for saving to disk or clipboard.
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap   = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let clipBoxHistoryChanged = Notification.Name("clipBoxHistoryChanged")
}
