import Cocoa
import UserNotifications
import ApplicationServices

class ClipboardItemCard: NSView {
    private var contentLabel: NSTextField!
    private var pinButton: NSButton!
    private var menuButton: NSButton!
    private var item: ClipboardItem!
    private var clickAction: ((ClipboardItem) -> Void)?
    
    init(frame: NSRect, item: ClipboardItem, clickAction: @escaping (ClipboardItem) -> Void) {
        self.item = item
        self.clickAction = clickAction
        super.init(frame: frame)
        setupUI()
        
        // Register for preferences changes
        NotificationCenter.default.addObserver(self, selector: #selector(applyPreferences), name: NSNotification.Name("PreferencesChanged"), object: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        // Card background
        wantsLayer = true
        applyPreferences()
        
        // Content label
        contentLabel = NSTextField(frame: NSRect(x: 16, y: 16, width: frame.width - 80, height: frame.height - 32))
        contentLabel.isEditable = false
        contentLabel.isBordered = false
        contentLabel.drawsBackground = false
        contentLabel.lineBreakMode = .byTruncatingTail
        contentLabel.cell?.wraps = true
        contentLabel.cell?.truncatesLastVisibleLine = true
        contentLabel.font = NSFont.systemFont(ofSize: 14)
        contentLabel.autoresizingMask = [.width, .height]
        contentLabel.stringValue = item.content.count > 100 ? String(item.content.prefix(97)) + "..." : item.content
        
        // Apply text color from preferences
        applyTextColor()
        
        // Pin button
        pinButton = NSButton(frame: NSRect(x: frame.width - 60, y: frame.height - 30, width: 24, height: 24))
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        
        // Set pin image based on pinned state
        let pinImageName = item.isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: pinImageName, accessibilityDescription: "Pin")
        
        pinButton.imagePosition = .imageOnly
        pinButton.autoresizingMask = [.minXMargin, .minYMargin]
        pinButton.target = self
        pinButton.action = #selector(pinButtonClicked)
        
        // Menu button
        menuButton = NSButton(frame: NSRect(x: frame.width - 30, y: frame.height - 30, width: 24, height: 24))
        menuButton.bezelStyle = .inline
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More")
        menuButton.imagePosition = .imageOnly
        menuButton.autoresizingMask = [.minXMargin, .minYMargin]
        menuButton.target = self
        menuButton.action = #selector(menuButtonClicked)
        
        addSubview(contentLabel)
        addSubview(pinButton)
        addSubview(menuButton)
        
        // Add click gesture for the content area only
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewClicked))
        contentLabel.addGestureRecognizer(clickGesture)
    }
    
    @objc private func applyPreferences() {
        let prefs = Preferences.shared
        
        // Apply background color
        if let backgroundColor = NSColor.fromHex(prefs.cardBackgroundColor) {
            layer?.backgroundColor = backgroundColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha)).cgColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha)).cgColor
        }
        
        layer?.cornerRadius = 8
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.1).cgColor
        layer?.shadowOffset = NSSize(width: 0, height: 1)
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 3
        
        // Apply text color if content label exists
        applyTextColor()
    }
    
    private func applyTextColor() {
        guard contentLabel != nil else { return }
        
        let prefs = Preferences.shared
        if let textColor = NSColor.fromHex(prefs.textColor) {
            contentLabel.textColor = textColor
        } else {
            contentLabel.textColor = NSColor.labelColor
        }
    }
    
    @objc private func viewClicked() {
        clickAction?(item)
    }
    
    @objc private func pinButtonClicked(_ sender: NSButton) {
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        // Toggle pin state
        NotificationCenter.default.post(name: NSNotification.Name("TogglePinClipboardItem"), object: item.id)
        
        // Update pin button image immediately for better UX
        let pinImageName = !item.isPinned ? "pin.fill" : "pin"
        pinButton.image = NSImage(systemSymbolName: pinImageName, accessibilityDescription: "Pin")
    }
    
    @objc private func menuButtonClicked(_ sender: NSButton) {
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        // Create context menu
        let menu = NSMenu()
        
        // Add "Copy" option
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyItemClicked), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        
        // Add "Delete" option
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteItemClicked), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        
        // Show menu
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: sender)
    }
    
    @objc private func copyItemClicked() {
        clickAction?(item)
    }
    
    @objc private func deleteItemClicked() {
        // Delete item
        NotificationCenter.default.post(name: NSNotification.Name("DeleteClipboardItem"), object: item.id)
    }
    
    override func mouseEntered(with event: NSEvent) {
        let prefs = Preferences.shared
        if let backgroundColor = NSColor.fromHex(prefs.cardBackgroundColor) {
            layer?.backgroundColor = backgroundColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha * 0.8)).cgColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        applyPreferences()
    }
}

class HistoryWindowController: NSWindowController {
    private var items: [ClipboardItem] = []
    private var scrollView: NSScrollView!
    private var headerView: NSView!
    private var clearAllButton: NSButton!
    private var containerView: NSView!
    private var tabView: NSSegmentedControl! // Add tab view for All/Pinned tabs
    private var currentTab: Int = 0 // 0 = All, 1 = Pinned
    private var targetApplication: NSRunningApplication? // Store the target application
    
    init(items: [ClipboardItem]) {
        print("HistoryWindowController init with \(items.count) items")
        for (index, item) in items.enumerated() {
            print("Window item \(index): \(item.content.prefix(30))...")
        }
        
        self.items = items
        
        // Store the frontmost application before showing our window
        self.targetApplication = NSWorkspace.shared.frontmostApplication
        print("Target application: \(targetApplication?.localizedName ?? "Unknown")")
        
        // Get preferences
        let prefs = Preferences.shared
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: prefs.windowWidth, height: prefs.windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Clipboard"
        window.titlebarAppearsTransparent = true
        
        // Apply window background color from preferences
        window.backgroundColor = prefs.windowBackgroundNSColor()
        
        // Make the window appear on top of other applications
        window.level = .floating
        
        // Set window behavior to stay on top but not take focus
        window.collectionBehavior = [.moveToActiveSpace, .transient]
        window.isMovableByWindowBackground = true
        
        super.init(window: window)
        
        setupUI()
        
        // Register for history updates
        NotificationCenter.default.addObserver(self, selector: #selector(historyUpdated), name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        
        // Register for preferences changes
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: NSNotification.Name("PreferencesChanged"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        print("Setting up UI for history window")
        guard let window = self.window else { return }
        
        // Create main content view
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        
        // Create header view
        headerView = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 60, width: contentView.bounds.width, height: 60))
        headerView.autoresizingMask = [.width, .minYMargin]
        
        // Add title label
        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 20, width: 200, height: 24))
        titleLabel.stringValue = "Clipboard"
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.textColor = NSColor.labelColor
        
        // Add tab view for All/Pinned tabs
        tabView = NSSegmentedControl(frame: NSRect(x: 200, y: 20, width: 150, height: 24))
        tabView.segmentCount = 2
        tabView.setLabel("All", forSegment: 0)
        tabView.setLabel("Pinned", forSegment: 1)
        tabView.selectedSegment = 0
        tabView.target = self
        tabView.action = #selector(tabChanged)
        tabView.segmentStyle = .texturedRounded
        tabView.autoresizingMask = [.minXMargin]
        
        // Add clear all button
        clearAllButton = NSButton(frame: NSRect(x: headerView.bounds.width - 100, y: 20, width: 80, height: 24))
        clearAllButton.title = "Clear all"
        clearAllButton.bezelStyle = .rounded
        clearAllButton.font = NSFont.systemFont(ofSize: 12)
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllClicked)
        clearAllButton.autoresizingMask = [.minXMargin]
        
        headerView.addSubview(titleLabel)
        headerView.addSubview(tabView)
        headerView.addSubview(clearAllButton)
        contentView.addSubview(headerView)
        
        // Create scroll view for cards
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 60))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor.clear
        
        let clipView = NSClipView(frame: scrollView.bounds)
        clipView.autoresizingMask = [.width, .height]
        clipView.drawsBackground = false
        
        // Calculate container height based on number of items and preferences
        let prefs = Preferences.shared
        let containerHeight = CGFloat(items.count * prefs.cardHeight + (items.count - 1) * prefs.cardSpacing + 20)
        containerView = NSView(frame: NSRect(x: 0, y: 0, width: scrollView.bounds.width, height: max(containerHeight, scrollView.bounds.height)))
        containerView.autoresizingMask = [.width]
        
        updateCardViews()
        
        clipView.documentView = containerView
        scrollView.contentView = clipView
        contentView.addSubview(scrollView)
        
        // Scroll to top
        scrollToTop()
        
        print("UI setup complete with \(items.count) cards")
    }
    
    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        currentTab = sender.selectedSegment
        
        // Update window title based on selected tab
        if currentTab == 0 {
            window?.title = "Clipboard"
        } else {
            window?.title = "Pinned Clipboard Items"
        }
        
        // Update the clear/unpin all button
        if currentTab == 0 {
            clearAllButton.title = "Clear all"
        } else {
            clearAllButton.title = "Unpin all"
        }
        
        // Update the displayed items
        updateCardViews()
    }
    
    private func updateCardViews() {
        // Remove existing cards
        containerView.subviews.forEach { $0.removeFromSuperview() }
        
        // Get preferences
        let prefs = Preferences.shared
        
        // Filter items based on current tab
        let displayItems: [ClipboardItem]
        if currentTab == 0 {
            // All items
            displayItems = items
        } else {
            // Only pinned items
            displayItems = items.filter { $0.isPinned }
        }
        
        // Calculate container height based on number of items and preferences
        let containerHeight = CGFloat(displayItems.count * prefs.cardHeight + (displayItems.count - 1) * prefs.cardSpacing + 20)
        containerView.frame = NSRect(x: 0, y: 0, width: containerView.frame.width, height: max(containerHeight, scrollView.bounds.height))
        
        // Create card for each item
        var yPosition = Int(containerHeight) - prefs.cardHeight - 10
        
        for item in displayItems {
            let cardFrame = NSRect(x: 20, y: CGFloat(yPosition), width: containerView.bounds.width - 40, height: CGFloat(prefs.cardHeight))
            let card = ClipboardItemCard(frame: cardFrame, item: item) { [weak self] selectedItem in
                self?.itemSelected(selectedItem)
            }
            card.autoresizingMask = [.width]
            
            containerView.addSubview(card)
            yPosition -= (prefs.cardHeight + prefs.cardSpacing) // Card height + spacing
        }
        
        // Scroll to top after updating
        scrollToTop()
    }
    
    @objc private func preferencesChanged() {
        // Update UI based on new preferences
        guard let window = self.window else { return }
        
        // Get preferences
        let prefs = Preferences.shared
        
        // Apply window background color
        window.backgroundColor = prefs.windowBackgroundNSColor()
        
        // Apply transparency if enabled
        if prefs.fullClipboardTransparency {
            window.isOpaque = false
            window.backgroundColor = window.backgroundColor?.withAlphaComponent(0.85)
        } else {
            window.isOpaque = true
        }
        
        // Update card views
        updateCardViews()
    }
    
    private func scrollToTop() {
        // Ensure we scroll to the top
        if containerView.frame.height > scrollView.bounds.height {
            let topPoint = NSPoint(x: 0, y: containerView.frame.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: topPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
    
    @objc private func historyUpdated() {
        // Get updated history
        if let appDelegate = NSApp.delegate as? AppDelegate {
            items = appDelegate.getClipboardHistory()
            updateCardViews()
        }
    }
    
    private func itemSelected(_ item: ClipboardItem) {
        print("Item selected: \(item.content.prefix(30))...")
        
        // Create a menu item with the appropriate tag
        let menuItem = NSMenuItem()
        menuItem.tag = items.firstIndex(where: { $0.id == item.id }) ?? 0
        
        // Get the app delegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            // Close the window first
            if let window = self.window, Preferences.shared.closeAfterCopy {
                window.close()
            }
            
            // Reactivate the target application before copying/pasting
            if let targetApp = self.targetApplication {
                print("Reactivating target app: \(targetApp.localizedName ?? "Unknown")")
                targetApp.activate(options: .activateIgnoringOtherApps)
                
                // Small delay to ensure the app is activated
                Thread.sleep(forTimeInterval: 0.1)
            }
            
            // Copy the item to clipboard and paste if needed
            appDelegate.copyItemToClipboard(menuItem)
        }
    }
    
    @objc private func clearAllClicked() {
        // Show confirmation dialog
        let alert = NSAlert()
        
        if currentTab == 0 {
            // Clear all items
            alert.messageText = "Clear Clipboard History"
            alert.informativeText = "Are you sure you want to clear all clipboard history?"
        } else {
            // Unpin all pinned items
            alert.messageText = "Unpin All Items"
            alert.informativeText = "Are you sure you want to unpin all pinned items?"
        }
        
        alert.alertStyle = .warning
        alert.addButton(withTitle: currentTab == 0 ? "Clear" : "Unpin")
        alert.addButton(withTitle: "Cancel")
        
        // Ensure alert appears on top of other applications
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        
        if alert.runModal() == .alertFirstButtonReturn {
            if currentTab == 0 {
                // User confirmed, clear history
                NotificationCenter.default.post(name: NSNotification.Name("ClearClipboardHistory"), object: nil)
            } else {
                // Unpin all pinned items
                for item in items.filter({ $0.isPinned }) {
                    NotificationCenter.default.post(name: NSNotification.Name("TogglePinClipboardItem"), object: item.id)
                }
            }
        }
    }
    
    // Add a method to update items without recreating the window
    func updateItems(_ newItems: [ClipboardItem]) {
        self.items = newItems
        updateCardViews()
    }
}

// MARK: - NSTableViewDataSource
extension HistoryWindowController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        print("numberOfRows called, returning \(items.count)")
        return items.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row < items.count else {
            print("Row \(row) out of bounds")
            return nil
        }
        
        let item = items[row]
        let content = item.content
        
        // Truncate long content for display
        let displayText = content.count > 100 ? String(content.prefix(97)) + "..." : content
        print("Row \(row) displaying: \(displayText.prefix(30))...")
        
        return displayText
    }
}

// MARK: - NSTableViewDelegate
extension HistoryWindowController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 40
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        print("shouldSelectRow called for row \(row)")
        return true
    }
} 
