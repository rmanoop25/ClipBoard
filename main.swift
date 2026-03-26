import Cocoa
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Global reference for Carbon hotkey callback
private var globalAppDelegate: AppDelegate?

// MARK: - Key Code Display Utility

private let keyCodeNames: [UInt16: String] = [
    0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
    0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
    0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
    0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
    0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
    0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
    0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
    0x25: "L", 0x26: "J", 0x28: "'", 0x29: "K", 0x2A: "\\",
    0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
    0x31: "Space", 0x32: "`",
]

func shortcutDisplayString(keyCode: UInt16, modifiers: UInt32) -> String {
    var s = ""
    if modifiers & UInt32(controlKey) != 0 { s += "\u{2303}" }
    if modifiers & UInt32(optionKey) != 0 { s += "\u{2325}" }
    if modifiers & UInt32(shiftKey) != 0 { s += "\u{21E7}" }
    if modifiers & UInt32(cmdKey) != 0 { s += "\u{2318}" }
    s += keyCodeNames[keyCode] ?? "?"
    return s
}

func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    if flags.contains(.shift) { m |= UInt32(shiftKey) }
    if flags.contains(.option) { m |= UInt32(optionKey) }
    if flags.contains(.control) { m |= UInt32(controlKey) }
    return m
}

// MARK: - Settings

class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "maxItems": 10,
            "hotkeyKeyCode": Int(kVK_ANSI_V),
            "hotkeyModifiers": Int(cmdKey | shiftKey),
            "popupEnabled": true,
            "launchAtLogin": false,
        ])
    }

    var maxItems: Int {
        get { max(5, min(50, defaults.integer(forKey: "maxItems"))) }
        set { defaults.set(newValue, forKey: "maxItems") }
    }

    var hotkeyKeyCode: UInt16 {
        get { UInt16(defaults.integer(forKey: "hotkeyKeyCode")) }
        set { defaults.set(Int(newValue), forKey: "hotkeyKeyCode") }
    }

    var hotkeyModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: "hotkeyModifiers")) }
        set { defaults.set(Int(newValue), forKey: "hotkeyModifiers") }
    }

    var popupEnabled: Bool {
        get { defaults.bool(forKey: "popupEnabled") }
        set { defaults.set(newValue, forKey: "popupEnabled") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set {
            defaults.set(newValue, forKey: "launchAtLogin")
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("ClipBoard: launch at login error: \(error)")
            }
        }
    }

    var hotkeyDisplayString: String {
        shortcutDisplayString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }
}

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
        lhs.content == rhs.content && lhs.isPinned == rhs.isPinned
    }

    var preview: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 80 { return String(singleLine.prefix(77)) + "..." }
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

    private func loadPinnedItems() {
        guard let data = try? Data(contentsOf: pinnedStoreURL),
              let strings = try? JSONDecoder().decode([String].self, from: data) else { return }
        for content in strings {
            history.append(ClipboardItem(content: content, timestamp: Date(), isPinned: true))
        }
    }

    private func savePinnedItems() {
        let pinned = history.filter { $0.isPinned }.map { $0.content }
        if let data = try? JSONEncoder().encode(pinned) {
            try? data.write(to: pinnedStoreURL)
        }
    }

    private func sortHistory() {
        let pinned = history.filter { $0.isPinned }
        let unpinned = history.filter { !$0.isPinned }
        history = pinned + unpinned
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        sortHistory()
        trimUnpinned()
        savePinnedItems()
    }

    func trimUnpinned() {
        let pinned = history.filter { $0.isPinned }
        var unpinned = history.filter { !$0.isPinned }
        let max = Settings.shared.maxItems
        if unpinned.count > max { unpinned = Array(unpinned.prefix(max)) }
        history = pinned + unpinned
    }

    func start(onChange: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let currentCount = NSPasteboard.general.changeCount
            if currentCount != self.lastChangeCount {
                self.lastChangeCount = currentCount
                if let content = NSPasteboard.general.string(forType: .string), !content.isEmpty {
                    let topUnpinned = self.history.first(where: { !$0.isPinned })
                    if topUnpinned?.content == content { return }
                    if self.history.contains(where: { $0.isPinned && $0.content == content }) { return }

                    let item = ClipboardItem(content: content, timestamp: Date())
                    self.history.removeAll { !$0.isPinned && $0.content == content }
                    let idx = self.history.firstIndex(where: { !$0.isPinned }) ?? self.history.endIndex
                    self.history.insert(item, at: idx)
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

// MARK: - Suggestion Panel

class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Suggestion Row View

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
            backing: .buffered, defer: false
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
        let ve = NSVisualEffectView()
        ve.material = .popover
        ve.state = .active
        ve.blendingMode = .behindWindow
        ve.wantsLayer = true
        ve.layer?.cornerRadius = 12
        ve.layer?.masksToBounds = true
        window?.contentView = ve

        let titleLabel = NSTextField(labelWithString: "  Clipboard History")
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(titleLabel)

        let shortcutLabel = NSTextField(labelWithString: Settings.shared.hotkeyDisplayString)
        shortcutLabel.font = .systemFont(ofSize: 10)
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(shortcutLabel)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(sep)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = panelWidth - 16
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self; tableView.delegate = self
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
        ve.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        ve.addSubview(emptyLabel)

        let bottomSep = NSBox(); bottomSep.boxType = .separator
        bottomSep.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(bottomSep)

        hintLabel.stringValue = "\u{2191}\u{2193} Navigate   \u{23CE} Paste   \u{2318}P Pin   \u{238B} Close"
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        ve.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: ve.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: ve.leadingAnchor, constant: 8),
            shortcutLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: ve.trailingAnchor, constant: -14),
            sep.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            sep.leadingAnchor.constraint(equalTo: ve.leadingAnchor, constant: 8),
            sep.trailingAnchor.constraint(equalTo: ve.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: ve.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: ve.trailingAnchor),
            emptyLabel.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 20),
            emptyLabel.centerXAnchor.constraint(equalTo: ve.centerXAnchor),
            bottomSep.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 4),
            bottomSep.leadingAnchor.constraint(equalTo: ve.leadingAnchor, constant: 8),
            bottomSep.trailingAnchor.constraint(equalTo: ve.trailingAnchor, constant: -8),
            hintLabel.topAnchor.constraint(equalTo: bottomSep.bottomAnchor, constant: 6),
            hintLabel.centerXAnchor.constraint(equalTo: ve.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: ve.bottomAnchor, constant: -8),
        ])
    }

    func updateItems(_ newItems: [ClipboardItem]) {
        items = newItems
        scrollView.isHidden = items.isEmpty
        emptyLabel.isHidden = !items.isEmpty
        tableView.reloadData()
        resizePanel()
        if !items.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView.scrollRowToVisible(0)
        }
    }

    private func resizePanel() {
        guard let panel = window else { return }
        let rows = min(items.count, 10)
        let tableH = max(CGFloat(rows) * (rowHeight + 2), 40)
        let totalH: CGFloat = 10 + 18 + 8 + 1 + 4 + tableH + 4 + 1 + 6 + 14 + 8
        let origin = panel.frame.origin
        panel.setFrame(NSRect(x: origin.x, y: origin.y + panel.frame.height - totalH,
                              width: panelWidth, height: totalH), display: true)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        startKeyMonitor()
    }

    override func close() { stopKeyMonitor(); super.close() }

    private func startKeyMonitor() {
        stopKeyMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isVisible == true else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func stopKeyMonitor() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let kc = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if kc == 53 { onDismiss?(); return true }
        if kc == 36 || kc == 76 { selectCurrent(); return true }
        if kc == 125 { moveSelection(by: 1); return true }
        if kc == 126 { moveSelection(by: -1); return true }

        if flags.contains(.command), let chars = event.charactersIgnoringModifiers {
            if chars == "p" {
                let row = tableView.selectedRow
                if row >= 0 && row < items.count { onTogglePin?(items[row]) }
                return true
            }
            if let d = chars.first, d >= "1" && d <= "9" {
                let i = Int(String(d))! - 1
                if i < items.count { onSelect?(items[i]) }
                return true
            }
            if chars == "0" && items.count >= 10 { onSelect?(items[9]); return true }
        }
        return false
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        var r = tableView.selectedRow + delta
        if r < 0 { r = items.count - 1 }
        if r >= items.count { r = 0 }
        tableView.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
        tableView.scrollRowToVisible(r)
    }

    private func selectCurrent() {
        let r = tableView.selectedRow
        if r >= 0 && r < items.count { onSelect?(items[r]) }
    }

    @objc private func tableRowClicked() {
        let r = tableView.clickedRow
        if r >= 0 && r < items.count { onSelect?(items[r]) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellId = NSUserInterfaceItemIdentifier("ClipCell")
        let cell = tableView.makeView(withIdentifier: cellId, owner: nil) ?? makeCellView(identifier: cellId)
        configureCellView(cell, row: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SuggestionRowView()
    }

    private func makeCellView(identifier: NSUserInterfaceItemIdentifier) -> NSView {
        let v = NSView(); v.identifier = identifier

        let idx = NSTextField(labelWithString: "")
        idx.tag = 100; idx.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        idx.textColor = .tertiaryLabelColor; idx.alignment = .center
        idx.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(idx)

        let pin = NSImageView(); pin.tag = 200
        pin.imageScaling = .scaleProportionallyDown
        pin.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(pin)

        let preview = NSTextField(labelWithString: "")
        preview.tag = 101; preview.font = .systemFont(ofSize: 13)
        preview.textColor = .labelColor; preview.lineBreakMode = .byTruncatingTail
        preview.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(preview)

        let time = NSTextField(labelWithString: "")
        time.tag = 102; time.font = .systemFont(ofSize: 10)
        time.textColor = .secondaryLabelColor; time.alignment = .right
        time.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(time)

        NSLayoutConstraint.activate([
            idx.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            idx.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            idx.widthAnchor.constraint(equalToConstant: 28),
            pin.leadingAnchor.constraint(equalTo: idx.trailingAnchor),
            pin.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            pin.widthAnchor.constraint(equalToConstant: 14),
            pin.heightAnchor.constraint(equalToConstant: 14),
            preview.leadingAnchor.constraint(equalTo: pin.trailingAnchor, constant: 4),
            preview.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            preview.trailingAnchor.constraint(equalTo: time.leadingAnchor, constant: -8),
            time.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            time.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            time.widthAnchor.constraint(equalToConstant: 52),
        ])
        return v
    }

    private func configureCellView(_ view: NSView, row: Int) {
        guard row < items.count else { return }
        let item = items[row]
        if let l = view.viewWithTag(100) as? NSTextField {
            l.stringValue = row < 9 ? "\u{2318}\(row+1)" : (row == 9 ? "\u{2318}0" : "")
        }
        if let p = view.viewWithTag(200) as? NSImageView {
            if item.isPinned {
                let img = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                img?.isTemplate = true; p.image = img; p.contentTintColor = .secondaryLabelColor
            } else { p.image = nil }
        }
        if let l = view.viewWithTag(101) as? NSTextField { l.stringValue = item.preview }
        if let l = view.viewWithTag(102) as? NSTextField { l.stringValue = item.timeAgo }
    }
}

// MARK: - Shortcut Recorder Button

class ShortcutRecorderButton: NSButton {
    var keyCode: UInt16 = 0
    var modifiers: UInt32 = 0
    var isRecording = false
    var onChange: ((UInt16, UInt32) -> Void)?
    private var eventMonitor: Any?

    func configure(keyCode: UInt16, modifiers: UInt32) {
        self.keyCode = keyCode; self.modifiers = modifiers
        updateDisplay()
    }

    private func updateDisplay() {
        title = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
        contentTintColor = nil
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording { return }
        isRecording = true
        title = "Type shortcut..."
        contentTintColor = .controlAccentColor
        startListening()
    }

    private func startListening() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            if event.keyCode == 53 { self.cancel(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.control) else { return nil }
            self.keyCode = event.keyCode
            self.modifiers = carbonModifiers(from: flags)
            self.finish()
            return nil
        }
    }

    private func finish() {
        isRecording = false; stopListening(); updateDisplay()
        onChange?(keyCode, modifiers)
    }

    private func cancel() {
        isRecording = false; stopListening(); updateDisplay()
    }

    private func stopListening() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController: NSWindowController {
    private let settings = Settings.shared
    private var itemsStepper: NSStepper!
    private var itemsValueLabel: NSTextField!
    private var loginCheckbox: NSButton!
    private var popupCheckbox: NSButton!
    private var shortcutButton: ShortcutRecorderButton!

    var onHotkeyChanged: (() -> Void)?
    var onMaxItemsChanged: (() -> Void)?

    init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        w.title = "ClipBoard Settings"
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13); l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    private func makeSectionHeader(_ text: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.topAnchor.constraint(equalTo: container.topAnchor),
            sep.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            container.heightAnchor.constraint(equalToConstant: 16),
        ])
        return container
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
        ])

        // -- General section --
        let generalHeader = makeSectionHeader("GENERAL")
        generalHeader.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(generalHeader)

        // History size
        let historyRow = NSStackView()
        historyRow.orientation = .horizontal; historyRow.spacing = 8
        let historyLabel = makeLabel("History size")
        historyLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        itemsValueLabel = NSTextField(labelWithString: "\(settings.maxItems)")
        itemsValueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        itemsValueLabel.alignment = .center
        itemsValueLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true

        itemsStepper = NSStepper()
        itemsStepper.minValue = 5; itemsStepper.maxValue = 50; itemsStepper.increment = 1
        itemsStepper.integerValue = settings.maxItems
        itemsStepper.valueWraps = false
        itemsStepper.target = self; itemsStepper.action = #selector(stepperChanged)

        historyRow.addArrangedSubview(historyLabel)
        historyRow.addArrangedSubview(itemsValueLabel)
        historyRow.addArrangedSubview(itemsStepper)
        stack.addArrangedSubview(historyRow)

        // Launch at login
        let loginRow = NSStackView()
        loginRow.orientation = .horizontal; loginRow.spacing = 8
        let loginLabel = makeLabel("Launch at login")
        loginLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        loginCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(loginToggled))
        loginCheckbox.state = settings.launchAtLogin ? .on : .off

        loginRow.addArrangedSubview(loginLabel)
        loginRow.addArrangedSubview(loginCheckbox)
        stack.addArrangedSubview(loginRow)

        // -- Shortcut section --
        stack.addArrangedSubview(NSView()) // spacer
        let shortcutHeader = makeSectionHeader("SHORTCUT")
        shortcutHeader.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(shortcutHeader)

        // Enable popup
        let popupRow = NSStackView()
        popupRow.orientation = .horizontal; popupRow.spacing = 8
        let popupLabel = makeLabel("Enable popup")
        popupLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        popupCheckbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(popupToggled))
        popupCheckbox.state = settings.popupEnabled ? .on : .off

        popupRow.addArrangedSubview(popupLabel)
        popupRow.addArrangedSubview(popupCheckbox)
        stack.addArrangedSubview(popupRow)

        // Shortcut recorder
        let shortcutRow = NSStackView()
        shortcutRow.orientation = .horizontal; shortcutRow.spacing = 8
        let scLabel = makeLabel("Quick paste")
        scLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true

        shortcutButton = ShortcutRecorderButton()
        shortcutButton.bezelStyle = .rounded
        shortcutButton.widthAnchor.constraint(equalToConstant: 90).isActive = true
        shortcutButton.configure(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
        shortcutButton.onChange = { [weak self] kc, mods in
            self?.settings.hotkeyKeyCode = kc
            self?.settings.hotkeyModifiers = mods
            self?.onHotkeyChanged?()
        }

        let hint = NSTextField(labelWithString: "Click to record")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .tertiaryLabelColor

        shortcutRow.addArrangedSubview(scLabel)
        shortcutRow.addArrangedSubview(shortcutButton)
        shortcutRow.addArrangedSubview(hint)
        stack.addArrangedSubview(shortcutRow)
    }

    @objc private func stepperChanged() {
        let val = itemsStepper.integerValue
        settings.maxItems = val
        itemsValueLabel.stringValue = "\(val)"
        onMaxItemsChanged?()
    }

    @objc private func loginToggled() {
        settings.launchAtLogin = loginCheckbox.state == .on
    }

    @objc private func popupToggled() {
        settings.popupEnabled = popupCheckbox.state == .on
        onHotkeyChanged?()
    }
}

// MARK: - Carbon Hotkey Handler

private func carbonHotKeyHandler(
    nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { globalAppDelegate?.toggleSuggestionPanel() }
    return noErr
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let monitor = ClipboardMonitor()
    private var suggestionWC: SuggestionWindowController?
    private var settingsWC: SettingsWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        globalAppDelegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
        }
        rebuildMenu()
        monitor.start { [weak self] in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        registerGlobalHotKey()
        checkAccessibilityPermission()
    }

    private func checkAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            NSLog("ClipBoard: Accessibility permission needed for paste simulation")
        }
    }

    private var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Global Hotkey

    func registerGlobalHotKey() {
        unregisterGlobalHotKey()
        guard Settings.shared.popupEnabled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyHandler, 1, &eventType, nil, nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: UInt32(1))
        RegisterEventHotKey(
            UInt32(Settings.shared.hotkeyKeyCode),
            Settings.shared.hotkeyModifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    func unregisterGlobalHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    // MARK: - Suggestion Panel

    func toggleSuggestionPanel() {
        guard Settings.shared.popupEnabled else { return }
        if let wc = suggestionWC, wc.window?.isVisible == true {
            dismissSuggestionPanel()
        } else {
            showSuggestionPanel()
        }
    }

    private func showSuggestionPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication
        if suggestionWC == nil { suggestionWC = SuggestionWindowController() }
        guard let wc = suggestionWC, let panel = wc.window else { return }

        wc.onSelect = { [weak self] item in self?.handleSuggestionSelect(item) }
        wc.onDismiss = { [weak self] in self?.dismissSuggestionPanel() }
        wc.onTogglePin = { [weak self] item in
            guard let self = self else { return }
            self.monitor.togglePin(item)
            wc.updateItems(self.monitor.history)
            self.rebuildMenu()
        }
        wc.updateItems(monitor.history)

        let mouse = NSEvent.mouseLocation
        panel.setFrameTopLeftPoint(NSPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y + 10))

        if let screen = NSScreen.main {
            var f = panel.frame; let sf = screen.visibleFrame
            if f.minX < sf.minX { f.origin.x = sf.minX + 4 }
            if f.maxX > sf.maxX { f.origin.x = sf.maxX - f.width - 4 }
            if f.minY < sf.minY { f.origin.y = sf.minY + 4 }
            if f.maxY > sf.maxY { f.origin.y = sf.maxY - f.height - 4 }
            panel.setFrame(f, display: true)
        }

        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissSuggestionPanel()
        }
    }

    private func dismissSuggestionPanel() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        suggestionWC?.close()
        if let prev = previousApp { prev.activate(); previousApp = nil }
    }

    private func handleSuggestionSelect(_ item: ClipboardItem) {
        monitor.copyToClipboard(item)
        rebuildMenu()
        dismissSuggestionPanel()
        waitForModifiersReleasedThenPaste()
    }

    private func waitForModifiersReleasedThenPaste() {
        DispatchQueue.global(qos: .userInteractive).async {
            // Wait up to 2s for user to release modifier keys from the hotkey
            for _ in 0..<200 {
                let flags = CGEventSource.flagsState(.hidSystemState)
                let modifierBits = flags.rawValue & 0x00FF_0000
                if modifierBits == 0 { break }
                usleep(10_000) // 10ms
            }
            // Small extra delay to let the target app fully activate
            usleep(50_000) // 50ms
            DispatchQueue.main.async { [weak self] in
                self?.simulatePaste()
            }
        }
    }

    private func simulatePaste() {
        // Try AppleScript approach — works reliably with Accessibility permission
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error = error {
            NSLog("ClipBoard: AppleScript paste failed: \(error)")
            // Fallback to CGEvent
            simulatePasteCGEvent()
        }
    }

    private func simulatePasteCGEvent() {
        guard isAccessibilityTrusted else {
            NSLog("ClipBoard: Accessibility not granted, cannot simulate paste")
            DispatchQueue.main.async { [weak self] in self?.showAccessibilityAlert() }
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        usleep(10_000)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "ClipBoard needs Accessibility access to paste automatically.\n\nGo to System Settings → Privacy & Security → Accessibility and enable ClipBoard."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
            settingsWC?.onHotkeyChanged = { [weak self] in
                self?.registerGlobalHotKey()
                self?.rebuildMenu()
            }
            settingsWC?.onMaxItemsChanged = { [weak self] in
                self?.monitor.trimUnpinned()
                self?.rebuildMenu()
            }
        }
        settingsWC?.showWindow(nil)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Menu Bar

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
            let empty = NSMenuItem(title: "No items yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false; menu.addItem(empty)
        } else {
            for (index, item) in monitor.history.enumerated() {
                if !pinnedItems.isEmpty && !unpinnedItems.isEmpty && item === unpinnedItems.first {
                    menu.addItem(NSMenuItem.separator())
                }
                let keyEquiv = index < 9 ? "\(index + 1)" : (index == 9 ? "0" : "")
                let mi = NSMenuItem(title: "", action: #selector(clipboardItemClicked(_:)), keyEquivalent: keyEquiv)
                if !keyEquiv.isEmpty { mi.keyEquivalentModifierMask = .command }
                let previewStr = item.preview
                let timeStr = "  \(item.timeAgo)"
                let attr = NSMutableAttributedString(string: previewStr + timeStr)
                attr.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)],
                                   range: NSRange(location: 0, length: previewStr.count))
                attr.addAttributes([.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor],
                                   range: NSRange(location: previewStr.count, length: timeStr.count))
                mi.attributedTitle = attr
                mi.tag = index; mi.target = self
                if item.isPinned {
                    mi.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
                    mi.image?.size = NSSize(width: 12, height: 12); mi.image?.isTemplate = true
                }
                let sub = NSMenu()
                let pin = NSMenuItem(title: item.isPinned ? "Unpin" : "Pin",
                                     action: #selector(togglePinFromMenu(_:)), keyEquivalent: "")
                pin.tag = index; pin.target = self; sub.addItem(pin)
                mi.submenu = sub
                menu.addItem(mi)
            }
        }

        menu.addItem(NSMenuItem.separator())

        if Settings.shared.popupEnabled {
            let hint = NSMenuItem(title: "Quick Paste: \(Settings.shared.hotkeyDisplayString)", action: nil, keyEquivalent: "")
            hint.isEnabled = false; menu.addItem(hint)
            menu.addItem(NSMenuItem.separator())
        }

        let clearItem = NSMenuItem(title: "Clear Unpinned", action: #selector(clearHistory), keyEquivalent: "K")
        clearItem.keyEquivalentModifierMask = [.command, .shift]
        clearItem.target = self; clearItem.isEnabled = !unpinnedItems.isEmpty
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        clearItem.image?.size = NSSize(width: 14, height: 14); clearItem.image?.isTemplate = true
        menu.addItem(clearItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command; settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.image?.size = NSSize(width: 14, height: 14); settingsItem.image?.isTemplate = true
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit ClipBoard", action: #selector(quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command; quit.target = self
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        quit.image?.size = NSSize(width: 14, height: 14); quit.image?.isTemplate = true
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func clipboardItemClicked(_ sender: NSMenuItem) {
        let i = sender.tag
        guard i < monitor.history.count else { return }
        monitor.copyToClipboard(monitor.history[i]); rebuildMenu()
        waitForModifiersReleasedThenPaste()
    }

    @objc private func togglePinFromMenu(_ sender: NSMenuItem) {
        let i = sender.tag
        guard i < monitor.history.count else { return }
        monitor.togglePin(monitor.history[i]); rebuildMenu()
    }

    @objc private func clearHistory() { monitor.clearHistory(); rebuildMenu() }
    @objc private func quitApp() { NSApplication.shared.terminate(nil) }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
