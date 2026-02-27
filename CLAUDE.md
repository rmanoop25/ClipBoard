# CLAUDE.md

## Project overview

ClipBoard is a native macOS menu bar clipboard history app written in a single Swift file. It has no external dependencies and compiles directly with `swiftc`. The app sits in the system menu bar (no Dock icon) and tracks the last 10 text clipboard items with an option to pin items permanently.

## Build

```bash
swiftc main.swift -o ClipBoard.app/Contents/MacOS/ClipBoard -framework Cocoa -framework Carbon -O
```

Or use the build script:

```bash
./build.sh
```

There is no Xcode project or Swift Package. The app is a single `main.swift` compiled into a macOS `.app` bundle.

## Architecture

Everything lives in `main.swift`. Key components:

- **`ClipboardItem`** (class) -- model holding content, timestamp, and pin state
- **`ClipboardMonitor`** -- polls `NSPasteboard` every 0.5s, manages history list (pinned first, then unpinned by recency), handles pin persistence to `~/Library/Application Support/ClipBoard/pinned.json`
- **`SuggestionPanel`** -- `NSPanel` subclass that overrides `canBecomeKey` for keyboard input
- **`SuggestionRowView`** -- custom `NSTableRowView` with rounded selection highlight
- **`SuggestionWindowController`** -- manages the floating popup: `NSTableView` inside `NSVisualEffectView`, local key event monitor for navigation/selection/pinning
- **`AppDelegate`** -- owns the `NSStatusItem`, `ClipboardMonitor`, suggestion window controller. Registers the global `Cmd+Shift+V` hotkey via Carbon `RegisterEventHotKey`. Handles paste simulation via `CGEvent`.
- **Entry point** -- creates `NSApplication`, sets delegate, calls `app.run()` (no storyboards/nibs)

## Key conventions

- **Single file**: all code stays in `main.swift`. Do not split into multiple files.
- **No dependencies**: only system frameworks (Cocoa, Carbon). No SPM, CocoaPods, or third-party libraries.
- **No Xcode project**: compiled directly with `swiftc`. The `.app` bundle is manually structured.
- **LSUIElement**: set to `true` in `Info.plist` so the app has no Dock icon.
- **SF Symbols**: used for all icons (clipboard, pin.fill). No custom image assets.
- **View tags**: table view cell subviews use integer tags (100=index, 101=preview, 102=time, 200=pin icon) for lookup in `configureCellView`.

## Data

- Pinned items persist to `~/Library/Application Support/ClipBoard/pinned.json` as a JSON string array.
- Unpinned history is in-memory only and lost on quit.
- Max 10 unpinned items. Pinned items have no limit.

## Global hotkey

The `Cmd+Shift+V` hotkey is registered via Carbon's `RegisterEventHotKey` (not `NSEvent.addGlobalMonitorForEvents`) because it works without accessibility permissions for the hotkey itself. The paste simulation (`CGEvent` posting) does require accessibility access.

## Testing

No automated tests. To verify manually:

1. `./build.sh && open ClipBoard.app`
2. Copy several pieces of text -- they should appear in the menu bar dropdown
3. Press `Cmd+Shift+V` -- the suggestion popup should appear at the cursor
4. Arrow keys to navigate, Enter to paste, `Cmd+P` to pin, Escape to dismiss
5. Pin an item, quit and relaunch -- the pinned item should still be there
