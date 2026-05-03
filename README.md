# ClipBox

A lightweight macOS clipboard history manager that runs entirely in the background. Press **⌘⇧V** (or your custom shortcut) from any app to summon a floating popup near your cursor, browse your clipboard history with text and images, pin important items to keep them forever, organize them with color-coded tags, and paste any of them back with a single keystroke.

---

## Features

### Clipboard History
- **Text & image capture** — Automatically records everything you copy — plain text and images.
- **Persistent history** — Survives app restarts. Text is stored in UserDefaults; images are saved as PNG files in Application Support.
- **Configurable size** — Keep 10, 15, 20, 25, or 50 items. Oldest are removed automatically when the limit is reached.
- **Deduplication** — Copying the same content again moves it to the top instead of creating a duplicate.

### Pinned Items
- **Pin anything permanently** — Pin any item from History to keep it in the Pinned tab forever, unaffected by the history limit or Clear.
- **Public pin** — Item displays and pastes normally.
- **Private pin** — The row shows bullets (••••••••) and a custom label you choose. The real content is still pasted as-is — hiding is purely visual.
- **Tag on pin** — Choose or create a tag directly from the pin dialog.

### Tags
- **Color-coded folders** — Group pinned items into named tags, each with a color chosen from a 10-color palette.
- **Tag detail view** — Click a tag flag to see only its items; navigate back with the back button or **Esc**.
- **Assign after pinning** — Click the flag icon on any pinned row to change or remove its tag at any time.
- **Inline tag creation** — Create a new tag directly from the pin dialog or the flag popover, without leaving your workflow.
- **Edit tags** — Rename or recolor a tag from the detail view header.
- **Delete tags** — Choose to move items to Untagged or delete them together with the tag.
- **Clear tag** — Clearing from inside a tag detail view removes the tag and all its items.

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
| Open from menu bar | Click the clipboard icon in the menu bar |
| Close popup | **Esc** or click outside |
| Move popup | Click and drag |

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
| Clear search entirely | **⌘A** |

### Items

| Action | How |
|--------|-----|
| Pin an item | Hover a history row → click the **pin icon** → choose Public or Private, optionally add a tag → **Pin** |
| Unpin an item | In Pinned tab: click the **✕** icon; in History: pin icon → **Unpin** |
| Delete from history | Hover a row → click the **✕** icon |
| Delete selected item | **⌘⌫** or **⌦** |
| Clear all in active view | **Clear** button in the header → confirm |

### Tags

| Action | How |
|--------|-----|
| Assign a tag while pinning | Pin dialog → Tag section → select chip or click **New tag…** |
| Assign / change a tag after pinning | Click the **flag icon** on any pinned row |
| Create a new tag | Any tag popover → **New tag…** → enter name + pick color → confirm |
| Enter a tag folder | Click the tag flag in the Pinned tab |
| Edit a tag | Inside the tag detail view → **pencil icon** in the header |
| Delete a tag | Inside the tag detail view → **trash icon** → choose to move items or delete them |
| Clear a tag and its items | Inside a tag detail view → **Clear** button |

### Settings

Open the popup → **Settings** button:

| Setting | Description |
|---------|-------------|
| **Show in Menu Bar** | Toggles the clipboard icon in the menu bar |
| **Follow Cursor** | When on, popup opens near the cursor; when off, it reopens at its last position |
| **History Size** | Maximum items kept (10 / 15 / 20 / 25 / 50) |
| **Global Shortcut** | Click **Record**, press your desired modifier+key combo — saved automatically |
| **Reset to Defaults** | Restores all settings to factory values |

**Auto-start on login (optional)**

System Settings → General → Login Items → **+** → select `ClipBox.app`.

---

## How It Works

**Clipboard monitoring** — A `Timer` fires every 0.5 s and checks `NSPasteboard.changeCount`. When the count changes, ClipBox reads the new content (image first, text fallback) and prepends it to history. Duplicates bubble to the top instead of creating a second entry.

**Image handling** — Images are resized to a maximum of 1024 px on the longest edge before being stored. They are saved as PNG files in `~/Library/Application Support/ClipBox/images/` and reloaded on launch.

**Tags** — Tags are stored as JSON in UserDefaults (`com.clipbox.tags`). Each pinned item carries a `tagID` that links it to a tag. Tag operations (create, edit, delete, assign) update both the tag list and the affected items atomically.

**Pinned items** — Stored in a separate persistent list, independent of the history limit. A private pin records a user-supplied description and an `isHidden` flag; real content is preserved and pasted normally — the masking is purely visual.

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
│   └── ClipboardManager.swift      # History, pinned items, tags, persistence, paste
├── Hotkey/
│   └── HotkeyManager.swift         # CGEventTap global hotkey; shortcut recording
├── Settings/
│   └── Shortcut.swift              # Codable model for the configured key combo
├── UI/
│   ├── PopupWindow.swift           # NSPanel lifecycle and positioning
│   ├── PopupView.swift             # SwiftUI: tabs, tag navigation, search, keyboard handling
│   ├── ClipboardRowView.swift      # Row view; PinOptionsPopover; TagAssignPopover
│   ├── SettingsView.swift          # Settings slide-over
│   └── PopoverAnchor.swift         # NSViewRepresentable helper for NSPopover anchoring
├── Utils/
│   └── CursorPosition.swift        # Mouse position helper
└── Resources/
    └── Info.plist                  # LSUIElement = YES (no Dock icon)
```

---

## Building from Source

```bash
git clone https://github.com/your-username/ClipBox.git
cd ClipBox
open ClipBox.xcodeproj
```

Select the **ClipBox** target → **Info** tab → confirm `Application is agent (UIElement)` is set to `YES`. Press **⌘R** to build and run.

---

## License

MIT License. See `LICENSE` for details.
