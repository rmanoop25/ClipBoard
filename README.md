# ClipBoard

A lightweight macOS menu bar clipboard history manager. Single-file Swift app, no dependencies, under 200KB.

## Features

- **Menu bar app** -- lives in the top bar, no Dock icon
- **Configurable history size** -- keep 5 to 50 clipboard items (default 10)
- **Quick paste popup** (`Cmd+Shift+V`) -- floating suggestion panel at your cursor, auto-pastes into the active text field
- **Pin items** -- pinned items stay at the top and are never removed
- **Keyboard driven** -- navigate, select, and pin without touching the mouse
- **Settings window** (`Cmd+,`) -- configure history size, shortcut, launch at login
- **Custom shortcut** -- re-record the quick paste hotkey to any combo you prefer
- **Launch at login** -- optional, toggle in settings
- **Persists pins** -- pinned items survive app restarts
- **Deduplication** -- copying the same text moves it to the top instead of creating duplicates
- **Custom app icon** -- programmatically generated, no external assets
- **Native macOS UI** -- vibrancy, SF Symbols, system colors, dark mode support

## Install

```bash
./build.sh
cp -r ClipBoard.app /Applications/
```

Or build manually:

```bash
swiftc main.swift -o ClipBoard.app/Contents/MacOS/ClipBoard -framework Cocoa -framework Carbon -O
open ClipBoard.app
```

## Requirements

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)

### Permissions

ClipBoard requires **Accessibility** permission to simulate `Cmd+V` paste into the active app. Without it, selecting an item will copy it to the clipboard but not auto-paste.

1. On first launch, macOS will prompt you to grant Accessibility access
2. If the prompt doesn't appear, or auto-paste isn't working, go to **System Settings → Privacy & Security → Accessibility** and add ClipBoard
3. Make sure the toggle next to ClipBoard is **ON**

> **After rebuilding:** Each build produces a new unsigned binary, which invalidates the previous Accessibility grant. You must **remove and re-add** ClipBoard in the Accessibility list after every rebuild, or toggle it off and on again.

## Usage

### Menu bar dropdown

Click the clipboard icon in the menu bar to see your history. Click any item to copy it back to the clipboard. Hover an item to reveal a submenu for pinning/unpinning.

### Quick paste popup

Press `Cmd+Shift+V` anywhere to open a floating suggestion panel at your cursor.

| Key | Action |
|---|---|
| `Up` / `Down` | Navigate items |
| `Enter` | Paste selected item |
| `Cmd+1` -- `Cmd+0` | Quick-paste by number |
| `Cmd+P` | Toggle pin on selected item |
| `Escape` | Dismiss |

Selecting an item copies it to the clipboard, closes the popup, switches back to the previous app, and simulates `Cmd+V` to paste.

### Pinning

Pin any item to keep it permanently at the top of the list. Pinned items are never evicted by new copies and are not removed by "Clear Unpinned". Pins persist across app restarts.

- **Popup**: select an item and press `Cmd+P`
- **Menu bar**: hover an item > submenu > Pin/Unpin

### Settings

Open with `Cmd+,` from the menu bar dropdown or click "Settings..." in the menu.

- **History size** -- adjust from 5 to 50 items
- **Launch at login** -- start ClipBoard when you log in
- **Enable popup** -- toggle the quick paste popup on/off
- **Quick paste shortcut** -- click the shortcut button and press a new key combo to re-bind

## Project structure

```
ClipBoard/
  main.swift              Single-file source
  generate_icon.swift     Programmatic app icon generator
  build.sh                Build script (compiles + generates icon)
  ClipBoard.app/          Ready-to-run app bundle
    Contents/
      Info.plist           App metadata (LSUIElement, bundle ID, icon)
      MacOS/ClipBoard      Compiled binary
      Resources/AppIcon.icns  App icon
```

## How it works

- **Clipboard monitoring**: a 0.5s `Timer` polls `NSPasteboard.general.changeCount` for changes
- **Global hotkey**: Carbon `RegisterEventHotKey` registers `Cmd+Shift+V` system-wide
- **Suggestion panel**: borderless `NSPanel` with `NSVisualEffectView` (.popover material) and `NSTableView`
- **Auto-paste**: uses AppleScript `System Events` keystroke (with CGEvent fallback) to simulate `Cmd+V` in the previously focused app. Waits for modifier keys to be released before pasting to avoid hotkey interference
- **Pin persistence**: pinned item contents saved as JSON array to `~/Library/Application Support/ClipBoard/pinned.json`
- **Settings**: stored in `UserDefaults` (standard macOS preferences system)
- **Launch at login**: uses `SMAppService` (macOS 13+)
- **App icon**: generated programmatically by `generate_icon.swift` using `NSBitmapImageRep`, converted to `.icns` via `iconutil`

## Data storage

- `~/Library/Application Support/ClipBoard/pinned.json` -- pinned items (plain text JSON array)
- No other data is written to disk. Unpinned history is in-memory only.

## License

MIT
