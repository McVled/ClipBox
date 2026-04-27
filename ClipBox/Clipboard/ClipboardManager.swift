//
//  ClipboardManager.swift
//  ClipBox
//

import Cocoa
import Combine

class ClipboardManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ClipboardManager()

    // MARK: - Published State

    @Published var history:      [ClipboardItem] = []
    @Published var pinnedItems:  [ClipboardItem] = []
    @Published var tags:         [ClipBoxTag]    = []

    // MARK: - Private Properties

    static let historyLimitKey     = "com.clipbox.historyLimit"
    static let historyLimitDefault = 15
    private static let tagsKey     = "com.clipbox.tags"

    var maxItems: Int {
        let v = UserDefaults.standard.integer(forKey: Self.historyLimitKey)
        return v > 0 ? v : Self.historyLimitDefault
    }

    func applyHistoryLimit() {
        let limit = maxItems
        guard history.count > limit else { return }
        history = Array(history.prefix(limit))
        saveHistory()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    private let maxImageDimension: CGFloat = 1024

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    private lazy var imagesDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("ClipBox/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let indexKey       = "com.clipbox.historyIndex"
    private let pinnedIndexKey = "com.clipbox.pinnedIndex"

    // MARK: - Init

    private init() {
        loadTags()
        loadHistory()
        loadPinnedItems()
    }

    // MARK: - Tags

    /// Creates a new tag and persists it. Returns the created tag.
    @discardableResult
    func createTag(name: String, colorHex: String) -> ClipBoxTag {
        let tag = ClipBoxTag(name: name, colorHex: colorHex)
        tags.append(tag)
        saveTags()
        return tag
    }

    /// Assigns (or removes) a tag on a pinned item, identified by `itemID`.
    func assignTag(_ tagID: UUID?, to itemID: UUID) {
        guard let index = pinnedItems.firstIndex(where: { $0.id == itemID }) else { return }
        pinnedItems[index] = pinnedItems[index].withTagID(tagID)
        savePinnedItems()
    }

    /// Updates a tag's name and colour in-place.
    func editTag(_ tag: ClipBoxTag, newName: String, newColorHex: String) {
        guard let i = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[i].name     = newName
        tags[i].colorHex = newColorHex
        saveTags()
    }

    /// Deletes a tag and unassigns it from every pinned item that had it.
    func deleteTag(_ tag: ClipBoxTag) {
        tags.removeAll { $0.id == tag.id }
        for i in pinnedItems.indices where pinnedItems[i].tagID == tag.id {
            pinnedItems[i] = pinnedItems[i].withTagID(nil)
        }
        saveTags()
        savePinnedItems()
    }

    /// Removes every tag that has no pinned items. Called after any operation
    /// that can reduce a tag's item count to zero.
    private func pruneEmptyTags() {
        let usedIDs = Set(pinnedItems.compactMap { $0.tagID })
        let before  = tags.count
        tags.removeAll { !usedIDs.contains($0.id) }
        if tags.count != before { saveTags() }
    }

    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: Self.tagsKey)
        }
    }

    private func loadTags() {
        guard let data = UserDefaults.standard.data(forKey: Self.tagsKey),
              let decoded = try? JSONDecoder().decode([ClipBoxTag].self, from: data)
        else { return }
        tags = decoded
    }

    // MARK: - Persistence: Save History

    private func saveHistory() {
        var indexEntries: [[String: String]] = []

        for item in history {
            switch item.content {
            case .text(let text):
                indexEntries.append([
                    "type":  "text",
                    "value": text,
                    "date":  ISO8601DateFormatter().string(from: item.date)
                ])

            case .image(let image):
                let filename = "\(item.id).png"
                let fileURL  = imagesDirectory.appendingPathComponent(filename)
                if let pngData = image.pngData() {
                    try? pngData.write(to: fileURL)
                }
                indexEntries.append([
                    "type":     "image",
                    "filename": filename,
                    "date":     ISO8601DateFormatter().string(from: item.date)
                ])
            }
        }

        if let data = try? JSONEncoder().encode(indexEntries) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }

        pruneOrphanedImageFiles()
    }

    private func pruneOrphanedImageFiles() {
        let historyFilenames = history.compactMap { item -> String? in
            guard case .image = item.content else { return nil }
            return "\(item.id).png"
        }
        let pinnedFilenames = pinnedItems.compactMap { item -> String? in
            guard case .image = item.content else { return nil }
            return "pinned_\(item.id).png"
        }
        let activeFilenames = Set(historyFilenames + pinnedFilenames)

        let allFiles = (try? FileManager.default.contentsOfDirectory(
            atPath: imagesDirectory.path
        )) ?? []

        for file in allFiles where !activeFilenames.contains(file) {
            try? FileManager.default.removeItem(
                at: imagesDirectory.appendingPathComponent(file)
            )
        }
    }

    // MARK: - Persistence: Load History

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: indexKey),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return }

        let formatter = ISO8601DateFormatter()
        var loaded: [ClipboardItem] = []

        for entry in entries {
            guard let type    = entry["type"],
                  let dateStr = entry["date"],
                  let date    = formatter.date(from: dateStr)
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

        history = Array(loaded.prefix(maxItems))
        if loaded.count > maxItems { saveHistory() }
    }

    // MARK: - Pinned Items

    func existingPin(for item: ClipboardItem) -> ClipboardItem? {
        pinnedItems.first(where: { $0.deduplicationKey == item.deduplicationKey })
    }

    func pinItem(_ item: ClipboardItem, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        guard !pinnedItems.contains(where: { $0.deduplicationKey == item.deduplicationKey }) else { return }
        let pinned = ClipboardItem(
            content:     item.content,
            date:        item.date,
            description: description,
            isHidden:    isHidden,
            tagID:       tagID
        )
        pinnedItems.insert(pinned, at: 0)
        savePinnedItems()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    func unpinItem(_ item: ClipboardItem) {
        pinnedItems.removeAll { $0.id == item.id }
        savePinnedItems()
        pruneOrphanedImageFiles()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    /// Moves a pinned item from one index to another within `pinnedItems`.
    func movePinnedItem(fromIndex source: Int, toIndex destination: Int) {
        guard source != destination,
              pinnedItems.indices.contains(source) else { return }
        let item     = pinnedItems.remove(at: source)
        let adjusted = destination > source ? destination - 1 : destination
        pinnedItems.insert(item, at: min(adjusted, pinnedItems.count))
        savePinnedItems()
    }

    private func savePinnedItems() {
        var indexEntries: [[String: String]] = []

        for item in pinnedItems {
            var entry: [String: String] = [
                "date": ISO8601DateFormatter().string(from: item.date)
            ]
            switch item.content {
            case .text(let text):
                entry["type"]  = "text"
                entry["value"] = text
            case .image(let image):
                let filename = "pinned_\(item.id).png"
                let fileURL  = imagesDirectory.appendingPathComponent(filename)
                if let pngData = image.pngData() {
                    try? pngData.write(to: fileURL)
                }
                entry["type"]     = "image"
                entry["filename"] = filename
            }
            if let desc = item.description, !desc.isEmpty {
                entry["description"] = desc
            }
            if item.isHidden {
                entry["hidden"] = "1"
            }
            if let tagID = item.tagID {
                entry["tagID"] = tagID.uuidString
            }
            indexEntries.append(entry)
        }

        if let data = try? JSONEncoder().encode(indexEntries) {
            UserDefaults.standard.set(data, forKey: pinnedIndexKey)
        }
    }

    private func loadPinnedItems() {
        guard let data = UserDefaults.standard.data(forKey: pinnedIndexKey),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return }

        let formatter = ISO8601DateFormatter()
        var loaded: [ClipboardItem] = []

        for entry in entries {
            guard let type    = entry["type"],
                  let dateStr = entry["date"],
                  let date    = formatter.date(from: dateStr)
            else { continue }

            let description = entry["description"]
            let isHidden    = entry["hidden"] == "1"
            let tagID       = entry["tagID"].flatMap { UUID(uuidString: $0) }

            switch type {
            case "text":
                if let text = entry["value"] {
                    loaded.append(ClipboardItem(
                        content:     .text(text),
                        date:        date,
                        description: description,
                        isHidden:    isHidden,
                        tagID:       tagID
                    ))
                }
            case "image":
                if let filename = entry["filename"] {
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    if let image = NSImage(contentsOf: fileURL) {
                        loaded.append(ClipboardItem(
                            content:     .image(image),
                            date:        date,
                            description: description,
                            isHidden:    isHidden,
                            tagID:       tagID
                        ))
                    }
                }
            default:
                break
            }
        }

        pinnedItems = loaded
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

    func deleteHistoryItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    func deletePinnedItem(_ item: ClipboardItem) {
        pinnedItems.removeAll { $0.id == item.id }
        savePinnedItems()
        pruneOrphanedImageFiles()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    func clearPinnedItems() {
        pinnedItems.removeAll()
        tags.removeAll()
        saveTags()
        savePinnedItems()
        pruneOrphanedImageFiles()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    /// Removes all pinned items that belong to the given tag (keeps the tag itself).
    func clearPinnedItems(withTagID tagID: UUID) {
        pinnedItems.removeAll { $0.tagID == tagID }
        savePinnedItems()
        pruneOrphanedImageFiles()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

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

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if history.first?.text == text { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.history.removeAll { $0.text == text }
            self.history.insert(ClipboardItem(text: text), at: 0)
            self.trimAndSave()
        }
    }

    private func trimAndSave() {
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
        saveHistory()
        NotificationCenter.default.post(name: .clipBoxHistoryChanged, object: nil)
    }

    // MARK: - Pasting

    func paste(item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.content {
        case .text(let text):
            pb.setString(text, forType: .string)

        case .image(let image):
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
    func readImage() -> NSImage? {
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
    func resized(toMaxDimension maxDimension: CGFloat) -> NSImage {
        let originalSize = self.size
        let longestEdge  = max(originalSize.width, originalSize.height)
        guard longestEdge > maxDimension else { return self }

        let scale   = maxDimension / longestEdge
        let newSize = NSSize(
            width:  (originalSize.width  * scale).rounded(),
            height: (originalSize.height * scale).rounded()
        )

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in:        NSRect(origin: .zero, size: newSize),
            from:      NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction:  1.0
        )
        newImage.unlockFocus()
        return newImage
    }

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
