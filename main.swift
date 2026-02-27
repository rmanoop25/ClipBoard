import Cocoa
import Carbon.HIToolbox

// MARK: - Global reference for Carbon hotkey callback
private var globalAppDelegate: AppDelegate?

// MARK: - Clipboard Item Model

class ClipboardItem: Equatable {
    let content: String
    let timestamp: Date
    var isPinned: Bool

    init(content: String, timestamp: Date, isPinned: Bool = false) {
        self.content = content
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        return lhs.content == rhs.content && lhs.isPinned == rhs.isPinned
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 80 {
            return String(singleLine.prefix(77)) + "..."
        }
        return singleLine
    }

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}

// MARK: - Clipboard Monitor

class ClipboardMonitor {
    private var lastChangeCount: Int
    private(set) var history: [ClipboardItem] = []
    private let maxUnpinnedItems = 10
    private var timer: Timer?

    private var pinnedStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClipBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pinned.json")
    }

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        loadPinnedItems()
    }

    // MARK: - Persistence for pinned items

    private func loadPinnedItems() {
        guard let data = try? Data(contentsOf: pinnedStoreURL),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return }
        for content in strings {
            let item = ClipboardItem(content: content, timestamp: Date(), isPinned: true)
            history.append(item)
        }
    }

    private func savePinnedItems() {
        let pinned = history.filter { $0.isPinned }.map { $0.content }
        if let data = try? JSONEncoder().encode(pinned) {
            try? data.write(to: pinnedStoreURL)
        }
    }

    // MARK: - Sorted list: pinned first, then unpinned by recency

    private func sortHistory() {
        let pinned = history.filter { $0.isPinned }
        let unpinned = history.filter { !$0.isPinned }
        history = pinned + unpinned
    }

    // MARK: - Pin / Unpin

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        sortHistory()
        trimUnpinned()
        savePinnedItems()
    }

    private func trimUnpinned() {
        let pinned = history.filter { $0.isPinned }
        var unpinned = history.filter { !$0.isPinned }
        if unpinned.count > maxUnpinnedItems {
            unpinned = Array(unpinned.prefix(maxUnpinnedItems))
        }
        history = pinned + unpinned
    }

    // MARK: - Monitoring

    func start(onChange: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentCount = NSPasteboard.general.changeCount
            if currentCount != self.lastChangeCount {
                self.lastChangeCount = currentCount
                if let content = NSPasteboard.general.string(forType: .string),
                   !content.isEmpty {
                    // Skip if newest unpinned already matches
                    let topUnpinned = self.history.first(where: { !$0.isPinned })
                    if topUnpinned?.content == content { return }
                    // Skip if it matches a pinned item
                    if self.history.contains(where: { $0.isPinned && $0.content == content }) { return }

                    let item = ClipboardItem(content: content, timestamp: Date())
                    // Remove older unpinned duplicate
                    self.history.removeAll { !$0.isPinned && $0.content == content }
                    // Insert after pinned items
                    let firstUnpinnedIndex = self.history.firstIndex(where: { !$0.isPinned }) ?? self.history.endIndex
                    self.history.insert(item, at: firstUnpinnedIndex)
                    self.trimUnpinned()
                    onChange()
                }
            }
        }
    }

    func copyToClipboard(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.content, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func clearHistory() {
        history.removeAll { !$0.isPinned }
    }
}

// MARK: - Suggestion Panel (borderless, key-accepting)

class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Suggestion Row View (custom selection highlight)

class SuggestionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let rect = bounds.insetBy(dx: 6, dy: 1)
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }
}

// MARK: - Suggestion Window Controller

class SuggestionWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No clipboard items yet")
    private var items: [ClipboardItem] = []
    private var localMonitor: Any?

    var onSelect: ((ClipboardItem) -> Void)?
    var onDismiss: (() -> Void)?
    var onTogglePin: ((ClipboardItem) -> Void)?

    private let rowHeight: CGFloat = 34
    private let panelWidth: CGFloat = 460

    init() {
        let panel = SuggestionPanel(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .utilityWindow

        super.init(window: panel)
        setupViews()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        guard let panel = window else { return }

        // Visual effect background
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        panel.contentView = visualEffect

        // Title
        titleLabel.stringValue = "  Clipboard History"
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(titleLabel)

        // Shortcut hint in title area
        let shortcutLabel = NSTextField(labelWithString: "⌘⇧V")
        shortcutLabel.font = .systemFont(ofSize: 10)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(shortcutLabel)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(separator)

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = panelWidth - 16
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = rowHeight
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.focusRingType = .none
        tableView.action = #selector(tableRowClicked)
        tableView.target = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(scrollView)

        // Empty label
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        visualEffect.addSubview(emptyLabel)

        // Bottom hint
        hintLabel.stringValue = "↑↓ Navigate   ⏎ Paste   ⌘P Pin   ⎋ Close"
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hintLabel)

        // Bottom separator
        let bottomSep = NSBox()
        bottomSep.boxType = .separator
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(bottomSep)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 8),

            shortcutLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -14),

            separator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 8),
            separator.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),

            emptyLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 20),
            emptyLabel.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),

            bottomSep.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            bottomSep.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 8),
            bottomSep.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -8),

            hintLabel.topAnchor.constraint(equalTo: bottomSep.bottomAnchor, constant: 6),
            hintLabel.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -8),
        ])
    }

    func updateItems(_ newItems: [ClipboardItem]) {
        items = newItems
        let isEmpty = items.isEmpty
        scrollView.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty
        tableView.reloadData()
        resizePanel()
        if !isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    private func resizePanel() {
        guard let panel = window else { return }
        let visibleRows = min(items.count, 10)
        let tableHeight = max(CGFloat(visibleRows) * (rowHeight + 2), 40)
        let totalHeight: CGFloat = 10 + 18 + 8 + 1 + 4 + tableHeight + 4 + 1 + 6 + 14 + 8
        let origin = panel.frame.origin
        let newFrame = NSRect(
            x: origin.x,
            y: origin.y + panel.frame.height - totalHeight,
            width: panelWidth,
            height: totalHeight
        )
        panel.setFrame(newFrame, display: true)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        startKeyMonitor()
    }

    override func close() {
        stopKeyMonitor()
        super.close()
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isVisible == true else { return event }
            if self.handleKeyEvent(event) {
                return nil
            }
            return event
        }
    }

    private func stopKeyMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape → dismiss
        if keyCode == 53 {
            onDismiss?()
            return true
        }

        // Enter/Return → select current
        if keyCode == 36 || keyCode == 76 {
            selectCurrent()
            return true
        }

        // Arrow Down
        if keyCode == 125 {
            moveSelection(by: 1)
            return true
        }

        // Arrow Up
        if keyCode == 126 {
            moveSelection(by: -1)
            return true
        }

        // Cmd+P → toggle pin on selected item
        if flags.contains(.command), let chars = event.charactersIgnoringModifiers, chars == "p" {
            let row = tableView.selectedRow
            if row >= 0 && row < items.count {
                onTogglePin?(items[row])
            }
            return true
        }

        // Cmd+1 through Cmd+9 and Cmd+0
        if flags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers {
                if let digit = chars.first, digit >= "1" && digit <= "9" {
                    let index = Int(String(digit))! - 1
                    if index < items.count {
                        onSelect?(items[index])
                    }
                    return true
                }
                if chars == "0" && items.count >= 10 {
                    onSelect?(items[9])
                    return true
                }
            }
        }

        return false
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        var newRow = tableView.selectedRow + delta
        if newRow < 0 { newRow = items.count - 1 }
        if newRow >= items.count { newRow = 0 }
        tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(newRow)
    }

    private func selectCurrent() {
        let row = tableView.selectedRow
        if row >= 0 && row < items.count {
            onSelect?(items[row])
        }
    }

    @objc private func tableRowClicked() {
        let row = tableView.clickedRow
        if row >= 0 && row < items.count {
            onSelect?(items[row])
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("ClipCell")
        let cell: NSView
        if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) {
            cell = reused
        } else {
            cell = makeCellView(identifier: cellId)
        }
        configureCellView(cell, row: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return SuggestionRowView()
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSView {
        let view = NSView()
        view.identifier = identifier

        let indexLabel = NSTextField(labelWithString: "")
        indexLabel.tag = 100
        indexLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        indexLabel.textColor = .tertiaryLabelColor
        indexLabel.alignment = .center
        indexLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(indexLabel)

        let pinIcon = NSImageView()
        pinIcon.tag = 200
        pinIcon.imageScaling = .scaleProportionallyDown
        pinIcon.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pinIcon)

        let previewLabel = NSTextField(labelWithString: "")
        previewLabel.tag = 101
        previewLabel.font = .systemFont(ofSize: 13)
        previewLabel.textColor = .labelColor
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewLabel)

        let timeLabel = NSTextField(labelWithString: "")
        timeLabel.tag = 102
        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            indexLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            indexLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            indexLabel.widthAnchor.constraint(equalToConstant: 28),

            pinIcon.leadingAnchor.constraint(equalTo: indexLabel.trailingAnchor, constant: 0),
            pinIcon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 14),
            pinIcon.heightAnchor.constraint(equalToConstant: 14),

            previewLabel.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 4),
            previewLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            timeLabel.widthAnchor.constraint(equalToConstant: 52),
        ])

        return view
    }

    private func configureCellView(_ view: NSView, row: Int) {
        guard row < items.count else { return }
        let item = items[row]

        if let indexLabel = view.viewWithTag(100) as? NSTextField {
            if row < 9 {
                indexLabel.stringValue = "⌘\(row + 1)"
            } else if row == 9 {
                indexLabel.stringValue = "⌘0"
            } else {
                indexLabel.stringValue = ""
            }
        }
        if let pinIcon = view.viewWithTag(200) as? NSImageView {
            if item.isPinned {
                let img = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                img?.isTemplate = true
                pinIcon.image = img
                pinIcon.contentTintColor = .secondaryLabelColor
            } else {
                pinIcon.image = nil
            }
        }
        if let previewLabel = view.viewWithTag(101) as? NSTextField {
            previewLabel.stringValue = item.preview
        }
        if let timeLabel = view.viewWithTag(102) as? NSTextField {
            timeLabel.stringValue = item.timeAgo
        }
    }
}

// MARK: - Carbon Hotkey Event Handler (C-compatible)

private func carbonHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        globalAppDelegate?.toggleSuggestionPanel()
    }
    return noErr
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = ClipboardMonitor()
    private var suggestionWC: SuggestionWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        globalAppDelegate = self

        // Status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
        }

        rebuildMenu()

        monitor.start { [weak self] in
            DispatchQueue.main.async {
                self?.rebuildMenu()
            }
        }

        registerGlobalHotKey()
        checkAccessibilityPermission()
    }

    // MARK: - Accessibility Check

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSLog("ClipBoard: Accessibility permission needed for Cmd+Shift+V paste simulation")
        }
    }

    // MARK: - Global Hotkey Registration (Carbon)

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerUPP: EventHandlerUPP = carbonHotKeyHandler
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            &eventType,
            nil,
            nil
        )

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x434C4950), // "CLIP"
            id: UInt32(1)
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    // MARK: - Suggestion Panel Toggle

    func toggleSuggestionPanel() {
        if let wc = suggestionWC, wc.window?.isVisible == true {
            dismissSuggestionPanel()
        } else {
            showSuggestionPanel()
        }
    }

    private func showSuggestionPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication

        if suggestionWC == nil {
            suggestionWC = SuggestionWindowController()
        }

        guard let wc = suggestionWC, let panel = wc.window else { return }

        wc.onSelect = { [weak self] item in
            self?.handleSuggestionSelect(item)
        }
        wc.onDismiss = { [weak self] in
            self?.dismissSuggestionPanel()
        }
        wc.onTogglePin = { [weak self] item in
            guard let self = self else { return }
            self.monitor.togglePin(item)
            wc.updateItems(self.monitor.history)
            self.rebuildMenu()
        }
        wc.updateItems(monitor.history)

        // Position at mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let panelSize = panel.frame.size
        panel.setFrameTopLeftPoint(NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y + 10
        ))

        // Ensure panel stays on screen
        if let screen = NSScreen.main {
            var frame = panel.frame
            let screenFrame = screen.visibleFrame
            if frame.minX < screenFrame.minX { frame.origin.x = screenFrame.minX + 4 }
            if frame.maxX > screenFrame.maxX { frame.origin.x = screenFrame.maxX - frame.width - 4 }
            if frame.minY < screenFrame.minY { frame.origin.y = screenFrame.minY + 4 }
            if frame.maxY > screenFrame.maxY { frame.origin.y = screenFrame.maxY - frame.height - 4 }
            panel.setFrame(frame, display: true)
        }

        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissSuggestionPanel()
        }
    }

    private func dismissSuggestionPanel() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        suggestionWC?.close()

        if let prev = previousApp {
            prev.activate()
            previousApp = nil
        }
    }

    private func handleSuggestionSelect(_ item: ClipboardItem) {
        monitor.copyToClipboard(item)
        dismissSuggestionPanel()
        rebuildMenu()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.simulatePaste()
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Menu Bar Dropdown

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let titleItem = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        titleItem.attributedTitle = NSAttributedString(
            string: "Clipboard History",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        )
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())

        let pinnedItems = monitor.history.filter { $0.isPinned }
        let unpinnedItems = monitor.history.filter { !$0.isPinned }

        if monitor.history.isEmpty {
            let emptyItem = NSMenuItem(title: "No items yet — copy something!", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, item) in monitor.history.enumerated() {
                if !pinnedItems.isEmpty && !unpinnedItems.isEmpty && item === unpinnedItems.first {
                    menu.addItem(NSMenuItem.separator())
                }

                let keyEquiv = index < 9 ? "\(index + 1)" : (index == 9 ? "0" : "")
                let menuItem = NSMenuItem(
                    title: "",
                    action: #selector(clipboardItemClicked(_:)),
                    keyEquivalent: keyEquiv
                )
                if !keyEquiv.isEmpty {
                    menuItem.keyEquivalentModifierMask = .command
                }

                let previewStr = item.preview
                let timeStr = "  \(item.timeAgo)"
                let fullStr = previewStr + timeStr
                let attributed = NSMutableAttributedString(string: fullStr)
                attributed.addAttributes(
                    [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)],
                    range: NSRange(location: 0, length: previewStr.count)
                )
                attributed.addAttributes(
                    [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor],
                    range: NSRange(location: previewStr.count, length: timeStr.count)
                )
                menuItem.attributedTitle = attributed
                menuItem.tag = index
                menuItem.target = self

                if item.isPinned {
                    menuItem.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                    menuItem.image?.size = NSSize(width: 12, height: 12)
                    menuItem.image?.isTemplate = true
                }

                let subMenu = NSMenu()
                let pinToggle = NSMenuItem(
                    title: item.isPinned ? "Unpin" : "Pin",
                    action: #selector(togglePinFromMenu(_:)),
                    keyEquivalent: ""
                )
                pinToggle.tag = index
                pinToggle.target = self
                subMenu.addItem(pinToggle)
                menuItem.submenu = subMenu

                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let hintItem = NSMenuItem(title: "Quick Paste: ⌘⇧V", action: nil, keyEquivalent: "")
        hintItem.isEnabled = false
        menu.addItem(hintItem)

        menu.addItem(NSMenuItem.separator())

        let clearItem = NSMenuItem(title: "Clear Unpinned", action: #selector(clearHistory), keyEquivalent: "K")
        clearItem.keyEquivalentModifierMask = [.command, .shift]
        clearItem.target = self
        clearItem.isEnabled = !unpinnedItems.isEmpty
        menu.addItem(clearItem)

        let quitItem = NSMenuItem(title: "Quit ClipBoard", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func clipboardItemClicked(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < monitor.history.count else { return }
        monitor.copyToClipboard(monitor.history[index])
        rebuildMenu()
    }

    @objc private func togglePinFromMenu(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < monitor.history.count else { return }
        monitor.togglePin(monitor.history[index])
        rebuildMenu()
    }

    @objc private func clearHistory() {
        monitor.clearHistory()
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
