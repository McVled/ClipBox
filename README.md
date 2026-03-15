# ClipBox

A lightweight macOS clipboard history manager that lives entirely in the background — no Dock icon. Press a keyboard shortcut to summon a floating popup near your cursor, browse your last 15 copied items with the arrow keys, and paste any of them back with Enter. A small icon in the menu bar lets you clear history and quit the app.

---

## Features

- **Global shortcut** — Press **⌘⇧V** from any app to open the popup.
- **15-item history** — The last 15 unique texts you copied are remembered automatically.
- **Keyboard navigation** — Use **↑ / ↓** to move through the list, **Enter** to paste, **Esc** to dismiss.
- **Mouse support** — Click any row to paste it directly.
- **Smart positioning** — The popup appears next to your cursor and automatically adjusts to stay within the screen bounds.
- **Instant paste** — Selecting an item writes it to the clipboard and triggers ⌘V in your previous app, so it lands exactly where your cursor was.
- **Adaptive appearance** — Follows the system Light/Dark mode via `.regularMaterial`.
- **Menu bar icon** — Click the clipboard icon in the menu bar to open ClipBox, clear history, or quit.
- **Zero Dock footprint** — No Dock icon, no app switcher clutter. Runs silently in the background.

---

## Requirements

| | |
|---|---|
| **macOS** | 15.7 Sequoia or later |
| **Xcode** | 14 or later |
| **Swift** | 5.7 or later |
| **Permissions** | Accessibility (required for global hotkey and simulated paste) |

---

## Getting Started

### Installing from DMG (recommended for end users)

1. Download the latest `ClipBox.dmg` from the [Releases](../../releases) page.
2. Open the DMG file — a window appears with the ClipBox icon and an Applications shortcut.
3. Drag **ClipBox** onto the **Applications** folder.
4. Eject the DMG and open ClipBox from **Applications** or **Spotlight** (⌘Space → "ClipBox").

**First launch — Gatekeeper warning**

Because ClipBox is not notarized through the Apple Developer Program, macOS will block it on first open with *"ClipBox cannot be opened because the developer cannot be verified."*

To fix this, open **Terminal** (Spotlight → "Terminal") and run:

```bash
xattr -cr /Applications/ClipBox.app
```

Then open ClipBox normally from Applications or Spotlight. This is a one-time step.

**First launch — Accessibility permission**

ClipBox will prompt you to grant Accessibility access. This is required for:
- The global ⌘⇧V hotkey (CGEventTap needs Accessibility to intercept keys system-wide)
- The simulated ⌘V paste into other apps

Click **Open System Settings** in the prompt, then toggle **ClipBox** on under Privacy & Security → Accessibility.

### Quitting ClipBox

ClipBox has no Dock icon, but it lives in your **menu bar** (top-right corner). Click the clipboard icon ( 󰅌 ) to access:

| Action | Description |
|--------|-------------|
| **Open ClipBox** | Shows the popup (same as ⌘⇧V) |
| **Clipboard history: N items** | How many items are currently stored |
| **Clear History** | Wipes all stored clipboard entries |
| **Quit ClipBox** | Fully exits the app |

### Auto-start on login (optional)

To have ClipBox start automatically when you log in:
1. Open **System Settings** → **General** → **Login Items**
2. Click **+** and select `ClipBox.app` from your Applications folder

---

## Project Structure

```
ClipBox/
├── App/
│   ├── ClipBoxApp.swift        # @main entry point, SwiftUI App scene
│   └── AppDelegate.swift       # Wires ClipboardManager + HotkeyManager on launch
│
├── Clipboard/
│   ├── ClipboardItem.swift     # Data model: text + timestamp + unique ID
│   └── ClipboardManager.swift  # Polls NSPasteboard, stores history, handles paste
│
├── Hotkey/
│   └── HotkeyManager.swift     # CGEventTap-based global ⌘⇧V shortcut
│
├── UI/
│   ├── PopupWindow.swift       # NSPanel management, positioning, key forwarding
│   ├── PopupView.swift         # SwiftUI list view with keyboard navigation
│   └── ClipboardRowView.swift  # Single row: index badge + text preview + timestamp
│
├── Utils/
│   └── CursorPosition.swift    # Thin wrapper around NSEvent.mouseLocation
│
└── Resources/
    └── Info.plist              # LSUIElement = YES (hides from Dock/menu bar)
```

### Building from source (developers)

```bash
git clone https://github.com/your-username/ClipBox.git
cd ClipBox
open ClipBox.xcodeproj
```

In Xcode, select the **ClipBox** target → **Info** tab and confirm:

| Key | Type | Value |
|-----|------|-------|
| `Application is agent (UIElement)` | Boolean | `YES` |

Press **⌘R** to build and run. The same Accessibility prompt will appear on first launch.

### Clipboard Monitoring

`ClipboardManager` runs a `Timer` that fires every **0.5 seconds** and reads `NSPasteboard.general.changeCount`. macOS increments this counter each time the clipboard is written to. When the count changes, we read the new string and prepend it to the `history` array (max 15 items, duplicates bubble to the top).

### Global Hotkey

`HotkeyManager` installs a `CGEventTap` at the session level. This is a low-level hook into the HID event stream that sees keypresses *before* any app does. When **⌘⇧V** is detected, the event is consumed (not forwarded) and the popup is toggled. This requires Accessibility permission.

### The Popup Panel

`PopupWindow` creates a `KeyablePanel` — a custom `NSPanel` subclass with:
- `.borderless` + `.nonactivatingPanel` style: the panel appears without stealing focus from the user's current app.
- `canBecomeKey = true`: overriding this allows the panel to receive keyboard input directly via `keyDown`, including **Escape** (which is blocked by Apple in global event monitors).
- `level = .floating`: always on top of regular windows.

Key presses are forwarded to SwiftUI's `PopupView` via `NotificationCenter` (`.clipBoxKeyDown`), since SwiftUI's native keyboard handling requires a focused window.

### Paste Sequence

When the user selects an item, the following happens in order:

```
1. Popup closes (orderOut)
2. Wait 80ms  → re-activate the previous app (NSRunningApplication.activate)
3. Wait 120ms → write selected text to NSPasteboard
               → send CGEvent ⌘V to the HID event tap
```

The delays are necessary because `activate()` is asynchronous — macOS needs a moment to complete the app switch before the paste event is delivered.

---

## Troubleshooting

**Popup doesn't open when I press ⌘⇧V**
→ Make sure ClipBox has Accessibility permission: *System Settings → Privacy & Security → Accessibility*.

**Text pastes but lands in the wrong app**
→ This can happen if another app also intercepts ⌘⇧V. Check for conflicts with other clipboard managers or productivity tools.

**History is empty on first launch**
→ Normal — ClipBox only records copies made *after* it starts running. Copy something and press ⌘⇧V again.

**Escape doesn't close the popup**
→ Ensure you're running the latest build. Earlier versions used `addGlobalMonitorForEvents` for keys, which blocks Escape. The fix uses `KeyablePanel.keyDown` directly.

---

## Architecture Decisions

| Decision | Reason |
|----------|--------|
| `CGEventTap` for hotkey | Only way to *consume* a keypress globally (prevent it reaching other apps) |
| `NSPanel` subclass for key input | `nonactivatingPanel` prevents focus theft; `canBecomeKey = true` enables direct `keyDown` including Esc |
| `NotificationCenter` for key forwarding | SwiftUI views in a non-activating panel can't receive `onKeyPress`; notifications bridge the gap |
| Polling `NSPasteboard` vs. change notification | macOS has no public push API for clipboard changes; 0.5s polling is the standard approach |
| `NSRunningApplication.activate` before paste | `CGEvent` posts to whichever app is active; we must restore the previous app first |

---

## License

MIT License. See `LICENSE` for details.