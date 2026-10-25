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
    /// Hard limit on pinned items. New pin attempts past this point are rejected
    /// and surfaced to the UI via `.clipBoxPinLimitReached` so the user can
    /// unpin something explicitly — silently dropping a pin they just chose
    /// would feel like a bug.
    static let pinnedLimit         = 100
    /// Hard limit on Recently Deleted entries. When exceeded the oldest are
    /// permanently dropped FIFO. This is on top of the 7-day auto-clean, so
    /// rapid mass-deletes can't balloon storage in a single afternoon.
    static let deletedItemsLimit   = 200
    private static let tagsKey     = "com.clipbox.tags"
    private static let dateFormatter = ISO8601DateFormatter()

    var maxItems: Int {
        let v = UserDefaults.standard.integer(forKey: Self.historyLimitKey)
        return v > 0 ? v : Self.historyLimitDefault
    }

    /// Truncates `history` to the current `maxItems`. Soft-deletes the dropped
    /// items into Recently Deleted instead of hard-erasing them — lowering the
    /// History Size in Settings (or hitting Reset to Defaults) is a config
    /// change, not an explicit "delete my data" gesture, so the items should
    /// stay recoverable for the usual 7-day window.
    func applyHistoryLimit() {
        let limit = maxItems
        guard history.count > limit else { return }
        let dropped = history.suffix(history.count - limit).map {
            $0.withDeletion(tagName: nil, tagColor: nil, fromPinned: false)
        }
        history = Array(history.prefix(limit))
        deletedItems.insert(contentsOf: dropped, at: 0)
        enforceDeletedItemsLimit()
        saveHistory()
        saveDeletedItems()
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
        // Trim only after every list is loaded: saving prunes image files that
        // no list references, so saving earlier would treat pinned and Recently
        // Deleted images as orphans and delete them from disk.
        applyHistoryLimit()
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
        let previousTagID = pinnedItems[index].tagID
        pinnedItems[index] = pinnedItems[index].withTagID(tagID)
        savePinnedItems()
        // If the item used to belong to a tag, the old tag may now be empty —
        // prune so empty flags don't linger in the UI until restart.
        if previousTagID != nil, previousTagID != tagID {
            pruneEmptyTags()
        }
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
        enforceDeletedItemsLimit()
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

        // Left untrimmed on purpose — `init` applies the history limit once all
        // lists are loaded.
        history = loaded
    }

    // MARK: - Pinned Items

    func existingPin(for item: ClipboardItem) -> ClipboardItem? {
        pinnedItems.first(where: { $0.deduplicationKey == item.deduplicationKey })
    }

    func pinItem(_ item: ClipboardItem, description: String? = nil, isHidden: Bool = false, tagID: UUID? = nil) {
        // The pin dialog's "Create & Pin" creates its tag before calling here,
        // so every refusal below prunes empty tags — otherwise that new tag
        // would linger with zero items until the next launch.
        guard !pinnedItems.contains(where: { $0.deduplicationKey == item.deduplicationKey }) else {
            pruneEmptyTags()
            return
        }
        // Refuse new pins past the hard limit. Posting a notification lets the
        // popup show an alert without ClipboardManager knowing about SwiftUI.
        guard pinnedItems.count < Self.pinnedLimit else {
            pruneEmptyTags()
            NotificationCenter.default.post(name: .clipBoxPinLimitReached, object: nil)
            return
        }
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

    /// Removes a pinned item via the History row's "Already pinned" popover.
    /// Routes through `softDeletePinnedItem` so the user's privacy label,
    /// description, and tag assignment survive in Recently Deleted — a hard
    /// delete here would silently destroy that metadata with no recovery.
    func unpinItem(_ item: ClipboardItem) {
        softDeletePinnedItem(item)
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

    /// Trims `deletedItems` down to `deletedItemsLimit` by permanently
    /// dropping the oldest entries.  Call after any insertion path.
    private func enforceDeletedItemsLimit() {
        guard deletedItems.count > Self.deletedItemsLimit else { return }
        deletedItems = Array(deletedItems.prefix(Self.deletedItemsLimit))
    }

    /// Soft-deletes a history item — moves it to Recently Deleted instead of erasing it.
    func deleteHistoryItem(_ item: ClipboardItem) {
        history.removeAll { $0.id == item.id }
        deletedItems.insert(item.withDeletion(tagName: nil, tagColor: nil, fromPinned: false), at: 0)
        enforceDeletedItemsLimit()
        saveHistory()
        saveDeletedItems()
    }

    /// Soft-deletes a pinned item — snapshots tag info for recovery, then removes it.
    func softDeletePinnedItem(_ item: ClipboardItem) {
        let tag = item.tagID.flatMap { id in tags.first(where: { $0.id == id }) }
        pinnedItems.removeAll { $0.id == item.id }
        deletedItems.insert(item.withDeletion(tagName: tag?.name, tagColor: tag?.colorHex, fromPinned: true), at: 0)
        enforceDeletedItemsLimit()
        savePinnedItems()
        saveDeletedItems()
        if item.tagID != nil { pruneEmptyTags() }
        pruneOrphanedImageFiles()
    }

    /// Moves a deleted item back to where it came from (history or pinnedItems).
    /// Recreates its tag if the tag was deleted in the meantime. Recovery of a
    /// pinned item is refused when the pin list is already full and the
    /// recovery wouldn't displace a duplicate — the item stays in Recently
    /// Deleted and the popup shows the same alert as a fresh pin attempt.
    func recoverItem(_ item: ClipboardItem) {
        let recovered = item.withRecovery()

        if item.deletedFromPinned {
            let duplicateExists = pinnedItems.contains { $0.deduplicationKey == recovered.deduplicationKey }
            if !duplicateExists, pinnedItems.count >= Self.pinnedLimit {
                NotificationCenter.default.post(name: .clipBoxPinLimitReached, object: nil)
                return
            }
            deletedItems.removeAll { $0.id == item.id }
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
            deletedItems.removeAll { $0.id == item.id }
            history.removeAll { $0.deduplicationKey == recovered.deduplicationKey }
            history.insert(recovered, at: 0)
            if history.count > maxItems { history = Array(history.prefix(maxItems)) }
            saveHistory()
        }

        saveDeletedItems()
    }

    /// Recovers every item in Recently Deleted in one shot.
    /// History items that exceed maxItems are placed back in Recently Deleted
    /// rather than being silently discarded. Pinned items that would exceed
    /// `pinnedLimit` likewise stay in Recently Deleted; we notify the popup so
    /// it can show the same alert as a manual over-limit pin attempt.
    func recoverAllItems() {
        let toRecover = deletedItems
        var stillDeleted: [ClipboardItem] = []
        var didCreateTag = false
        var pinLimitHit  = false

        // Iterate oldest-first so the most recently deleted item ends up at
        // index 0 after we insert each recovered item at position 0.
        for item in toRecover.reversed() {
            let recovered = item.withRecovery()
            if item.deletedFromPinned {
                let duplicateExists = pinnedItems.contains { $0.deduplicationKey == recovered.deduplicationKey }
                if !duplicateExists, pinnedItems.count >= Self.pinnedLimit {
                    // Keep the original (still with deletion metadata) so the
                    // 7-day countdown is preserved.
                    stillDeleted.append(item)
                    pinLimitHit = true
                    continue
                }
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

        // `stillDeleted` was built oldest-first; reverse so the array as a
        // whole stays newest-first like `deletedItems`.
        deletedItems = stillDeleted.reversed()

        if history.count > maxItems {
            let excess = Array(history.dropFirst(maxItems))
            history = Array(history.prefix(maxItems))
            let overflowBack = excess.map {
                $0.withDeletion(tagName: nil, tagColor: nil, fromPinned: false)
            }
            deletedItems.insert(contentsOf: overflowBack, at: 0)
        }
        enforceDeletedItemsLimit()

        if didCreateTag { saveTags() }
        saveHistory()
        savePinnedItems()
        saveDeletedItems()

        if pinLimitHit {
            NotificationCenter.default.post(name: .clipBoxPinLimitReached, object: nil)
        }
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
        enforceDeletedItemsLimit()
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
        enforceDeletedItemsLimit()
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
            // Write both TIFF and PNG. Many AppKit apps (Preview, Pages,
            // Keynote, several mail clients) only look at .tiff on paste and
            // leave the destination empty when only .png is present.
            let pngData  = image.pngData()
            let tiffData = image.tiffRepresentation
            guard pngData != nil || tiffData != nil else { return }
            pb.clearContents()
            if let tiff = tiffData { pb.setData(tiff, forType: .tiff) }
            if let png  = pngData  { pb.setData(png,  forType: .png)  }
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

// MARK: - Backup & Restore

extension ClipboardManager {

    /// 4-byte magic header so we can validate the file and version the format.
    private static let backupMagic = Data([0x43, 0x42, 0x42, 0x01])  // "CBB\x01"

    /// Highest backup file format the current build understands. Backups with a
    /// higher version are rejected on import to prevent partial / corrupt restores.
    static let currentBackupVersion = 1

    /// Thread-safe backup encoder.  Operates ONLY on its parameters and never
    /// touches `self.*` @Published state, so it's safe to call off the main
    /// thread.  Callers must snapshot the arrays on main before invoking this.
    static func encodeBackup(
        tags:          [ClipBoxTag],
        pinnedItems:   [ClipboardItem],
        history:       [ClipboardItem],
        deletedItems:  [ClipboardItem],
        historyLimit:  Int,
        followCursor:  Bool,
        showInMenuBar: Bool,
        shortcut:      Shortcut
    ) throws -> Data {
        let settings = BackupSettings(
            historyLimit:  historyLimit,
            followCursor:  followCursor,
            showInMenuBar: showInMenuBar,
            shortcut:      shortcut
        )
        let backup = ClipBoxBackup(
            version:         Self.currentBackupVersion,
            exportedAt:      Date(),
            settings:        settings,
            tags:            tags.map         { BackupTag($0) },
            pinnedItems:     pinnedItems.map  { BackupItem($0) },
            history:         history.map      { BackupItem($0) },
            recentlyDeleted: deletedItems.map { BackupItem($0) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting     = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(backup)

        // LZFSE compression — typically 5–10× smaller than raw JSON+base64.
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        return Self.backupMagic + compressed
    }

    /// Convenience that snapshots @Published state from the current (main)
    /// thread and forwards to `encodeBackup`. Use this only from main; for
    /// background work, snapshot manually and call `encodeBackup` directly.
    func exportBackup(historyLimit: Int,
                      followCursor: Bool,
                      showInMenuBar: Bool,
                      shortcut: Shortcut) throws -> Data {
        try Self.encodeBackup(
            tags:          tags,
            pinnedItems:   pinnedItems,
            history:       history,
            deletedItems:  deletedItems,
            historyLimit:  historyLimit,
            followCursor:  followCursor,
            showInMenuBar: showInMenuBar,
            shortcut:      shortcut
        )
    }

    /// Result of `decodeBackup` — a thread-safe value holding everything needed
    /// to restore state. Pass to `applyDecoded(_:)` on the main thread.
    struct DecodedBackup {
        let historyLimit:  Int
        let followCursor:  Bool
        let showInMenuBar: Bool
        let shortcut:      Shortcut
        let tags:          [ClipBoxTag]
        let pinnedItems:   [ClipboardItem]
        let history:       [ClipboardItem]
        let deletedItems:  [ClipboardItem]
    }

    /// Thread-safe decoder.  Validates header, decompresses, parses JSON,
    /// checks version, and rebuilds NSImages from base64.  Does NOT touch
    /// any @Published state — safe to call off the main thread.
    static func decodeBackup(_ rawData: Data) throws -> DecodedBackup {
        guard rawData.count > backupMagic.count,
              rawData.prefix(backupMagic.count) == backupMagic else {
            throw NSError(domain: "ClipBox", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "This file is not a ClipBox backup."])
        }
        let payload = rawData.subdata(in: backupMagic.count..<rawData.count)
        let json: Data
        do {
            json = try (payload as NSData).decompressed(using: .lzfse) as Data
        } catch {
            throw NSError(domain: "ClipBox", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The backup file is corrupted and cannot be decompressed."])
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: ClipBoxBackup
        do {
            backup = try decoder.decode(ClipBoxBackup.self, from: json)
        } catch {
            throw NSError(domain: "ClipBox", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "The backup file's format is invalid or unreadable."])
        }

        guard backup.version <= currentBackupVersion else {
            throw NSError(domain: "ClipBox", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "This backup was created by a newer version of ClipBox. Please update the app and try again."])
        }

        return DecodedBackup(
            historyLimit:  backup.settings.historyLimit,
            followCursor:  backup.settings.followCursor,
            showInMenuBar: backup.settings.showInMenuBar,
            shortcut:      backup.settings.shortcut,
            tags:          backup.tags.map { ClipBoxTag(id: $0.id, name: $0.name, colorHex: $0.colorHex) },
            pinnedItems:   backup.pinnedItems.compactMap     { $0.toClipboardItem() },
            history:       backup.history.compactMap         { $0.toClipboardItem() },
            deletedItems:  backup.recentlyDeleted.compactMap { $0.toClipboardItem() }
        )
    }

    /// Main-thread restore — applies a previously decoded backup to live state.
    /// Truncates history to the current `maxItems` (which we set first from the
    /// decoded settings) so the imported history fits the user's chosen limit.
    func applyDecoded(_ d: DecodedBackup) {
        UserDefaults.standard.set(d.historyLimit, forKey: Self.historyLimitKey)
        PopupWindow.shared.followCursor       = d.followCursor
        StatusBarController.shared.setVisible(d.showInMenuBar)
        HotkeyManager.shared.currentShortcut  = d.shortcut.hasModifier ? d.shortcut : .default

        // Clamp every list to its hard limit so a stale or hand-edited backup
        // can't drag the running app past invariants the rest of the code
        // assumes (e.g. pinned-row counts in alerts, FIFO eviction in deleted).
        tags         = d.tags
        pinnedItems  = Array(d.pinnedItems.prefix(Self.pinnedLimit))
        history      = Array(d.history.prefix(maxItems))
        deletedItems = Array(d.deletedItems.prefix(Self.deletedItemsLimit))

        // Drop items already past the 7-day window inside the backup so they
        // don't briefly resurface in Recently Deleted, and drop tags with no
        // items — matches the same cleanup loadPinnedItems performs at launch.
        pruneExpiredDeletedItems()
        pruneEmptyTags()

        saveTags()
        savePinnedItems()
        saveHistory()
        saveDeletedItems()
        pruneOrphanedImageFiles()
    }

    /// Convenience for synchronous import on the main thread. For large
    /// backups, prefer `decodeBackup` (background) + `applyDecoded` (main)
    /// to keep the UI responsive.
    func importBackup(_ rawData: Data) throws {
        let decoded = try Self.decodeBackup(rawData)
        applyDecoded(decoded)
    }
}

// MARK: - Backup Codable types (file-private)

private struct ClipBoxBackup: Codable {
    let version:         Int
    let exportedAt:      Date
    let settings:        BackupSettings
    let tags:            [BackupTag]
    let pinnedItems:     [BackupItem]
    let history:         [BackupItem]
    let recentlyDeleted: [BackupItem]
}

private struct BackupSettings: Codable {
    let historyLimit:  Int
    let followCursor:  Bool
    let showInMenuBar: Bool
    let shortcut:      Shortcut
}

private struct BackupTag: Codable {
    let id:       UUID
    let name:     String
    let colorHex: String

    init(_ tag: ClipBoxTag) {
        id       = tag.id
        name     = tag.name
        colorHex = tag.colorHex
    }
}

private struct BackupItem: Codable {
    let id:                UUID
    let type:              String
    let text:              String?
    let imageBase64:       String?
    let date:              Date
    let description:       String?
    let isHidden:          Bool
    let tagID:             UUID?
    let deletedAt:         Date?
    let deletedTagName:    String?
    let deletedTagColor:   String?
    let deletedFromPinned: Bool

    init(_ item: ClipboardItem) {
        id                = item.id
        date              = item.date
        description       = item.description
        isHidden          = item.isHidden
        tagID             = item.tagID
        deletedAt         = item.deletedAt
        deletedTagName    = item.deletedTagName
        deletedTagColor   = item.deletedTagColor
        deletedFromPinned = item.deletedFromPinned
        switch item.content {
        case .text(let t):
            type = "text"; text = t; imageBase64 = nil
        case .image(let img):
            type = "image"; text = nil
            imageBase64 = img.pngData()?.base64EncodedString()
        }
    }

    func toClipboardItem() -> ClipboardItem? {
        let content: ClipboardContent
        switch type {
        case "text":
            guard let t = text else { return nil }
            content = .text(t)
        case "image":
            guard let b64  = imageBase64,
                  let data = Data(base64Encoded: b64),
                  let img  = NSImage(data: data) else { return nil }
            content = .image(img)
        default:
            return nil
        }
        return ClipboardItem(
            loadedWithID:      id,
            content:           content,
            date:              date,
            description:       description,
            isHidden:          isHidden,
            tagID:             tagID,
            deletedAt:         deletedAt,
            deletedTagName:    deletedTagName,
            deletedTagColor:   deletedTagColor,
            deletedFromPinned: deletedFromPinned
        )
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

