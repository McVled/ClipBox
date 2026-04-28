//
//  PopupView.swift
//  ClipBox
//

import SwiftUI

struct PopupView: View {

    // MARK: - Dependencies

    @ObservedObject var clipboardManager = ClipboardManager.shared

    // MARK: - State

    enum Tab: String, CaseIterable {
        case history = "History"
        case pinned  = "Pinned"
    }

    @State private var selectedTab:     Tab      = .history
    @State private var selectedIndex:   Int      = 0
    @State private var isClearing:              Bool      = false
    @State private var showingClearConfirm:     Bool      = false
    @State private var showingTagDeleteConfirm: Bool      = false
    @State private var tagPendingDelete:        ClipBoxTag? = nil
    @State private var followCursor:    Bool     = PopupWindow.shared.followCursor
    @State private var showingSettings: Bool     = false
    @State private var isRecording:     Bool     = false
    @State private var shortcut:        Shortcut = HotkeyManager.shared.currentShortcut
    @State private var historyLimit:    Int      = {
        let v = UserDefaults.standard.integer(forKey: ClipboardManager.historyLimitKey)
        return v > 0 ? v : ClipboardManager.historyLimitDefault
    }()
    @State private var showInMenuBar:   Bool     = StatusBarController.isEnabled

    /// nil = top-level pinned list; non-nil = inside that tag's detail view.
    @State private var activeTagID: UUID? = nil

    /// Index of the focused tag flag in the top-level Pinned view; nil = item list focused.
    @State private var selectedTagIndex: Int? = nil

    // MARK: - Callbacks

    var onClose: () -> Void
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
                        withAnimation(.easeInOut(duration: 0.22)) { showingSettings = false }
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
                        StatusBarController.shared.setVisible(StatusBarController.showInMenuBarDefault)
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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
        // If the active tag is deleted, pop back to top level.
        .onChange(of: clipboardManager.tags.map(\.id)) { tagIDs in
            if let active = activeTagID, !tagIDs.contains(active) {
                activeTagID      = nil
                selectedTagIndex = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipBoxKeyDown)) { notification in
            guard let keyCode = notification.userInfo?["keyCode"] as? UInt16 else { return }
            let flagsRaw = notification.userInfo?["flags"] as? UInt ?? 0
            let chars    = notification.userInfo?["chars"] as? String ?? ""
            handleKey(keyCode: keyCode,
                      flags:   NSEvent.ModifierFlags(rawValue: flagsRaw),
                      chars:   chars)
        }
    }

    // MARK: - Main view

    private var mainView: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Text("ClipBox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { showingClearConfirm = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "trash").font(.system(size: 10))
                        Text("Clear").font(.system(size: 11))
                    }
                    .foregroundColor(clearDisabled ? .secondary.opacity(0.35) : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(clearDisabled || isClearing)

                Divider().frame(height: 12).padding(.horizontal, 2)

                Button(action: {
                    shortcut = HotkeyManager.shared.currentShortcut
                    withAnimation(.easeInOut(duration: 0.22)) { showingSettings = true }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "gearshape").font(.system(size: 10))
                        Text("Settings").font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 12).padding(.horizontal, 2)

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    HStack(spacing: 3) {
                        Image(systemName: "power").font(.system(size: 10))
                        Text("Quit").font(.system(size: 11))
                    }
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
            .onChange(of: selectedTab) { tab in
                selectedIndex = 0
                activeTagID   = nil
                if tab == .pinned {
                    selectedTagIndex = clipboardManager.tags.isEmpty ? nil : 0
                } else {
                    selectedTagIndex = nil
                }
            }

            Divider()

            // ── Content ──────────────────────────────────────────────────
            if selectedTab == .history {
                if clipboardManager.history.isEmpty {
                    emptyState(icon: "doc.on.clipboard",
                               title: "History is empty",
                               subtitle: "Copy something to get started")
                } else {
                    historyList
                }
            } else {
                pinnedContent
            }

            // ── Footer ───────────────────────────────────────────────────
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
        .alert(clearConfirmTitle, isPresented: $showingClearConfirm) {
            Button("Clear", role: .destructive, action: triggerClearWithAnimation)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .alert(tagDeleteConfirmTitle, isPresented: $showingTagDeleteConfirm) {
            Button("Move to Untagged") {
                if let tag = tagPendingDelete { performTagDelete(tag, moveToUntagged: true) }
            }
            Button("Delete Items", role: .destructive) {
                if let tag = tagPendingDelete { performTagDelete(tag, moveToUntagged: false) }
            }
            Button("Cancel", role: .cancel) { tagPendingDelete = nil }
        } message: {
            if let tag = tagPendingDelete {
                let count = clipboardManager.pinnedItems.filter { $0.tagID == tag.id }.count
                Text("What should happen to the \(count) item\(count == 1 ? "" : "s") in this tag?")
            }
        }
    }

    private var clearConfirmTitle: String {
        if let tagID = activeTagID,
           let tag = clipboardManager.tags.first(where: { $0.id == tagID }) {
            return "Clear \"\(tag.name)\"?"
        }
        return selectedTab == .history ? "Clear History?" : "Clear Pinned Items?"
    }

    private var tagDeleteConfirmTitle: String {
        "Delete \"\(tagPendingDelete?.name ?? "")\"?"
    }

    private func performTagDelete(_ tag: ClipBoxTag, moveToUntagged: Bool) {
        let currentIndex = selectedTagIndex
        if activeTagID == tag.id { activeTagID = nil }
        if moveToUntagged {
            clipboardManager.deleteTag(tag)
        } else {
            clipboardManager.deleteTagAndItems(tag)
        }
        tagPendingDelete = nil
        let newCount = clipboardManager.tags.count
        selectedTagIndex = newCount == 0 ? nil : currentIndex.map { min($0, newCount - 1) }
    }

    // MARK: - History list

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(clipboardManager.history.enumerated()), id: \.element.id) { index, item in
                        let existingPin = clipboardManager.existingPin(for: item)
                        let unpinAction: (() -> Void)? = existingPin.map { p in
                            { clipboardManager.unpinItem(p) }
                        }

                        ClipboardRowView(
                            item:        item,
                            index:       index,
                            isSelected:  index == selectedIndex,
                            isPinned:    false,
                            onSelect:    { onPaste(item) },
                            onPin: { description, isHidden, tagID in
                                clipboardManager.pinItem(item,
                                                         description: description,
                                                         isHidden:    isHidden,
                                                         tagID:       tagID)
                            },
                            onUnpin:     unpinAction,
                            existingPin: existingPin,
                            onDelete:    { clipboardManager.deleteHistoryItem(item) },
                            tags:        clipboardManager.tags,
                            onCreateTag: { name, colorHex in
                                clipboardManager.createTag(name: name, colorHex: colorHex).id
                            }
                        )
                        .id(item.id)
                        .opacity(isClearing ? 0 : 1)
                        .animation(.easeIn(duration: 0.25).delay(Double(index) * 0.04),
                                   value: isClearing)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { idx in
                guard idx < clipboardManager.history.count else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(clipboardManager.history[idx].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Pinned content

    @ViewBuilder
    private var pinnedContent: some View {
        if let tagID = activeTagID,
           let tag = clipboardManager.tags.first(where: { $0.id == tagID }) {
            // Inside a tag detail view
            tagDetailView(tag: tag)
        } else if clipboardManager.pinnedItems.isEmpty && clipboardManager.tags.isEmpty {
            emptyState(icon: "pin",
                       title: "No pinned items",
                       subtitle: "Pin items from History to keep them here")
        } else {
            pinnedTopLevel
        }
    }

    // Top-level pinned: tag flags section + untagged rows
    private var pinnedTopLevel: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {

                    // ── Tag flags ────────────────────────────────────────
                    if !clipboardManager.tags.isEmpty {
                        ScrollViewReader { tagProxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(clipboardManager.tags.enumerated()), id: \.element.id) { index, tag in
                                        TagFlagButton(
                                            tag:        tag,
                                            count:      clipboardManager.pinnedItems.filter { $0.tagID == tag.id }.count,
                                            isSelected: selectedTagIndex == index,
                                            onTap: {
                                                selectedIndex    = 0
                                                selectedTagIndex = nil
                                                activeTagID      = tag.id
                                            },
                                            onEdit: { newName, newColorHex in
                                                clipboardManager.editTag(tag, newName: newName, newColorHex: newColorHex)
                                            },
                                            onDelete: {
                                                if activeTagID == tag.id { activeTagID = nil }
                                                clipboardManager.deleteTag(tag)
                                            },
                                            onDeleteWithItems: {
                                                if activeTagID == tag.id { activeTagID = nil }
                                                clipboardManager.deleteTagAndItems(tag)
                                            }
                                        )
                                        .id(tag.id)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                            }
                            .onChange(of: selectedTagIndex) { idx in
                                guard let idx, idx < clipboardManager.tags.count else { return }
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    tagProxy.scrollTo(clipboardManager.tags[idx].id, anchor: .center)
                                }
                            }
                        }

                        Divider().padding(.horizontal, 6)
                    }

                    // ── Untagged rows ─────────────────────────────────────
                    let untagged = clipboardManager.pinnedItems.filter { $0.tagID == nil }
                    if untagged.isEmpty && !clipboardManager.tags.isEmpty {
                        Text("No untagged items")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.55))
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(untagged.enumerated()), id: \.element.id) { index, item in
                            pinnedRow(item: item, index: index)
                                .id(item.id)
                                .opacity(isClearing ? 0 : 1)
                                .animation(.easeIn(duration: 0.25).delay(Double(index) * 0.04),
                                           value: isClearing)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .onChange(of: selectedIndex) { idx in
                let items = currentItems
                guard idx < items.count else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(items[idx].id, anchor: .center)
                }
            }
        }
    }

    // Tag detail: mini-header + items belonging to this tag
    @ViewBuilder
    private func tagDetailView(tag: ClipBoxTag) -> some View {
        VStack(spacing: 0) {

            // Mini navigation header
            HStack {
                Button(action: {
                    selectedIndex = 0
                    activeTagID   = nil
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 11))
                        .foregroundColor(tag.color)
                    Text(tag.name)
                        .font(.system(size: 12, weight: .semibold))
                }

                Spacer()

                // Invisible spacer to balance the back button and keep title centred
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11))
                    Text("Back").font(.system(size: 11))
                }
                .hidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            let tagged = clipboardManager.pinnedItems.filter { $0.tagID == tag.id }
            if tagged.isEmpty {
                emptyState(icon: "flag",
                           title: "No items in \"\(tag.name)\"",
                           subtitle: "Use the flag icon on a pinned item to assign it")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(tagged.enumerated()), id: \.element.id) { index, item in
                                pinnedRow(item: item, index: index)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { idx in
                        guard idx < tagged.count else { return }
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(tagged[idx].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // Builds a single pinned row with tag assignment support
    private func pinnedRow(item: ClipboardItem, index: Int) -> some View {
        ClipboardRowView(
            item:       item,
            index:      index,
            isSelected: index == selectedIndex && selectedTagIndex == nil,
            isPinned:   true,
            onSelect:   { onPaste(item) },
            onUnpin:    { clipboardManager.unpinItem(item) },
            tags:       clipboardManager.tags,
            onAssignTag: { tagID in
                clipboardManager.assignTag(tagID, to: item.id)
            },
            onCreateAndAssignTag: { name, colorHex in
                let tag = clipboardManager.createTag(name: name, colorHex: colorHex)
                clipboardManager.assignTag(tag.id, to: item.id)
            }
        )
    }

    // MARK: - Empty state

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.4))
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Computed Properties

    /// Items used for keyboard navigation (varies by tab + active tag).
    private var currentItems: [ClipboardItem] {
        if selectedTab == .history { return clipboardManager.history }
        if let tagID = activeTagID {
            return clipboardManager.pinnedItems.filter { $0.tagID == tagID }
        }
        return clipboardManager.pinnedItems.filter { $0.tagID == nil }
    }

    /// Whether the Clear button should be disabled.
    private var clearDisabled: Bool {
        if selectedTab == .history { return clipboardManager.history.isEmpty }
        if let tagID = activeTagID {
            return clipboardManager.pinnedItems.filter { $0.tagID == tagID }.isEmpty
        }
        return clipboardManager.pinnedItems.isEmpty
    }

    // MARK: - Clear Animation

    private func triggerClearWithAnimation() {
        // Inside a tag view: immediately unpin all items in that tag, then pop back.
        if let tagID = activeTagID {
            activeTagID = nil
            selectedIndex = 0
            ClipboardManager.shared.clearPinnedItems(withTagID: tagID)
            return
        }

        guard !isClearing else { return }
        isClearing = true

        let itemCount  = currentItems.count
        let totalDelay = 0.25 + Double(itemCount) * 0.04 + 0.1
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

    private func handleKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String) {
        if isRecording {
            handleRecordingKey(keyCode: keyCode, flags: flags, chars: chars)
            return
        }

        let tags = clipboardManager.tags
        let inTagNav = selectedTab == .pinned && activeTagID == nil && selectedTagIndex != nil

        // Escape: back from tag view → back from settings → close popup
        if keyCode == 53 {
            if showingSettings {
                withAnimation(.easeInOut(duration: 0.22)) { showingSettings = false }
            } else if let tagID = activeTagID {
                let restoredIndex = clipboardManager.tags.firstIndex(where: { $0.id == tagID })
                activeTagID      = nil
                selectedIndex    = 0
                selectedTagIndex = restoredIndex
            } else {
                onClose()
            }
            return
        }

        if showingSettings { return }

        // ← Arrow
        if keyCode == 123 {
            guard activeTagID == nil else { return }
            if inTagNav, let ti = selectedTagIndex, ti > 0 {
                selectedTagIndex = ti - 1
            } else if inTagNav {
                selectedTagIndex = nil
                selectedTab      = .history
            } else {
                selectedTab      = .history
                selectedTagIndex = nil
            }
            return
        }

        // → Arrow
        if keyCode == 124 {
            if inTagNav, let ti = selectedTagIndex, ti < tags.count - 1 {
                selectedTagIndex = ti + 1
            } else if !inTagNav {
                selectedTab = .pinned
            }
            return
        }

        // ↑ Arrow
        if keyCode == 126 {
            if selectedTab == .pinned, activeTagID == nil {
                if inTagNav {
                    // tags are horizontal; nothing above — do nothing
                } else if selectedIndex == 0, !tags.isEmpty {
                    selectedTagIndex = 0   // jump up into tag row
                } else {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
            } else {
                let items = currentItems
                guard items.count > 0 else { return }
                if selectedIndex >= items.count { selectedIndex = items.count - 1 }
                selectedIndex = max(selectedIndex - 1, 0)
            }
            return
        }

        // ↓ Arrow
        if keyCode == 125 {
            if inTagNav {
                let hasUntagged = clipboardManager.pinnedItems.contains { $0.tagID == nil }
                guard hasUntagged else { return }
                selectedTagIndex = nil
                selectedIndex    = 0
            } else {
                let items = currentItems
                guard items.count > 0 else { return }
                if selectedIndex >= items.count { selectedIndex = items.count - 1 }
                selectedIndex = min(selectedIndex + 1, items.count - 1)
            }
            return
        }

        // Delete (⌫ = 51, ⌦ = 117)
        if keyCode == 51 || keyCode == 117 {
            if inTagNav, let ti = selectedTagIndex, ti < tags.count {
                let tag = tags[ti]
                let count = clipboardManager.pinnedItems.filter { $0.tagID == tag.id }.count
                if count == 0 {
                    performTagDelete(tag, moveToUntagged: true)
                } else {
                    tagPendingDelete        = tag
                    showingTagDeleteConfirm = true
                }
            } else {
                let items = currentItems
                guard !items.isEmpty, selectedIndex < items.count else { return }
                let item = items[selectedIndex]
                if selectedTab == .history {
                    clipboardManager.deleteHistoryItem(item)
                } else {
                    clipboardManager.unpinItem(item)
                }
                selectedIndex = min(selectedIndex, max(0, currentItems.count - 1))
            }
            return
        }

        // Return / Numpad Enter
        if keyCode == 36 || keyCode == 76 {
            if inTagNav, let ti = selectedTagIndex, ti < tags.count {
                selectedTagIndex = nil
                selectedIndex    = 0
                activeTagID      = tags[ti].id
            } else {
                let items = currentItems
                guard items.count > 0 else { return }
                if selectedIndex >= items.count { selectedIndex = items.count - 1 }
                onPaste(items[selectedIndex])
            }
            return
        }
    }

    // MARK: - Shortcut Recording

    private func handleRecordingKey(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String) {
        if keyCode == 53 {
            isRecording = false
            HotkeyManager.shared.isRecording = false
            return
        }

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
            command:  flags.contains(.command),
            shift:    flags.contains(.shift),
            option:   flags.contains(.option),
            control:  flags.contains(.control),
            keyCode:  keyCode,
            keyLabel: label
        )

        guard new.hasModifier else { return }

        shortcut = new
        HotkeyManager.shared.currentShortcut = new
        isRecording = false
        HotkeyManager.shared.isRecording = false
    }

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

// MARK: - TagFlagButton

private struct TagFlagButton: View {

    let tag:              ClipBoxTag
    let count:            Int
    let isSelected:       Bool
    let onTap:            () -> Void
    let onEdit:           (String, String) -> Void
    let onDelete:         () -> Void   // move items to untagged
    let onDeleteWithItems: () -> Void  // remove items too

    @State private var showingEdit          = false
    @State private var showingDeleteConfirm = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 16))
                    .foregroundColor(tag.color)
                Text(tag.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .frame(minWidth: 52)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? tag.color.opacity(0.18) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isSelected ? tag.color.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            PopoverAnchor(isPresented: $showingEdit, preferredEdge: .minY) {
                TagEditPopover(
                    tag:      tag,
                    onSave: { name, colorHex in
                        showingEdit = false
                        onEdit(name, colorHex)
                    },
                    onCancel: { showingEdit = false }
                )
            }
        )
        .contextMenu {
            Button("Edit…") { showingEdit = true }
            Divider()
            Button("Delete Tag", role: .destructive) {
                if count == 0 {
                    onDelete()
                } else {
                    showingDeleteConfirm = true
                }
            }
        }
        .alert("Delete \"\(tag.name)\"?", isPresented: $showingDeleteConfirm) {
            Button("Move to Untagged", action: onDelete)
            Button("Delete Items", role: .destructive, action: onDeleteWithItems)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("What should happen to the \(count) item\(count == 1 ? "" : "s") in this tag?")
        }
    }
}

// MARK: - TagEditPopover

private struct TagEditPopover: View {

    let tag:      ClipBoxTag
    let onSave:   (String, String) -> Void
    let onCancel: () -> Void

    @State private var name:     String
    @State private var colorHex: String

    @FocusState private var nameFocused: Bool

    init(tag: ClipBoxTag, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.tag      = tag
        self.onSave   = onSave
        self.onCancel = onCancel
        _name     = State(initialValue: tag.name)
        _colorHex = State(initialValue: tag.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Tag")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            TextField("Tag name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($nameFocused)
                .onSubmit { save() }

            HStack(spacing: 6) {
                ForEach(ClipBoxTag.palette, id: \.self) { hex in
                    let selected = colorHex == hex
                    Circle()
                        .fill(Color(hex: hex) ?? .accentColor)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: selected ? 2 : 0))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                        .onTapGesture { colorHex = hex }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).controlSize(.small).keyboardShortcut(.cancelAction)
                Button("Save",   action: save).controlSize(.small).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 220)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, colorHex)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let clipBoxKeyDown = Notification.Name("clipBoxKeyDown")
}
