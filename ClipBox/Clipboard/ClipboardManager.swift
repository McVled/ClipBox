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
    @Published var deletedItems: [ClipboardItem] = []

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
    private let deletedIndexKey = "com.clipbox.deletedIndex"

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
        loadDeletedItems()
        pruneExpiredDeletedItems()
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

    /// Toggles a pinned item's privacy. Pass `isHidden: true` with a description
    /// to make it private, or `isHidden: false` (description ignored) to make it public.
    func setPrivacy(item: ClipboardItem, isHidden: Bool, description: String?) {
        guard let index = pinnedItems.firstIndex(where: { $0.id == item.id }) else { return }
        pinnedItems[index] = pinnedItems[index].withPrivacy(isHidden: isHidden, description: isHidden ? description : nil)
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

    /// Deletes a tag and soft-deletes all pinned items that belonged to it.
    func deleteTagAndItems(_ tag: ClipBoxTag) {
        let toDelete = pinnedItems.filter { $0.tagID == tag.id }
        let softDeleted = toDelete.map {
            $0.withDeletion(tagName: tag.name, tagColor: tag.colorHex, fromPinned: true)
        }
        tags.removeAll { $0.id == tag.id }
        pinnedItems.removeAll { $0.tagID == tag.id }
        deletedItems.insert(contentsOf: softDeleted, at: 0)
        saveTags()
        savePinnedItems()
        saveDeletedItems()
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
                        "id":    item.id.uuidString,
                        "type":  "text",
                        "value": text,
                        "date":  Self.dateFormatter.string(from: item.date)
                    ])

                case .image(let image):
                    let filename = "\(item.id).png"
                    let fileURL  = dir.appendingPathComponent(filename)
                    if !FileManager.default.fileExists(atPath: fileURL.path),
                       let pngData = image.pngData() {
                        try? pngData.write(to: fileURL)
                    }
                    indexEntries.append([
                        "id":       item.id.uuidString,
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
        for item in deletedItems where item.image != nil {
            // Deleted history images keep the plain filename; deleted pinned images
            // keep the "pinned_" prefix — whichever was used when the item was alive.
            let filename = item.deletedFromPinned ? "pinned_\(item.id).png" : "\(item.id).png"
            names.insert(filename)
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

        var loaded: [ClipboardItem] = []

        for entry in entries {
            guard let type    = entry["type"],
                  let dateStr = entry["date"],
                  let date    = Self.dateFormatter.date(from: dateStr)
            else { continue }

            let savedID = entry["id"].flatMap { UUID(uuidString: $0) }

            switch type {
            case "text":
                if let text = entry["value"] {
                    if let id = savedID {
                        loaded.append(ClipboardItem(loadedWithID: id, content: .text(text), date: date))
                    } else {
                        loaded.append(ClipboardItem(content: .text(text), date: date))
                    }
                }
            case "image":
                if let filename = entry["filename"] {
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    if let image = NSImage(contentsOf: fileURL) {
                        if let id = savedID {
                            loaded.append(ClipboardItem(loadedWithID: id, content: .image(image), date: date))
                        } else {
                            loaded.append(ClipboardItem(content: .image(image), date: date))
                        }
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
                    "id":   item.id.uuidString,
                    "date": Self.dateFormatter.string(from: item.date)
                ]
                switch item.content {
                case .text(let text):
                    entry["type"]  = "text"
                    entry["value"] = text
                case .image(let image):
                    let filename = "pinned_\(item.id).png"
                    let fileURL  = dir.appendingPathComponent(filename)
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

        var loaded: [ClipboardItem] = []

        for entry in entries {
            guard let type    = entry["type"],
                  let dateStr = entry["date"],
                  let date    = Self.dateFormatter.date(from: dateStr)
            else { continue }

            let savedID     = entry["id"].flatMap { UUID(uuidString: $0) }
            let description = entry["description"]
            let isHidden    = entry["hidden"] == "1"
            let tagID       = entry["tagID"].flatMap { UUID(uuidString: $0) }

            switch type {
            case "text":
                if let text = entry["value"] {
                    if let id = savedID {
                        loaded.append(ClipboardItem(loadedWithID: id, content: .text(text), date: date,
                                                    description: description, isHidden: isHidden, tagID: tagID))
                    } else {
                        loaded.append(ClipboardItem(content: .text(text), date: date,
                                                    description: description, isHidden: isHidden, tagID: tagID))
                    }
                }
            case "image":
                if let filename = entry["filename"] {
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    if let image = NSImage(contentsOf: fileURL) {
                        if let id = savedID {
                            loaded.append(ClipboardItem(loadedWithID: id, content: .image(image), date: date,
                                                        description: description, isHidden: isHidden, tagID: tagID))
                        } else {
                            loaded.append(ClipboardItem(content: .image(image), date: date,
                                                        description: description, isHidden: isHidden, tagID: tagID))
                        }
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

    // MARK: - Recently Deleted

    /// Soft-deletes a history item — moves it to Recently Deleted instead of erasing it.
    func deleteHistoryItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        deletedItems.insert(item.withDeletion(tagName: nil, tagColor: nil, fromPinned: false), at: 0)
        saveHistory()
        saveDeletedItems()
    }

    /// Soft-deletes a pinned item — snapshots tag info for recovery, then removes it.
    func softDeletePinnedItem(_ item: ClipboardItem) {
        let tag = item.tagID.flatMap { id in tags.first(where: { $0.id == id }) }
        pinnedItems.removeAll { $0.id == item.id }
        deletedItems.insert(item.withDeletion(tagName: tag?.name, tagColor: tag?.colorHex, fromPinned: true), at: 0)
        savePinnedItems()
        saveDeletedItems()
        pruneOrphanedImageFiles()
    }

    /// Moves a deleted item back to where it came from (history or pinnedItems).
    /// Recreates its tag if the tag was deleted in the meantime.
    func recoverItem(_ item: ClipboardItem) {
        deletedItems.removeAll { $0.id == item.id }

        let recovered = item.withRecovery()

        if item.deletedFromPinned {
            // Recreate the tag if it's missing.
            if let tagID = item.tagID, !tags.contains(where: { $0.id == tagID }),
               let name = item.deletedTagName, let color = item.deletedTagColor {
                tags.append(ClipBoxTag(id: tagID, name: name, colorHex: color))
                saveTags()
            }
            // Dedup: if the same content was re-pinned while this item was in
            // Recently Deleted, drop the existing pin so we don't end up with
            // two pins of identical content.
            pinnedItems.removeAll { $0.deduplicationKey == recovered.deduplicationKey }
            pinnedItems.insert(recovered, at: 0)
            savePinnedItems()
        } else {
            history.removeAll { $0.deduplicationKey == recovered.deduplicationKey }
            history.insert(recovered, at: 0)
            if history.count > maxItems { history = Array(history.prefix(maxItems)) }
            saveHistory()
        }

        saveDeletedItems()
    }

    /// Recovers every item in Recently Deleted in one shot.
    /// History items that exceed maxItems are placed back in Recently Deleted
    /// rather than being silently discarded.
    func recoverAllItems() {
        let toRecover = deletedItems
        deletedItems.removeAll()

        var didCreateTag = false
        var overflowBack: [ClipboardItem] = []

        // Iterate oldest-first so the most recently deleted item ends up at
        // index 0 after we insert each recovered item at position 0.
        for item in toRecover.reversed() {
            let recovered = item.withRecovery()
            if item.deletedFromPinned {
                if let tagID = item.tagID, !tags.contains(where: { $0.id == tagID }),
                   let name = item.deletedTagName, let color = item.deletedTagColor {
                    tags.append(ClipBoxTag(id: tagID, name: name, colorHex: color))
                    didCreateTag = true
                }
                pinnedItems.removeAll { $0.deduplicationKey == recovered.deduplicationKey }
                pinnedItems.insert(recovered, at: 0)
            } else {
                history.removeAll { $0.deduplicationKey == recovered.deduplicationKey }
                history.insert(recovered, at: 0)
            }
        }

        if history.count > maxItems {
            let excess = Array(history.dropFirst(maxItems))
            history = Array(history.prefix(maxItems))
            overflowBack = excess.map {
                $0.withDeletion(tagName: nil, tagColor: nil, fromPinned: false)
            }
            deletedItems.insert(contentsOf: overflowBack, at: 0)
        }

        if didCreateTag { saveTags() }
        saveHistory()
        savePinnedItems()
        saveDeletedItems()
    }

    /// Permanently removes an item from Recently Deleted — no recovery possible.
    func permanentlyDelete(_ item: ClipboardItem) {
        deletedItems.removeAll { $0.id == item.id }
        saveDeletedItems()
        pruneOrphanedImageFiles()
    }

    func permanentlyDeleteAll() {
        deletedItems.removeAll()
        saveDeletedItems()
        pruneOrphanedImageFiles()
    }

    /// Removes items that have been in Recently Deleted for more than 7 days.
    /// Called at launch and from the UI whenever the user opens the Recently
    /// Deleted view, so long-running sessions still see auto-cleanup.
    func pruneExpiredDeletedItems() {
        let sevenDays: TimeInterval = 7 * 24 * 3600
        let now = Date()
        let before = deletedItems.count
        deletedItems.removeAll { item in
            guard let at = item.deletedAt else { return false }
            return now.timeIntervalSince(at) > sevenDays
        }
        if deletedItems.count != before {
            saveDeletedItems()
            pruneOrphanedImageFiles()
        }
    }

    // MARK: - Persist Recently Deleted

    private func saveDeletedItems() {
        let snapshot = deletedItems
        let dir      = imagesDirectory
        let key      = deletedIndexKey
        saveQueue.async {
            var entries: [[String: String]] = []
            for item in snapshot {
                var e: [String: String] = [
                    "id":   item.id.uuidString,
                    "date": Self.dateFormatter.string(from: item.date)
                ]
                if let at = item.deletedAt { e["deletedAt"] = Self.dateFormatter.string(from: at) }
                if let n  = item.deletedTagName  { e["deletedTagName"]  = n }
                if let c  = item.deletedTagColor { e["deletedTagColor"] = c }
                if let t  = item.tagID           { e["tagID"]           = t.uuidString }
                if item.deletedFromPinned        { e["fromPinned"]      = "1" }
                if let d  = item.description, !d.isEmpty { e["description"] = d }
                if item.isHidden                 { e["hidden"]          = "1" }

                switch item.content {
                case .text(let text):
                    e["type"]  = "text"
                    e["value"] = text
                case .image(let image):
                    let fromPinned = item.deletedFromPinned
                    let filename   = fromPinned ? "pinned_\(item.id).png" : "\(item.id).png"
                    let fileURL    = dir.appendingPathComponent(filename)
                    if !FileManager.default.fileExists(atPath: fileURL.path),
                       let pngData = image.pngData() {
                        try? pngData.write(to: fileURL)
                    }
                    e["type"]     = "image"
                    e["filename"] = filename
                }
                entries.append(e)
            }
            if let data = try? JSONEncoder().encode(entries) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private func loadDeletedItems() {
        guard let data    = UserDefaults.standard.data(forKey: deletedIndexKey),
              let entries = try? JSONDecoder().decode([[String: String]].self, from: data)
        else { return }

        var loaded: [ClipboardItem] = []

        for e in entries {
            guard let type    = e["type"],
                  let dateStr = e["date"],
                  let date    = Self.dateFormatter.date(from: dateStr),
                  let idStr   = e["id"],
                  let id      = UUID(uuidString: idStr)
            else { continue }

            let deletedAt       = e["deletedAt"].flatMap { Self.dateFormatter.date(from: $0) }
            let deletedTagName  = e["deletedTagName"]
            let deletedTagColor = e["deletedTagColor"]
            let tagID           = e["tagID"].flatMap { UUID(uuidString: $0) }
            let fromPinned      = e["fromPinned"] == "1"
            let description     = e["description"]
            let isHidden        = e["hidden"] == "1"

            switch type {
            case "text":
                if let text = e["value"] {
                    loaded.append(ClipboardItem(
                        loadedWithID:      id,
                        content:           .text(text),
                        date:              date,
                        description:       description,
                        isHidden:          isHidden,
                        tagID:             tagID,
                        deletedAt:         deletedAt,
                        deletedTagName:    deletedTagName,
                        deletedTagColor:   deletedTagColor,
                        deletedFromPinned: fromPinned
                    ))
                }
            case "image":
                if let filename = e["filename"] {
                    let fileURL = imagesDirectory.appendingPathComponent(filename)
                    if let image = NSImage(contentsOf: fileURL) {
                        loaded.append(ClipboardItem(
                            loadedWithID:      id,
                            content:           .image(image),
                            date:              date,
                            description:       description,
                            isHidden:          isHidden,
                            tagID:             tagID,
                            deletedAt:         deletedAt,
                            deletedTagName:    deletedTagName,
                            deletedTagColor:   deletedTagColor,
                            deletedFromPinned: fromPinned
                        ))
                    }
                }
            default:
                break
            }
        }

        deletedItems = loaded
    }

    func clearHistory() {
        let softDeleted = history.map {
            $0.withDeletion(tagName: nil, tagColor: nil, fromPinned: false)
        }
        history.removeAll()
        deletedItems.insert(contentsOf: softDeleted, at: 0)
        saveHistory()
        saveDeletedItems()
    }

    func clearAllPinned() {
        let softDeleted = pinnedItems.map { item -> ClipboardItem in
            let tag = item.tagID.flatMap { id in tags.first(where: { $0.id == id }) }
            return item.withDeletion(tagName: tag?.name, tagColor: tag?.colorHex, fromPinned: true)
        }
        pinnedItems.removeAll()
        tags.removeAll()
        deletedItems.insert(contentsOf: softDeleted, at: 0)
        saveTags()
        savePinnedItems()
        saveDeletedItems()
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

