import Cocoa
import UserNotifications
import ApplicationServices

class ClipboardItemCard: NSView {
    private var contentLabel: NSTextField!
    private var imageView: NSImageView?
    private var pinButton: NSButton!
    private var menuButton: NSButton!
    private var saveButton: NSButton?
    var item: ClipboardItem!
    private var clickAction: ((ClipboardItem) -> Void)?
    var isSelected: Bool = false {
        didSet {
            if isSelected != oldValue {
                updateSelectionAppearance()
            }
        }
    }
    
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
        
        if item.isImage, let image = item.getImage() {
            // Setup image view for image content
            imageView = NSImageView(frame: NSRect(x: 16, y: 16, width: frame.width - 80, height: frame.height - 32))
            imageView?.image = image
            imageView?.imageScaling = .scaleProportionallyUpOrDown
            imageView?.autoresizingMask = [.width, .height]
            
            if let imageView = imageView {
                addSubview(imageView)
                
                // Add click gesture for the image area
                let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewClicked))
                clickGesture.numberOfClicksRequired = 1
                clickGesture.delaysPrimaryMouseButtonEvents = true
                imageView.addGestureRecognizer(clickGesture)
                
                // Add double-click gesture for viewing the image
                let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewDoubleClicked))
                doubleClickGesture.numberOfClicksRequired = 2
                doubleClickGesture.delaysPrimaryMouseButtonEvents = true
                imageView.addGestureRecognizer(doubleClickGesture)
                
                // Make sure double-click takes precedence
                doubleClickGesture.delaysPrimaryMouseButtonEvents = true
            }
            
            // Add save button for images
            saveButton = NSButton(frame: NSRect(x: frame.width - 90, y: frame.height - 30, width: 24, height: 24))
            saveButton?.bezelStyle = .inline
            saveButton?.isBordered = false
            saveButton?.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            saveButton?.imagePosition = .imageOnly
            saveButton?.autoresizingMask = [.minXMargin, .minYMargin]
            saveButton?.target = self
            saveButton?.action = #selector(saveButtonClicked)
            
            if let saveButton = saveButton {
                addSubview(saveButton)
            }
        } else {
            // Content label for text content
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
            
            addSubview(contentLabel)
            
            // Add click gesture for the content area
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewClicked))
            clickGesture.numberOfClicksRequired = 1
            clickGesture.delaysPrimaryMouseButtonEvents = true
            contentLabel.addGestureRecognizer(clickGesture)
            
            // Add double-click gesture for editing
            let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewDoubleClicked))
            doubleClickGesture.numberOfClicksRequired = 2
            doubleClickGesture.delaysPrimaryMouseButtonEvents = true
            contentLabel.addGestureRecognizer(doubleClickGesture)
            
            // Make sure double-click takes precedence
            doubleClickGesture.delaysPrimaryMouseButtonEvents = true
        }
        
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
        
        addSubview(pinButton)
        addSubview(menuButton)
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
        
        // If selected, update selection appearance
        if isSelected {
            updateSelectionAppearance()
        }
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
        // Check if this is part of a double-click sequence
        if NSApp.currentEvent?.clickCount ?? 0 > 1 {
            // This is part of a double-click, let the double-click handler handle it
            return
        }
        
        // Notify that this card was clicked (for selection)
        NotificationCenter.default.post(name: NSNotification.Name("CardClicked"), object: item.id)
        
        // Call the click action (for copying to clipboard)
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
        
        // Add appropriate edit/view option based on content type
        if item.isImage {
            let viewItem = NSMenuItem(title: "View Image", action: #selector(viewImageClicked), keyEquivalent: "")
            viewItem.target = self
            menu.addItem(viewItem)
            
            // Add save options for images
            let saveAsItem = NSMenuItem(title: "Save As...", action: #selector(saveButtonClicked(_:)), keyEquivalent: "")
            saveAsItem.target = self
            menu.addItem(saveAsItem)
        } else {
            let editItem = NSMenuItem(title: "Edit", action: #selector(editItemClicked), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)
        }
        
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
    
    @objc private func editItemClicked() {
        // Post notification to edit this item
        NotificationCenter.default.post(name: NSNotification.Name("EditClipboardItem"), object: item.id)
    }
    
    @objc private func deleteItemClicked() {
        // Delete item
        NotificationCenter.default.post(name: NSNotification.Name("DeleteClipboardItem"), object: item.id)
    }
    
    @objc private func viewImageClicked() {
        // Open image in default image viewer
        guard item.isImage else { return }
        
        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("clipboard_image_\(item.id.uuidString).png")
        
        do {
            // Convert to PNG for viewing
            if let image = item.getImage(),
               let tiffData = image.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                
                try pngData.write(to: tempFile)
                
                // Open with default application
                NSWorkspace.shared.open(tempFile)
            }
        } catch {
            print("Error opening image: \(error)")
        }
    }
    
    @objc private func saveButtonClicked(_ sender: NSButton) {
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        guard item.isImage, let image = item.getImage() else { return }
        
        // Create save menu
        let menu = NSMenu()
        
        // Add "Save as PNG" option
        let pngItem = NSMenuItem(title: "Save as PNG", action: #selector(saveAsPNG), keyEquivalent: "")
        pngItem.target = self
        menu.addItem(pngItem)
        
        // Add "Save as JPEG" option
        let jpegItem = NSMenuItem(title: "Save as JPEG", action: #selector(saveAsJPEG), keyEquivalent: "")
        jpegItem.target = self
        menu.addItem(jpegItem)
        
        // Show menu
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: sender)
    }
    
    @objc private func saveAsPNG() {
        saveImage(fileType: .png)
    }
    
    @objc private func saveAsJPEG() {
        saveImage(fileType: .jpeg)
    }
    
    private func saveImage(fileType: NSBitmapImageRep.FileType) {
        guard item.isImage, let image = item.getImage() else { return }
        
        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = fileType == .png ? ["png"] : ["jpg", "jpeg"]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Image"
        savePanel.message = "Choose a location to save the image"
        savePanel.nameFieldStringValue = "clipboard_image"
        
        savePanel.beginSheetModal(for: self.window!) { response in
            if response == .OK, let url = savePanel.url {
                // Convert image to data
                guard let tiffData = image.tiffRepresentation,
                      let bitmapImage = NSBitmapImageRep(data: tiffData) else { return }
                
                let imageData: Data?
                if fileType == .png {
                    imageData = bitmapImage.representation(using: .png, properties: [:])
                } else {
                    imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                }
                
                // Save to file
                if let imageData = imageData {
                    do {
                        try imageData.write(to: url)
                    } catch {
                        // Show error alert
                        let alert = NSAlert()
                        alert.messageText = "Error Saving Image"
                        alert.informativeText = error.localizedDescription
                        alert.alertStyle = .warning
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }
    
    @objc private func viewDoubleClicked() {
        // Prevent event propagation to avoid beep sound
        NSApp.preventWindowOrdering()
        
        // Discard any pending mouse up events to prevent the single-click action from firing
        NSApp.discardEvents(matching: .leftMouseUp, before: nil)
        
        // First, notify that this card was clicked to update selection
        NotificationCenter.default.post(name: NSNotification.Name("CardClicked"), object: item.id)
        
        // For double-click, we want to edit text or view image, not paste
        if item.isImage {
            // Directly call the method to view the image
            viewImageClicked()
        } else {
            // Directly call the method to edit the text
            editItemClicked()
        }
        
        // Prevent the single-click action from being triggered
        NSApp.discardEvents(matching: .leftMouseUp, before: nil)
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
    
    private func updateSelectionAppearance() {
        // Update the appearance based on selection state
        if isSelected {
            // Get preferences
            let prefs = Preferences.shared
            
            // Create a selection indicator
            wantsLayer = true
            
            // Apply a highlighted background color
            if let backgroundColor = NSColor.fromHex(prefs.cardBackgroundColor) {
                // Use a slightly brighter version of the background color
                let brighterColor = backgroundColor.blended(withFraction: 0.3, of: NSColor.white) ?? backgroundColor
                layer?.backgroundColor = brighterColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha)).cgColor
                
                // Add a border
                layer?.borderWidth = 2.0
                layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
            }
        } else {
            // Reset to normal appearance
            applyPreferences()
            layer?.borderWidth = 0.0
        }
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
    private var selectedItemIndex: Int = 0 // Track the currently selected item
    private var selectedCard: ClipboardItemCard? // Reference to the currently selected card
    
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
        
        // Register for card click notifications
        NotificationCenter.default.addObserver(self, selector: #selector(cardClicked(_:)), name: NSNotification.Name("CardClicked"), object: nil)
        
        // Register for edit item notifications
        NotificationCenter.default.addObserver(self, selector: #selector(editClipboardItem(_:)), name: NSNotification.Name("EditClipboardItem"), object: nil)
        
        // Set up keyboard event monitoring
        setupKeyboardMonitoring()
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
        
        // Reset selected item index to the most recent item (top item)
        selectedItemIndex = 0
        selectedCard = nil
        
        // Calculate container height based on number of items and preferences
        let containerHeight = CGFloat(displayItems.count * prefs.cardHeight + (displayItems.count - 1) * prefs.cardSpacing + 20)
        containerView.frame = NSRect(x: 0, y: 0, width: containerView.frame.width, height: max(containerHeight, scrollView.bounds.height))
        
        // Create card for each item
        var yPosition = Int(containerHeight) - prefs.cardHeight - 10
        
        for (index, item) in displayItems.enumerated() {
            let cardFrame = NSRect(x: 20, y: CGFloat(yPosition), width: containerView.bounds.width - 40, height: CGFloat(prefs.cardHeight))
            let card = ClipboardItemCard(frame: cardFrame, item: item) { [weak self] selectedItem in
                self?.itemSelected(selectedItem)
            }
            card.autoresizingMask = [.width]
            
            // Set selection state for the card
            card.isSelected = (index == selectedItemIndex)
            if index == selectedItemIndex {
                selectedCard = card
            }
            
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
        // Ensure we maintain accessory policy
        NSApp.setActivationPolicy(.accessory)
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
        
        // Ensure we're still using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
    }
    
    // Add a method to update items without recreating the window
    func updateItems(_ newItems: [ClipboardItem]) {
        self.items = newItems
        updateCardViews()
    }
    
    private func setupKeyboardMonitoring() {
        // Make the window first responder to receive key events
        window?.makeFirstResponder(nil)
        
        // Set up local event monitor for keyboard events
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            
            // Handle key events
            if self.handleKeyEvent(event) {
                return nil // Event was handled, don't propagate
            }
            
            return event // Event wasn't handled, propagate normally
        }
        
        // Set up local event monitor for mouse events to prevent beep on double-click and triple-click
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            // If it's a double-click or triple-click, we'll handle it in our gesture recognizers
            if event.clickCount >= 2 && event.type == .leftMouseDown {
                // Let our gesture recognizers handle it
                return event
            } else if event.clickCount >= 2 && event.type == .leftMouseUp {
                // Prevent the system beep by consuming the event
                return nil
            }
            
            return event // Not a multi-click, propagate normally
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        
        // Get filtered items based on current tab
        let displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        
        // Handle arrow keys
        switch keyCode {
        case 125: // Down arrow
            if selectedItemIndex < displayItems.count - 1 {
                // Deselect current item
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                // Select next item
                selectedItemIndex += 1
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible
                scrollToSelectedItem()
            }
            return true
            
        case 126: // Up arrow
            if selectedItemIndex > 0 {
                // Deselect current item
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                // Select previous item
                selectedItemIndex -= 1
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible
                scrollToSelectedItem()
            }
            return true
            
        case 36: // Return/Enter key
            if !displayItems.isEmpty && selectedItemIndex < displayItems.count {
                let item = displayItems[selectedItemIndex]
                
                // For Return/Enter key, paste the item
                itemSelected(item)
            }
            return true
            
        case 14: // E key
            if !displayItems.isEmpty && selectedItemIndex < displayItems.count {
                // Edit the selected item or view the image
                let item = displayItems[selectedItemIndex]
                
                // Post the edit notification - the handler will determine whether to edit or view based on content type
                NotificationCenter.default.post(name: NSNotification.Name("EditClipboardItem"), object: item.id)
            }
            return true
            
        default:
            return false
        }
    }
    
    private func updateCardSelection(at index: Int, isSelected: Bool) {
        // Get filtered items based on current tab
        let displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        
        // Ensure index is valid
        guard index >= 0 && index < displayItems.count else { return }
        
        // Find the card view for the item at the given index
        for subview in containerView.subviews {
            if let card = subview as? ClipboardItemCard, card.item.id == displayItems[index].id {
                if isSelected {
                    // Store reference to selected card
                    selectedCard = card
                    
                    // Highlight the selected card
                    card.isSelected = true
                } else {
                    // Remove highlight
                    card.isSelected = false
                    
                    // Clear reference if this was the selected card
                    if selectedCard == card {
                        selectedCard = nil
                    }
                }
                break
            }
        }
    }
    
    private func scrollToSelectedItem() {
        guard let selectedCard = selectedCard else { return }
        
        // Convert card frame to scroll view coordinates
        let cardFrameInScrollView = containerView.convert(selectedCard.frame, to: scrollView.contentView)
        
        // Check if card is fully visible in the scroll view
        let scrollViewVisibleRect = scrollView.contentView.bounds
        
        if !scrollViewVisibleRect.contains(cardFrameInScrollView) {
            // Card is not fully visible, scroll to make it visible
            scrollView.contentView.scrollToVisible(cardFrameInScrollView)
        }
    }
    
    @objc private func cardClicked(_ notification: Notification) {
        // Get the clicked item ID
        guard let clickedItemId = notification.object as? UUID else { return }
        
        // Get filtered items based on current tab
        let displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        
        // Find the index of the clicked item
        if let index = displayItems.firstIndex(where: { $0.id == clickedItemId }) {
            // Deselect current item if different
            if index != selectedItemIndex {
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                // Update selected index
                selectedItemIndex = index
                
                // Select the new item
                updateCardSelection(at: selectedItemIndex, isSelected: true)
            }
        }
    }
    
    @objc private func editClipboardItem(_ notification: Notification) {
        // Get the item ID to edit
        guard let itemId = notification.object as? UUID,
              let itemIndex = items.firstIndex(where: { $0.id == itemId }) else { return }
        
        let item = items[itemIndex]
        
        // If it's an image, just show the image viewer instead of edit dialog
        if item.isImage {
            // Create a temporary file
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("clipboard_image_\(item.id.uuidString).png")
            
            do {
                // Convert to PNG for viewing
                if let image = item.getImage(),
                   let tiffData = image.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    
                    try pngData.write(to: tempFile)
                    
                    // Open with default application
                    NSWorkspace.shared.open(tempFile)
                }
            } catch {
                print("Error opening image: \(error)")
            }
            return
        }
        
        // For text items, show the edit dialog
        // Create an edit dialog
        let alert = NSAlert()
        alert.messageText = "Edit Clipboard Item"
        alert.informativeText = "Modify the text below:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        // Add a text field for editing
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textField.stringValue = item.content
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = true
        textField.drawsBackground = true
        textField.font = NSFont.systemFont(ofSize: 14)
        
        // Create a scroll view to contain the text field for long content
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        
        // Use a text view instead for better multiline editing
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = item.content
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        
        scrollView.documentView = textView
        
        alert.accessoryView = scrollView
        
        // Ensure alert appears on top of other applications
        NSApp.activate(ignoringOtherApps: true)
        alert.window.level = .floating
        
        // Show the dialog
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // User clicked Save
            let updatedContent = textView.string
            
            // Update the item in the clipboard manager
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateClipboardItem"),
                object: nil,
                userInfo: ["itemId": itemId, "content": updatedContent]
            )
        }
        
        // Ensure we're still using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
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
