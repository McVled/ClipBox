# ClipBox

<p align="center">
  <a href="docs/media/clipbox-showreel.mp4">
    <img src="docs/media/clipbox-showreel.gif" alt="ClipBox in 30 seconds: clipboard history, private pins, tags & search, Recently Deleted" width="100%">
  </a>
  <br>
  <sub>▶ <a href="docs/media/clipbox-showreel.mp4">Watch in full HD (MP4, 30 s)</a></sub>
</p>

ClipBox is a lightweight macOS **clipboard history manager** that runs entirely in the background, keeping a full record of everything you copy — text and images — so nothing is ever lost.

Press **⌘⇧V** (or your custom shortcut) from any app to summon a floating popup near your cursor. Browse your clipboard history, pin important items to keep them forever, organize them with color-coded tags, and paste any of them back with a single keystroke.

**ClipBox also works as a lightweight password manager.** Pin any sensitive text — passwords, API keys, secret tokens — as a **private item**. The row shows only bullet dots (scaled to the real length) and a label you choose; the actual content is never displayed but pastes normally when you need it. Items are grouped by tag, hidden behind a press-and-hold or popover reveal, and protected from accidental deletion by the Recently Deleted safety net.

---

## Features

### Clipboard History
- **Text & image capture** — Automatically records everything you copy — plain text and images.
- **Persistent history** — Survives app restarts. Text is stored in UserDefaults; images are saved as PNG files in Application Support.
- **Configurable size** — Keep 10, 15, 20, 25, or 50 items. Oldest are removed automatically when the limit is reached.
- **Deduplication** — Copying the same content again moves it to the top instead of creating a duplicate.

### Pinned Items
- **Pin anything permanently** — Pin any item from History to keep it in the Pinned tab forever, unaffected by the history limit or Clear.
- **Capacity** — Up to **100 pinned items**. When you reach the limit, ClipBox tells you so you can unpin something deliberately instead of silently dropping a pin you just chose.
- **Public pin** — Item displays and pastes normally.
- **Private pin** — The row shows bullets scaled to the text length so you can tell at a glance how long the content is. A custom label is shown instead of content. The real content is still pasted as-is — hiding is purely visual.
- **Privacy toggle** — A lock button sits next to the tag flag on every pinned row. Closed lock = private, open lock = public. Tap to switch instantly; going public→private opens a label-entry dialog.
- **Press-and-hold reveal** — For short private items (≤ 30 chars), press and hold the eye icon to momentarily reveal the text; release to hide it again.
- **Popover reveal** — For longer private items, the eye icon opens a floating preview popover.
- **Tag on pin** — Choose or create a tag directly from the pin dialog.

### Tags
- **Color-coded folders** — Group pinned items into named tags, each with a color chosen from a 10-color palette (ordered warm → cool: red, orange, yellow, brown, green, teal, cyan, blue, light pink, hot pink).
- **Tag detail view** — Click a tag flag to see only its items; navigate back with the back button or **Esc**.
- **Assign after pinning** — Click the flag icon on any pinned row to change or remove its tag at any time.
- **Inline tag creation** — Create a new tag directly from the pin dialog or the flag popover, without leaving your workflow.
- **Edit tags** — Right-click any tag flag → **Edit…** to rename or recolor.
- **Delete tags** — Right-click any tag flag → **Delete Tag**, then choose to move items to Untagged or delete them together with the tag.
- **Clear tag** — Clearing from inside a tag detail view sends the tag and all its items to Recently Deleted.

### Recently Deleted
- **Soft-delete** — Nothing is permanently erased immediately. Deleting a history item, unpinning, or using any Clear button moves items to Recently Deleted first.
- **7-day auto-expiry** — Items are automatically and permanently removed 7 days after deletion. The footer shows "Auto-Clean in X days" (or "Auto-Clean today") so you always know how soon the next cleanup is.
- **Capacity** — Up to **200 entries**. When exceeded the oldest are permanently dropped (FIFO), so a single afternoon of mass-deletes can't balloon storage.
- **Recover items** — Restore a single item with the ↩ button, or restore everything at once with **Recover All** (confirmation required).
- **Delete forever** — Remove a single item permanently with the 🗑 button, or wipe everything with **Delete All** (confirmation required).
- **Tag restoration** — If a recovered item belonged to a tag that was since deleted, the tag is recreated automatically so the item lands back exactly where it was.
- **Smart badge** — The "Recently Deleted" badge in the footer is grayed-out when empty and fills with a solid background when items are waiting, making it easy to spot.

### Backup & Restore
- **One-file backup** — Export everything (settings, tags, pinned items, history, Recently Deleted) into a single `.clipboxbackup` file from the Settings header.
- **Compressed** — Uses LZFSE compression (typically 5–10× smaller than raw JSON+base64), so backups stay compact even with many images.
- **Format-validated import** — Files are checked by magic header and version before any state is touched; invalid or future-version files are rejected with a specific error message.
- **Background processing** — Encode and decode run on a background queue with a spinner in the Settings header, so the UI stays responsive even for backups with dozens of images.
- **Safe replace** — Importing replaces all clipboard data and settings; ClipBox asks for confirmation first and lands you back on the History tab so the restored data is immediately visible.

### Search
- **Type-ahead** — Start typing anywhere in the popup to instantly filter the visible list.
- **Works in all views** — Filters History, Pinned (top-level), and tag detail views.
- **Smart tag filtering** — While searching in Pinned, only tags with matching items are shown.
- **Visual indicator** — Active search query is displayed in the footer with a one-click ✕ to clear.
- **Safe Clear** — The Clear button is disabled while a search is active to prevent accidentally clearing hidden items.

### Navigation
- **Full keyboard control** — Navigate everything without touching the mouse.
- **Type-ahead search** — Any printable character (without modifiers) appends to the search filter.
- **Hierarchical Esc** — Clears search → exits tag view → closes popup, in that order.

### Paste
- **One keystroke** — Press **Enter** or click any row to paste it instantly into the app you were using.
- **Focus-preserving** — ClipBox restores focus to your previous app before pasting, so the content lands exactly where your cursor was.

### Interface
- **Floating popup** — Opens near your cursor without activating ClipBox or stealing focus from your work.
- **Draggable** — Click and drag the popup to reposition it anywhere on screen.
- **Smart positioning** — Auto-adjusts to stay within screen bounds; flips direction near edges.
- **Dynamic menu bar icon** — The icon fills when you have items and empties when everything is cleared.
- **Adaptive appearance** — Follows system Light / Dark mode automatically.

---

## Requirements

| | |
|---|---|
| **macOS** | 12 Monterey or later |
| **Permissions** | Accessibility (required for global hotkey and simulated paste) |

---

## Installation

1. Download the latest `ClipBox.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag **ClipBox** into the **Applications** folder.
3. Launch ClipBox from **Applications** or **Spotlight** (⌘Space → "ClipBox").

**First launch — Gatekeeper warning**

Because ClipBox is not notarized, macOS will block it on first open with *"ClipBox cannot be opened because the developer cannot be verified."*

Open **Terminal** (⌘Space → "Terminal") and run this once:

```bash
xattr -cr /Applications/ClipBox.app
```

Then open ClipBox normally.

**First launch — Accessibility permission**

ClipBox will prompt for Accessibility access. This is required for the global shortcut and the simulated ⌘V paste. Click **Open System Settings** and enable ClipBox under Privacy & Security → Accessibility.

---

## Usage

### Popup

| Action | How |
|--------|-----|
| Open popup | Global shortcut (default **⌘⇧V**) from any app |
| Open from menu bar | Click the clipboard icon (enable it first in Settings → **Show in Menu Bar**) |
| Close popup | **Esc** or click outside |
| Move popup | Click and drag the popup background |

### Navigation

| Action | How |
|--------|-----|
| Switch tabs | **← / →** arrow keys or click **History / Pinned** |
| Move through list | **↑ / ↓** arrow keys |
| Navigate tag flags | **← / →** while focused on the tag row |
| Enter a tag folder | **Enter** while a tag flag is selected, or click the flag |
| Go back from tag | **Esc** or the back button |
| Paste selected item | **Enter** or click the row |
| Search | Just type — any character without a modifier starts filtering |
| Clear search | **Esc** or click **✕** in the footer |

### Items

| Action | How |
|--------|-----|
| Pin an item | Hover a history row → click the **pin icon** → choose Public or Private, optionally add a tag → **Pin** |
| Unpin an item | In Pinned tab: click the **✕** icon (moves to Recently Deleted); in History: pin icon → **Unpin** |
| Toggle privacy on a pin | Click the **lock icon** on the pinned row (open = public, closed = private) |
| Reveal a short private item | Press and hold the **eye icon** |
| Preview a long private item | Click the **eye icon** to open a popover |
| Delete from history | Hover a row → click the **✕** icon (moves to Recently Deleted) |
| Delete selected item | **⌘⌫** or **⌦** |
| Clear all in active view | **Clear** button in the header → confirm (moves to Recently Deleted) |
| Open Recently Deleted | Click the **Recently Deleted** badge in the footer |
| Recover a deleted item | In Recently Deleted → click **↩** on the row |
| Delete an item forever | In Recently Deleted → click **🗑** on the row |
| Recover all | In Recently Deleted → **Recover All** → confirm |
| Delete all forever | In Recently Deleted → **Delete All** → confirm |

### Tags

| Action | How |
|--------|-----|
| Assign a tag while pinning | Pin dialog → Tag section → select chip or click **New tag…** |
| Assign / change a tag after pinning | Click the **flag icon** on any pinned row |
| Create a new tag | Any tag popover → **New tag…** → enter name + pick color → confirm |
| Enter a tag folder | Click the tag flag in the Pinned tab |
| Edit a tag | Right-click the tag flag → **Edit…** → change name or color |
| Delete a tag | Right-click the tag flag → **Delete Tag** → choose to move items to Untagged or delete them |
| Clear a tag and its items | Inside a tag detail view → **Clear** button → confirm |

### Settings

Open the popup → **Settings** button:

| Setting | Description |
|---------|-------------|
| **Show in Menu Bar** | Toggles the clipboard icon in the menu bar |
| **Follow Cursor** | When on, popup opens near the cursor; when off, it reopens at its last position |
| **History Size** | Maximum items kept (10 / 15 / 20 / 25 / 50) |
| **Global Shortcut** | Click **Record**, press your desired modifier+key combo — saved automatically |
| **Reset to Defaults** | Restores all settings to factory values |
| **Export backup** ⬆ | Save everything to a `.clipboxbackup` file (settings, tags, pinned, history, Recently Deleted) |
| **Import backup** ⬇ | Restore from a `.clipboxbackup` file — confirmation required, replaces all current data |

**Auto-start on login (optional)**

System Settings → General → Login Items → **+** → select `ClipBox.app`.

---

## How It Works

**Clipboard monitoring** — A `Timer` fires every 0.5 s and checks `NSPasteboard.changeCount`. When the count changes, ClipBox reads the new content (image first, text fallback) and prepends it to history. Duplicates bubble to the top instead of creating a second entry.

**Image handling** — Images are resized to a maximum of 1024 px on the longest edge before being stored. They are saved as PNG files in `~/Library/Application Support/ClipBox/images/` and reloaded on launch.

**Tags** — Tags are stored as JSON in UserDefaults (`com.clipbox.tags`). Each pinned item carries a `tagID` that links it to a tag. Tag operations (create, edit, delete, assign) update both the tag list and the affected items atomically.

**Pinned items** — Stored in a separate persistent list, independent of the history limit. Capped at 100 entries; attempts past that surface a `clipBoxPinLimitReached` notification so the popup can ask the user to unpin first. A private pin records a user-supplied description and an `isHidden` flag; real content is preserved and pasted normally — the masking is purely visual. The number of bullet dots scales proportionally with the actual text length so the row gives a size hint without revealing content.

**Recently Deleted** — Every delete or clear operation performs a soft-delete: items are moved to `deletedItems` with a `deletedAt` timestamp and a snapshot of their tag name/color. On launch and whenever the view opens, items older than 7 days are pruned automatically. The list is also capped at 200 entries — any overflow is permanently dropped FIFO. Recovering an item restores it to its original list (history or pinned); if the original tag no longer exists, it is recreated from the snapshot so the item lands back in its original folder. All three arrays (history, pinned, deleted) are persisted independently and share the same image file pool — orphaned image files are pruned after any operation that can remove items.

**Backup format** — Export produces a `.clipboxbackup` file: a 4-byte magic header (`CBB\x01`) followed by an LZFSE-compressed JSON document containing settings, tags, pinned items, history, and Recently Deleted. Images are embedded as base64 PNG strings inside the JSON, then compressed end-to-end so the file is typically 5–10× smaller than the raw payload. Import validates header → decompression → JSON → version (rejects anything newer than the current build) before any live state is touched, so a malformed file can never corrupt the running app. Encode and decode both run on a background queue while the UI shows a spinner.

**Global hotkey** — `HotkeyManager` installs a `CGEventTap` at the session level, seeing keypresses before any app. The configured shortcut is saved as JSON in UserDefaults and restored on launch. Only the exact modifier combination matches — **⌘V** won't accidentally trigger a **⌘⇧V** shortcut.

**Menu bar icon** — `StatusBarController` creates an `NSStatusItem` when enabled and subscribes to history and pinned item changes via Combine. The icon updates (filled vs. outline) with a 0.1 s debounce to avoid redundant redraws.

**Popup panel** — `PopupWindow` uses a custom `KeyablePanel` (`NSPanel` subclass) with `.nonactivatingPanel` so it never steals focus, and `canBecomeKey = true` so it receives keyboard input directly — including Escape, which Apple blocks in global event monitors.

**Paste sequence** — Close popup → wait 80 ms → re-activate previous app → wait 120 ms → write to `NSPasteboard` → send `CGEvent` ⌘V. The delays give macOS time to complete the app switch before the paste lands.

---

## Troubleshooting

**Popup doesn't open on the global shortcut**
→ Grant Accessibility permission: System Settings → Privacy & Security → Accessibility → enable ClipBox.

**Paste lands in the wrong app**
→ Another app may be intercepting your shortcut. Try recording a different combo in Settings.

**History is empty on first launch**
→ Normal — ClipBox only records copies made after it starts. Copy something and try again.

**Images not appearing**
→ Some apps copy images in proprietary formats. Standard PNG, TIFF, JPEG, and HEIC copies are supported.

---

## Project Structure

```
ClipBox/
├── App/
│   ├── ClipBoxApp.swift            # @main entry point
│   ├── AppDelegate.swift           # Wires all components on launch
│   └── StatusBarController.swift   # Menu-bar icon; dynamic fill/empty state
├── Clipboard/
│   ├── ClipboardItem.swift         # Data model: content, pin metadata, tagID
│   ├── ClipBoxTag.swift            # Tag model: id, name, colorHex; 10-color palette
│   └── ClipboardManager.swift      # History, pinned items, tags, backup, persistence, paste
├── Hotkey/
│   └── HotkeyManager.swift         # CGEventTap global hotkey; in-memory shortcut cache
├── Settings/
│   └── Shortcut.swift              # Codable model for the configured key combo
└── UI/
    ├── PopupWindow.swift           # NSPanel lifecycle and positioning
    ├── PopupView.swift             # SwiftUI: tabs, tag navigation, search, keyboard handling
    ├── ClipboardRowView.swift      # Row view; PinOptionsPopover; TagAssignPopover
    └── SettingsView.swift          # Settings slide-over (incl. Export/Import)
```

Info.plist keys (`LSUIElement = YES`, app category, etc.) are auto-generated from `INFOPLIST_KEY_*` build settings in `project.pbxproj` — no standalone Info.plist file in the repo.

---

## Building from Source

```bash
git clone https://github.com/your-username/ClipBox.git
cd ClipBox
open ClipBox.xcodeproj
```

Select the **ClipBox** target → **Signing & Capabilities** → set your **Team**. Press **⌘R** to build and run. Requires Xcode 16+ and macOS 12+.

---

## License

MIT License. See `LICENSE` for details.
