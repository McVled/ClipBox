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
    private static let dateFormatter = ISO8601DateFormatter()

    var maxItems: Int {
        let v = UserDefaults.standard.integer(forKey: Self.historyLimitKey)
        return v > 0 ? v : Self.historyLimitDefault
    }

    func applyHistoryLimit() {
        let limit = maxItems
        guard history.count > limit else { return }
        history = Array(history.prefix(limit))
        saveHistory()
    }

    private let maxImageDimension: CGFloat = 1024

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount

    /// Set during `init`, never mutated.  Eagerly initialised (not lazy) because
    /// `imagesDirectory` is read from the background save queue and `lazy var`
    /// is not thread-safe on first access.
    private let imagesDirectory: URL

    private let indexKey       = "com.clipbox.historyIndex"
    private let pinnedIndexKey = "com.clipbox.pinnedIndex"

    /// Serial queue that handles all filesystem and UserDefaults persistence
    /// so it never blocks the main thread.  Saves are dispatched async after
    /// snapshotting the relevant state on main.  Ordering is preserved because
    /// the queue is serial.
    private let saveQueue = DispatchQueue(label: "com.clipbox.persistence", qos: .utility)

    // MARK: - Init

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("ClipBox/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.imagesDirectory = dir

        loadTags()
        loadHistory()
        loadPinnedItems()
    }

    /// Blocks until every pending background save has completed.  Called from
    /// `applicationWillTerminate` so we never quit with in-flight writes.
    func flushPendingSaves() {
        saveQueue.sync {}
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

    /// Deletes a tag and moves its items to untagged.
    func deleteTag(_ tag: ClipBoxTag) {
        tags.removeAll { $0.id == tag.id }
        for i in pinnedItems.indices where pinnedItems[i].tagID == tag.id {
            pinnedItems[i] = pinnedItems[i].withTagID(nil)
        }
        saveTags()
        savePinnedItems()
    }

    /// Deletes a tag and removes all pinned items that belonged to it.
    func deleteTagAndItems(_ tag: ClipBoxTag) {
        tags.removeAll { $0.id == tag.id }
        pinnedItems.removeAll { $0.tagID == tag.id }
        saveTags()
        savePinnedItems()
        pruneOrphanedImageFiles()
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
        let snapshot = tags
        saveQueue.async {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.tagsKey)
            }
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
        let snapshot = history
        let dir      = imagesDirectory
        let key      = indexKey
        let active   = computeActiveImageFilenames()
        saveQueue.async {
            var indexEntries: [[String: String]] = []

            for item in snapshot {
                switch item.content {
                case .text(let text):
                    indexEntries.append([
                        "type":  "text",
                        "value": text,
                        "date":  Self.dateFormatter.string(from: item.date)
                    ])

                case .image(let image):
                    let filename = "\(item.id).png"
                    let fileURL  = dir.appendingPathComponent(filename)
                    // Image content is immutable per UUID, so once the file
                    // exists we don't need to rewrite it on subsequent saves.
                    if !FileManager.default.fileExists(atPath: fileURL.path),
                       let pngData = image.pngData() {
                        try? pngData.write(to: fileURL)
                    }
                    indexEntries.append([
                        "type":     "image",
                        "filename": filename,
                        "date":     Self.dateFormatter.string(from: item.date)
                    ])
                }
            }

            if let data = try? JSONEncoder().encode(indexEntries) {
                UserDefaults.standard.set(data, forKey: key)
            }

            Self.prune(directory: dir, keeping: active)
        }
    }

    /// Snapshot of currently-active image filenames (must be called on the main
    /// thread before dispatching to `saveQueue`).
    private func computeActiveImageFilenames() -> Set<String> {
        var names: Set<String> = []
        for item in history where item.image != nil {
            names.insert("\(item.id).png")
        }
        for item in pinnedItems where item.image != nil {
            names.insert("pinned_\(item.id).png")
        }
        return names
    }

    private func pruneOrphanedImageFiles() {
        let dir    = imagesDirectory
        let active = computeActiveImageFilenames()
        saveQueue.async {
            Self.prune(directory: dir, keeping: active)
        }
    }

    /// Background-safe directory cleanup — only touches its parameters.
    private static func prune(directory: URL, keeping active: Set<String>) {
        let allFiles = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in allFiles where !active.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
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
        history.removeAll { $0.deduplicationKey == item.deduplicationKey }
        saveHistory()
    }

    func unpinItem(_ item: ClipboardItem) {
        pinnedItems.removeAll { $0.id == item.id }
        savePinnedItems()
        pruneOrphanedImageFiles()
    }

    private func savePinnedItems() {
        let snapshot = pinnedItems
        let dir      = imagesDirectory
        let key      = pinnedIndexKey
        saveQueue.async {
            var indexEntries: [[String: String]] = []

            for item in snapshot {
                var entry: [String: String] = [
                    "date": Self.dateFormatter.string(from: item.date)
                ]
                switch item.content {
                case .text(let text):
                    entry["type"]  = "text"
                    entry["value"] = text
                case .image(let image):
                    let filename = "pinned_\(item.id).png"
                    let fileURL  = dir.appendingPathComponent(filename)
                    // Skip rewriting an existing PNG — image bytes never change
                    // for a given UUID, so the on-disk copy is already correct.
                    if !FileManager.default.fileExists(atPath: fileURL.path),
                       let pngData = image.pngData() {
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
                UserDefaults.standard.set(data, forKey: key)
            }
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
        pruneEmptyTags()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        timer?.invalidate()
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
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func clearAllPinned() {
        tags.removeAll()
        pinnedItems.removeAll()
        saveTags()
        savePinnedItems()
        pruneOrphanedImageFiles()
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
    }

    // MARK: - Pasting

    func paste(item: ClipboardItem) {
        let pb = NSPasteboard.general

        switch item.content {
        case .text(let text):
            pb.clearContents()
            pb.setString(text, forType: .string)

        case .image(let image):
            guard let data = image.pngData() else { return }
            pb.clearContents()
            pb.setData(data, forType: .png)
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

