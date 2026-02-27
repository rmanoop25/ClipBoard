# ClipBoard

A lightweight macOS menu bar clipboard history manager. Single-file Swift app, no dependencies, under 200KB.

## Features

- **Menu bar app** -- lives in the top bar, no Dock icon
- **Last 10 clipboard items** -- automatically captures text copies
- **Quick paste popup** (`Cmd+Shift+V`) -- floating suggestion panel at your cursor, auto-pastes into the active text field
- **Pin items** -- pinned items stay at the top and are never removed
- **Keyboard driven** -- navigate, select, and pin without touching the mouse
- **Persists pins** -- pinned items survive app restarts
- **Deduplication** -- copying the same text moves it to the top instead of creating duplicates
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
- **Accessibility permission** -- required for the `Cmd+Shift+V` auto-paste feature. macOS will prompt on first launch. Grant it in System Settings > Privacy & Security > Accessibility.

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

## Project structure

```
ClipBoard/
  main.swift              Single-file source (~860 lines)
  build.sh                Build script
  ClipBoard.app/          Ready-to-run app bundle
    Contents/
      Info.plist           App metadata (LSUIElement, bundle ID)
      MacOS/ClipBoard      Compiled binary
```

## How it works

- **Clipboard monitoring**: a 0.5s `Timer` polls `NSPasteboard.general.changeCount` for changes
- **Global hotkey**: Carbon `RegisterEventHotKey` registers `Cmd+Shift+V` system-wide
- **Suggestion panel**: borderless `NSPanel` with `NSVisualEffectView` (.popover material) and `NSTableView`
- **Auto-paste**: `CGEvent` posts a synthetic `Cmd+V` keystroke to the previously focused app
- **Pin persistence**: pinned item contents saved as JSON array to `~/Library/Application Support/ClipBoard/pinned.json`

## Data storage

- `~/Library/Application Support/ClipBoard/pinned.json` -- pinned items (plain text JSON array)
- No other data is written to disk. Unpinned history is in-memory only.

## License

MIT
