import Cocoa
import UserNotifications
import ApplicationServices
import UniformTypeIdentifiers
import Carbon.HIToolbox

class ClipboardItemCard: NSView {
    private var contentLabel: NSTextField!
    private var imageView: NSImageView?
    private var pinButton: NSButton!
    private var menuButton: NSButton!
    private var saveButton: NSButton?
    private var pasteButton: NSButton? // Add paste button property
    private var formatIndicator: NSTextField?
    var item: ClipboardItem!
    private var clickAction: ((ClipboardItem) -> Void)?
    var isSelected: Bool = false {
        didSet {
            if isSelected != oldValue {
                updateSelectionAppearance()
            }
        }
    }
    var searchText: String = "" {
        didSet {
            if !item.isImage && contentLabel != nil {
                updateContentWithHighlight()
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
                clickGesture.delaysPrimaryMouseButtonEvents = false // Changed to false to improve responsiveness
                
                // Add double-click gesture for viewing the image
                let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewDoubleClicked))
                doubleClickGesture.numberOfClicksRequired = 2
                doubleClickGesture.delaysPrimaryMouseButtonEvents = false // Changed to false to improve responsiveness
                
                // Add the gestures in the correct order - double-click first
                imageView.addGestureRecognizer(doubleClickGesture)
                imageView.addGestureRecognizer(clickGesture)
                
                // Make the image view accept mouse events
                imageView.acceptsTouchEvents = true
                
                // Make sure double-click takes precedence
                // This line was causing build errors - NSClickGestureRecognizer doesn't have this method
                // clickGesture.requireGestureRecognizerToFail(doubleClickGesture)
                
                // Make the image view accept touch events
                imageView.allowedTouchTypes = [.direct]
            }
            
            // Add format indicator for images
            addFormatIndicator("Image")
            
            // Add save button for images
            saveButton = NSButton(frame: NSRect(x: frame.width - 120, y: frame.height - 30, width: 24, height: 24))
            saveButton?.bezelStyle = .inline
            saveButton?.isBordered = false
            saveButton?.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            saveButton?.imagePosition = .imageOnly
            saveButton?.autoresizingMask = [.minXMargin, .minYMargin]
            saveButton?.target = self
            saveButton?.action = #selector(saveButtonClicked)
            
            if let saveButton = saveButton {
                // Make the save button more visible
                saveButton.contentTintColor = NSColor.systemBlue
                
                // Add hover effect for better visibility
                saveButton.wantsLayer = true
                saveButton.layer?.cornerRadius = 4
                
                // Add tooltip
                saveButton.toolTip = "Save image as file (PNG, JPEG)"
                
                // Add tracking area for hover effects
                let trackingArea = NSTrackingArea(
                    rect: saveButton.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: self,
                    userInfo: ["button": "save"]
                )
                saveButton.addTrackingArea(trackingArea)
                
                addSubview(saveButton)
            }
            
            // Add paste button for images
            pasteButton = NSButton(frame: NSRect(x: frame.width - 90, y: frame.height - 30, width: 24, height: 24))
            pasteButton?.bezelStyle = .inline
            pasteButton?.isBordered = false
            pasteButton?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
            pasteButton?.imagePosition = .imageOnly
            pasteButton?.autoresizingMask = [.minXMargin, .minYMargin]
            pasteButton?.target = self
            pasteButton?.action = #selector(pasteButtonClicked)
            
            if let pasteButton = pasteButton {
                // Make the paste button more visible
                pasteButton.contentTintColor = NSColor.systemGreen
                
                // Add hover effect for better visibility
                pasteButton.wantsLayer = true
                pasteButton.layer?.cornerRadius = 4
                
                // Add tooltip
                pasteButton.toolTip = "Paste this item"
                
                // Add tracking area for hover effects
                let trackingArea = NSTrackingArea(
                    rect: pasteButton.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: self,
                    userInfo: ["button": "paste"]
                )
                pasteButton.addTrackingArea(trackingArea)
                
                addSubview(pasteButton)
            }
        } else {
            // Setup text label for text content
            // Adjust width to leave space for buttons (120px from right edge)
            contentLabel = NSTextField(frame: NSRect(x: 16, y: 16, width: frame.width - 150, height: frame.height - 32))
            contentLabel.isEditable = false
            contentLabel.isBordered = false
            contentLabel.drawsBackground = false
            contentLabel.cell?.wraps = true
            contentLabel.cell?.isScrollable = true
            contentLabel.cell?.truncatesLastVisibleLine = true
            contentLabel.autoresizingMask = [.width, .height]
            contentLabel.font = NSFont.systemFont(ofSize: 14)
            contentLabel.allowsEditingTextAttributes = true
            contentLabel.preferredMaxLayoutWidth = frame.width - 150 // Adjust preferred width to match frame
            
            // Set content with highlighting if needed
            updateContentWithHighlight()
            
            addSubview(contentLabel)
            
            // Add format indicator for rich text
            if item.isRichText || item.hasMultipleFormats {
                addFormatIndicator("Rich Text")
            }
            
            // Add click gesture for the content area
            let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewClicked))
            clickGesture.numberOfClicksRequired = 1
            clickGesture.delaysPrimaryMouseButtonEvents = false // Changed to false to improve responsiveness
            
            // Add double-click gesture for editing
            let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewDoubleClicked))
            doubleClickGesture.numberOfClicksRequired = 2
            doubleClickGesture.delaysPrimaryMouseButtonEvents = false // Changed to false to improve responsiveness
            
            // Add the gestures in the correct order - double-click first
            contentLabel.addGestureRecognizer(doubleClickGesture)
            contentLabel.addGestureRecognizer(clickGesture)
            
            // Make the content label accept touch events
            contentLabel.allowedTouchTypes = [.direct]
            
            // Add save button for text items (similar to image items)
            saveButton = NSButton(frame: NSRect(x: frame.width - 120, y: frame.height - 30, width: 24, height: 24))
            saveButton?.bezelStyle = .inline
            saveButton?.isBordered = false
            saveButton?.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            saveButton?.imagePosition = .imageOnly
            saveButton?.autoresizingMask = [.minXMargin, .minYMargin]
            saveButton?.target = self
            saveButton?.action = #selector(saveTextButtonClicked)
            
            if let saveButton = saveButton {
                // Make the save button more visible for text items
                saveButton.contentTintColor = NSColor.systemBlue
                
                // Add hover effect for better visibility
                saveButton.wantsLayer = true
                saveButton.layer?.cornerRadius = 4
                
                // Add tooltip
                saveButton.toolTip = "Save text as file (TXT, RTF, DOC)"
                
                // Add tracking area for hover effects
                let trackingArea = NSTrackingArea(
                    rect: saveButton.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: self,
                    userInfo: ["button": "save"]
                )
                saveButton.addTrackingArea(trackingArea)
                
                addSubview(saveButton)
            }
            
            // Add paste button for text items
            pasteButton = NSButton(frame: NSRect(x: frame.width - 90, y: frame.height - 30, width: 24, height: 24))
            pasteButton?.bezelStyle = .inline
            pasteButton?.isBordered = false
            pasteButton?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
            pasteButton?.imagePosition = .imageOnly
            pasteButton?.autoresizingMask = [.minXMargin, .minYMargin]
            pasteButton?.target = self
            pasteButton?.action = #selector(pasteButtonClicked)
            
            if let pasteButton = pasteButton {
                // Make the paste button more visible
                pasteButton.contentTintColor = NSColor.systemGreen
                
                // Add hover effect for better visibility
                pasteButton.wantsLayer = true
                pasteButton.layer?.cornerRadius = 4
                
                // Add tooltip
                pasteButton.toolTip = "Paste this item"
                
                // Add tracking area for hover effects
                let trackingArea = NSTrackingArea(
                    rect: pasteButton.bounds,
                    options: [.mouseEnteredAndExited, .activeAlways],
                    owner: self,
                    userInfo: ["button": "paste"]
                )
                pasteButton.addTrackingArea(trackingArea)
                
                addSubview(pasteButton)
            }
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
    
    private func addFormatIndicator(_ formatType: String) {
        formatIndicator = NSTextField(frame: NSRect(x: frame.width - 120, y: 5, width: 80, height: 16))
        formatIndicator?.isEditable = false
        formatIndicator?.isBordered = false
        formatIndicator?.drawsBackground = true
        formatIndicator?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2)
        formatIndicator?.textColor = NSColor.systemBlue
        formatIndicator?.alignment = .center
        formatIndicator?.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        formatIndicator?.stringValue = formatType
        formatIndicator?.autoresizingMask = [.minXMargin, .maxYMargin]
        
        // Make it look like a pill/badge
        formatIndicator?.wantsLayer = true
        formatIndicator?.layer?.cornerRadius = 8
        
        if let formatIndicator = formatIndicator {
            addSubview(formatIndicator)
        }
    }
    
    private func updateContentWithHighlight() {
        guard contentLabel != nil else { return }
        
        // Handle rich text content
        if item.isRichText, let richTextData = item.richTextData {
            do {
                // Create attributed string from rich text data
                let attributedString = try NSAttributedString(
                    data: richTextData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                
                // If we have search text, we need to highlight it
                if !searchText.isEmpty {
                    let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
                    
                    // Find all occurrences of search text (case insensitive)
                    let content = item.content.lowercased()
                    let search = searchText.lowercased()
                    
                    var searchStartIndex = content.startIndex
                    while searchStartIndex < content.endIndex {
                        if let range = content.range(of: search, options: .caseInsensitive, range: searchStartIndex..<content.endIndex) {
                            // Convert Swift string range to NSRange for attributed string
                            let nsRange = NSRange(range, in: item.content)
                            
                            // Highlight the match with a bright yellow background and black text
                            mutableAttributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: nsRange)
                            mutableAttributedString.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
                            
                            // Move search start index to after this match
                            searchStartIndex = range.upperBound
                        } else {
                            break
                        }
                    }
                    
                    // Apply the attributed string to the content label
                    contentLabel.attributedStringValue = mutableAttributedString
                } else {
                    // No search text, just use the original rich text
                    contentLabel.attributedStringValue = attributedString
                }
                
                return
            } catch {
                print("Error displaying rich text: \(error)")
                // Fall back to plain text if there's an error
            }
        }
        
        // Handle plain text content (existing code)
        if searchText.isEmpty || item.isImage {
            // No search or image content, just set regular text
            contentLabel.stringValue = item.content
            
            // Apply text color
            applyTextColor()
            return
        }
        
        // Create attributed string for highlighting
        let attributedString = NSMutableAttributedString(string: item.content)
        
        // Apply the base text color based on appearance settings
        let prefs = Preferences.shared
        let textColor: NSColor
        
        if prefs.useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            textColor = isDark ? 
                (NSColor.fromHex("#FFFFFF") ?? NSColor.white) : 
                (NSColor.fromHex(prefs.textColor) ?? NSColor.labelColor)
        } else if prefs.darkMode {
            // Use dark mode colors
            textColor = NSColor.fromHex("#FFFFFF") ?? NSColor.white
        } else {
            // Use light mode colors
            textColor = NSColor.fromHex(prefs.textColor) ?? NSColor.labelColor
        }
        
        // Guard against empty content
        guard !item.content.isEmpty else {
            contentLabel.stringValue = ""
            return
        }
        
        attributedString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: item.content.count))
        
        // Find all occurrences of search text (case insensitive)
        let content = item.content.lowercased()
        let search = searchText.lowercased()
        
        // Use a more efficient approach for finding matches
        var searchStartIndex = content.startIndex
        while searchStartIndex < content.endIndex {
            if let range = content.range(of: search, options: .caseInsensitive, range: searchStartIndex..<content.endIndex) {
                // Convert Swift string range to NSRange for attributed string
                let nsRange = NSRange(range, in: item.content)
                
                // Highlight the match with a bright yellow background and black text
                attributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow, range: nsRange)
                attributedString.addAttribute(.foregroundColor, value: NSColor.black, range: nsRange)
                
                // Move search start index to after this match
                searchStartIndex = range.upperBound
            } else {
                break
            }
        }
        
        // Apply the attributed string to the content label on the main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.contentLabel != nil else { return }
            self.contentLabel.attributedStringValue = attributedString
        }
    }
    
    @objc func applyPreferences() {
        let prefs = Preferences.shared
        
        // Apply background color based on dark mode setting
        let backgroundColor: NSColor
        if prefs.useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            backgroundColor = isDark ? 
                (NSColor.fromHex("#333333") ?? NSColor.darkGray) : 
                (NSColor.fromHex(prefs.cardBackgroundColor) ?? NSColor.controlBackgroundColor)
        } else if prefs.darkMode {
            // Use dark mode colors
            backgroundColor = NSColor.fromHex("#333333") ?? NSColor.darkGray
        } else {
            // Use light mode colors
            backgroundColor = NSColor.fromHex(prefs.cardBackgroundColor) ?? NSColor.controlBackgroundColor
        }
        
        // Apply the background color with alpha
        layer?.backgroundColor = backgroundColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha)).cgColor
        
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
        
        // Update content with highlight if needed
        if !item.isImage && contentLabel != nil {
            updateContentWithHighlight()
        }
    }
    
    private func applyTextColor() {
        guard contentLabel != nil else { return }
        
        let prefs = Preferences.shared
        
        // Determine text color based on appearance settings
        let textColor: NSColor
        if prefs.useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            textColor = isDark ? 
                (NSColor.fromHex("#FFFFFF") ?? NSColor.white) : 
                (NSColor.fromHex(prefs.textColor) ?? NSColor.labelColor)
        } else if prefs.darkMode {
            // Use dark mode colors
            textColor = NSColor.fromHex("#FFFFFF") ?? NSColor.white
        } else {
            // Use light mode colors
            textColor = NSColor.fromHex(prefs.textColor) ?? NSColor.labelColor
        }
        
        contentLabel.textColor = textColor
    }
    
    @objc private func viewClicked() {
        // Get the current event and its click count
        let clickCount = NSApp.currentEvent?.clickCount ?? 0
        print("Click detected with clickCount: \(clickCount)")
        
        // If it's a double-click or more, let the double-click handler handle it
        if clickCount >= 2 {
            print("Detected multi-click in viewClicked, forwarding to viewDoubleClicked")
            viewDoubleClicked()
            return
        }
        
        // Notify that this card was clicked (for selection)
        NotificationCenter.default.post(name: NSNotification.Name("CardClicked"), object: item.id)
        
        // No longer perform paste action on single click - removed the paste functionality
    }
    
    // Add paste button click handler
    @objc private func pasteButtonClicked(_ sender: NSButton) {
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        // Log that we're handling a paste action
        print("Paste button clicked for item: \(item.id), isImage: \(item.isImage)")
        
        // Get the currently active application (where the cursor is positioned)
        let targetApp = NSWorkspace.shared.frontmostApplication
        print("Target application before paste: \(targetApp?.localizedName ?? "Unknown")")
        
        // Store the target app's process ID for later reactivation
        let targetAppPID = targetApp?.processIdentifier
        
        // Perform paste action (copy to clipboard)
        clickAction?(item)
        
        // Immediately activate the target application BEFORE closing our window
        // This is crucial to prevent Finder from becoming active
        if let pid = targetAppPID,
           let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            
            print("Activating target app before closing window: \(app.localizedName ?? "Unknown")")
            
            // Activate with stronger options
            if #available(macOS 14.0, *) {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            } else {
                app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            
            // Small delay to ensure activation takes effect
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Now close the window without animation
        if let window = self.window {
            print("Closing window after activating target app")
            
            // Disable animation when closing the window
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                window.orderOut(nil)
            }, completionHandler: nil)
        } else {
            print("Cannot close window (window is nil)")
        }
        
        // Immediately perform the paste operation without additional delays
        // This matches the behavior of the Enter/Return key
        print("Immediately performing paste operation")
        print("isRichText: \(self.item.isRichText), hasMultipleFormats: \(self.item.hasMultipleFormats), isImage: \(self.item.isImage)")
        
        // Use the appropriate paste method based on content type
        if self.item.isImage {
            // For images, use the specialized image paste method
            PasteManager.shared.paste(isRichText: false, isImage: true)
        } else if self.item.isRichText || self.item.hasMultipleFormats {
            // For rich text, use the specialized rich text paste method
            PasteManager.shared.paste(isRichText: true, isImage: false)
        } else {
            // For plain text, use the universal paste method
            PasteManager.shared.universalPaste()
        }
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
        
        // Get the currently active application (where the cursor is positioned)
        let targetApp = NSWorkspace.shared.frontmostApplication
        
        // Store the target app's process ID for later reactivation
        let targetAppPID = targetApp?.processIdentifier
        
        // Create context menu
        let menu = NSMenu()
        
        // Add "Copy" option
        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyItemClicked), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)
        
        // Add "Paste" option with custom handler to prevent Finder blinking
        let pasteItem = NSMenuItem(title: "Paste", action: nil, keyEquivalent: "")
        pasteItem.target = self
        
        // Use a custom action handler for the paste menu item
        pasteItem.action = #selector(pasteMenuItemClicked(_:))
        
        // Store the target app PID as represented object for later use
        if let pid = targetAppPID {
            pasteItem.representedObject = pid
        }
        
        menu.addItem(pasteItem)
        
        // Add appropriate edit/view option based on content type
        if item.isImage {
            let viewItem = NSMenuItem(title: "View Image", action: #selector(viewImageClicked), keyEquivalent: "")
            viewItem.target = self
            menu.addItem(viewItem)
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
    
    // Custom handler for paste menu item to prevent Finder blinking
    @objc private func pasteMenuItemClicked(_ sender: NSMenuItem) {
        // Get the target app PID from the represented object
        guard let pid = sender.representedObject as? pid_t else {
            // Fallback to regular paste button click if no PID is available
            pasteButtonClicked(NSButton())
            return
        }
        
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        // Log that we're handling a paste action
        print("Paste menu item clicked for item: \(item.id), isImage: \(item.isImage)")
        
        // Perform paste action (copy to clipboard)
        clickAction?(item)
        
        // Immediately activate the target application BEFORE closing our window
        // This is crucial to prevent Finder from becoming active
        if let app = NSRunningApplication(processIdentifier: pid),
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            
            print("Activating target app before closing window: \(app.localizedName ?? "Unknown")")
            
            // Activate with stronger options
            if #available(macOS 14.0, *) {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            } else {
                app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            
            // Small delay to ensure activation takes effect
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Now close the window without animation
        if let window = self.window {
            print("Closing window after activating target app")
            
            // Disable animation when closing the window
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                window.orderOut(nil)
            }, completionHandler: nil)
        } else {
            print("Cannot close window (window is nil)")
        }
        
        // Immediately perform the paste operation without additional delays
        // This matches the behavior of the Enter/Return key
        print("Immediately performing paste operation from menu item")
        
        // Use the appropriate paste method based on content type
        if self.item.isImage {
            // For images, use the specialized image paste method
            PasteManager.shared.paste(isRichText: false, isImage: true)
        } else if self.item.isRichText || self.item.hasMultipleFormats {
            // For rich text, use the specialized rich text paste method
            PasteManager.shared.paste(isRichText: true, isImage: false)
        } else {
            // For plain text, use the universal paste method
            PasteManager.shared.universalPaste()
        }
    }
    
    @objc private func copyItemClicked() {
        clickAction?(item)
    }
    
    @objc private func editItemClicked() {
        // Post notification to edit this item
        print("Posting EditClipboardItem notification for item: \(item.id)")
        
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            // Post the notification on the main thread to ensure it's processed correctly
            NotificationCenter.default.post(name: NSNotification.Name("EditClipboardItem"), object: self.item.id)
        }
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
                
                // Ensure the app is activated before opening the file
                NSApp.activate(ignoringOtherApps: true)
                
                // Open with default application (Preview on macOS)
                NSWorkspace.shared.open(tempFile)
                
                print("Opening image in Preview: \(tempFile.path)")
            }
        } catch {
            print("Error opening image: \(error)")
        }
    }
    
    @objc private func saveButtonClicked(_ sender: NSButton) {
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        guard item.isImage, item.getImage() != nil else { return }
        
        // Ensure the app is activated
        NSApp.activate(ignoringOtherApps: true)
        
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
    
    @objc private func saveTextButtonClicked(_ sender: NSButton) {
        // Prevent event propagation
        NSApp.preventWindowOrdering()
        
        guard !item.isImage else { return }
        
        // Ensure the app is activated
        NSApp.activate(ignoringOtherApps: true)
        
        // Create save menu
        let menu = NSMenu()
        
        // Add "Save as TXT" option
        let txtItem = NSMenuItem(title: "Save as TXT", action: #selector(saveAsTXT), keyEquivalent: "")
        txtItem.target = self
        menu.addItem(txtItem)
        
        // Add "Save as RTF" option
        let rtfItem = NSMenuItem(title: "Save as RTF", action: #selector(saveAsRTF), keyEquivalent: "")
        rtfItem.target = self
        menu.addItem(rtfItem)
        
        // Add "Save as DOC" option
        let docItem = NSMenuItem(title: "Save as DOC", action: #selector(saveAsDOC), keyEquivalent: "")
        docItem.target = self
        menu.addItem(docItem)
        
        // Show menu
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: sender)
    }
    
    @objc private func saveAsTXT() {
        saveText(fileExtension: "txt", fileType: "Text File")
    }
    
    @objc private func saveAsRTF() {
        saveText(fileExtension: "rtf", fileType: "Rich Text Format")
    }
    
    @objc private func saveAsDOC() {
        saveText(fileExtension: "doc", fileType: "Word Document")
    }
    
    // Helper method to get the window from the view hierarchy
    private func findParentWindow() -> NSWindow? {
        // Try to get window from view hierarchy
        var responder: NSResponder? = self
        while let nextResponder = responder?.nextResponder {
            if let window = nextResponder as? NSWindow {
                return window
            }
            responder = nextResponder
        }
        
        // If not found in responder chain, try to get from app's windows
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            return window
        }
        
        // If still not found, try to get the key window
        return NSApp.keyWindow
    }
    
    private func saveText(fileExtension: String, fileType: String) {
        guard !item.isImage else { return }
        
        print("Saving text as \(fileExtension) file...")
        
        // Ensure the app is activated
        NSApp.activate(ignoringOtherApps: true)
        
        // Create save panel
        let savePanel = NSSavePanel()
        
        // Use UTType instead of file extension strings
        if #available(macOS 11.0, *) {
            // Use modern UTType API
            switch fileExtension {
            case "txt":
                savePanel.allowedContentTypes = [UTType.plainText]
            case "rtf":
                savePanel.allowedContentTypes = [UTType.rtf]
            case "doc":
                if let docType = UTType(filenameExtension: "doc") {
                    savePanel.allowedContentTypes = [docType]
                } else {
                    // Use a more generic type as fallback
                    savePanel.allowedContentTypes = [UTType.text]
                }
            default:
                savePanel.allowedContentTypes = [UTType.plainText]
            }
        } else {
            // Fallback for older macOS versions
            print("Using older macOS API with allowedFileTypes")
            // Try to use UTType if available
            if #available(macOS 11.0, *) {
                if let utType = UTType(filenameExtension: fileExtension) {
                    savePanel.allowedContentTypes = [utType]
                } else {
                    // Last resort fallback
                    savePanel.allowedFileTypes = [fileExtension]
                }
            } else {
                savePanel.allowedFileTypes = [fileExtension]
            }
        }
        
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Text"
        savePanel.message = "Choose a location to save the text"
        savePanel.nameFieldStringValue = "clipboard_text"
        
        print("Showing save panel...")
        
        // Try to find the main window
        let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first
        print("Main window found: \(mainWindow != nil)")
        
        // Always use runModal as a fallback since it's more reliable
        print("Using runModal for save panel")
        let response = savePanel.runModal()
        print("Save panel response (runModal): \(response == .OK ? "OK" : "Cancel")")
        
        if response == .OK, let url = savePanel.url {
            print("Selected save location: \(url.path)")
            
            do {
                if fileExtension == "doc" {
                    print("Creating DOC file...")
                    
                    // Check if we have rich text data
                    if item.isRichText, let richTextData = item.richTextData {
                        // Create attributed string from rich text data
                        let attributedString = try NSAttributedString(
                            data: richTextData,
                            options: [.documentType: NSAttributedString.DocumentType.rtf],
                            documentAttributes: nil
                        )
                        
                        // Convert to DOC format
                        let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
                            .documentType: NSAttributedString.DocumentType.wordML,
                            .characterEncoding: String.Encoding.utf8.rawValue
                        ]
                        
                        // Write to file with document attributes
                        try attributedString.fileWrapper(from: NSRange(location: 0, length: attributedString.length),
                                                      documentAttributes: documentAttributes)
                            .write(to: url, options: .atomic, originalContentsURL: nil)
                    } else {
                        // No rich text data, create a plain text DOC
                        let attributedString = NSAttributedString(string: self.item.content)
                        let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
                            .documentType: NSAttributedString.DocumentType.wordML,
                            .characterEncoding: String.Encoding.utf8.rawValue
                        ]
                        
                        // Write to file with document attributes
                        try attributedString.fileWrapper(from: NSRange(location: 0, length: attributedString.length),
                                                      documentAttributes: documentAttributes)
                            .write(to: url, options: .atomic, originalContentsURL: nil)
                    }
                    print("DOC file saved successfully")
                } else if fileExtension == "rtf" {
                    print("Creating RTF file...")
                    
                    // Check if we have rich text data
                    if item.isRichText, let richTextData = item.richTextData {
                        // If we already have RTF data, write it directly
                        try richTextData.write(to: url)
                    } else {
                        // No rich text data, create a plain RTF
                        let attributedString = NSAttributedString(string: self.item.content)
                        let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
                            .documentType: NSAttributedString.DocumentType.rtf,
                            .characterEncoding: String.Encoding.utf8.rawValue
                        ]
                        
                        // Write to file with RTF attributes
                        let rtfData = try attributedString.data(from: NSRange(location: 0, length: attributedString.length),
                                                              documentAttributes: documentAttributes)
                        try rtfData.write(to: url)
                    }
                    print("RTF file saved successfully")
                } else {
                    print("Creating TXT file...")
                    // For TXT files, just write the plain text
                    try self.item.content.write(to: url, atomically: true, encoding: .utf8)
                    print("TXT file saved successfully")
                }
            } catch {
                print("Error saving file: \(error.localizedDescription)")
                // Show error alert
                let alert = NSAlert()
                alert.messageText = "Error Saving Text"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    private func saveImage(fileType: NSBitmapImageRep.FileType) {
        guard item.isImage, let image = item.getImage() else { return }
        
        print("Saving image as \(fileType == .png ? "PNG" : "JPEG") file...")
        
        // Ensure the app is activated
        NSApp.activate(ignoringOtherApps: true)
        
        // Create save panel
        let savePanel = NSSavePanel()
        // Use UTType instead of file extension strings
        if #available(macOS 11.0, *) {
            // Use modern UTType API
            if fileType == .png {
                if let pngType = UTType(filenameExtension: "png") {
                    print("Using UTType for png: \(pngType.identifier)")
                    savePanel.allowedContentTypes = [pngType]
                } else {
                    print("Falling back to allowedFileTypes for png")
                    savePanel.allowedFileTypes = ["png"]
                }
            } else {
                if let jpegType = UTType(filenameExtension: "jpeg") {
                    print("Using UTType for jpeg: \(jpegType.identifier)")
                    savePanel.allowedContentTypes = [jpegType]
                } else {
                    print("Falling back to allowedFileTypes for jpeg")
                    savePanel.allowedFileTypes = ["jpg", "jpeg"]
                }
            }
        } else {
            // Fallback for older macOS versions
            print("Using older macOS API with allowedFileTypes")
            // Try to use UTType if available
            if #available(macOS 11.0, *) {
                if fileType == .png {
                    savePanel.allowedContentTypes = [UTType.png]
                } else {
                    savePanel.allowedContentTypes = [UTType.jpeg]
                }
            } else {
                savePanel.allowedFileTypes = fileType == .png ? ["png"] : ["jpg", "jpeg"]
            }
        }
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.title = "Save Image"
        savePanel.message = "Choose a location to save the image"
        savePanel.nameFieldStringValue = "clipboard_image"
        
        print("Showing save panel for image...")
        
        // Try to find the main window
        let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first
        print("Main window found: \(mainWindow != nil)")
        
        // Always use runModal as a fallback since it's more reliable
        print("Using runModal for save panel")
        let response = savePanel.runModal()
        print("Save panel response (runModal): \(response == .OK ? "OK" : "Cancel")")
        
        if response == .OK, let url = savePanel.url {
            print("Selected save location: \(url.path)")
            
            // Convert image to data
            guard let tiffData = image.tiffRepresentation,
                  let bitmapImage = NSBitmapImageRep(data: tiffData) else {
                print("Failed to create bitmap image representation")
                return
            }
            
            let imageData: Data?
            if fileType == .png {
                print("Creating PNG data...")
                imageData = bitmapImage.representation(using: .png, properties: [:])
            } else {
                print("Creating JPEG data...")
                imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            }
            
            // Save to file
            if let imageData = imageData {
                do {
                    try imageData.write(to: url)
                    print("Image saved successfully")
                } catch {
                    print("Error saving image: \(error.localizedDescription)")
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Error Saving Image"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            } else {
                print("Failed to create image data")
            }
        }
    }
    
    @objc private func viewDoubleClicked() {
        // Get the current event and its click count
        let clickCount = NSApp.currentEvent?.clickCount ?? 0
        print("viewDoubleClicked called with clickCount: \(clickCount)")
        
        // Prevent event propagation to avoid beep sound
        NSApp.preventWindowOrdering()
        
        // Discard any pending mouse up events to prevent the single-click action from firing
        NSApp.discardEvents(matching: .leftMouseUp, before: nil)
        
        // First, notify that this card was clicked to update selection
        NotificationCenter.default.post(name: NSNotification.Name("CardClicked"), object: item.id)
        
        print("Double-click detected on item: \(item.id)")
        
        // For double-click, we want to edit text or view image, not paste
        if item.isImage {
            // Directly call the method to view the image
            print("Opening image preview for item: \(item.id)")
            viewImageClicked()
        } else {
            // Directly call the method to edit the text
            print("Opening edit dialog for item: \(item.id)")
            editItemClicked()
        }
        
        // Prevent the single-click action from being triggered
        NSApp.discardEvents(matching: .leftMouseUp, before: nil)
        
        // Ensure we don't process any more events for this double-click
        NSApp.discardEvents(matching: .leftMouseDown, before: nil)
    }
    
    override func mouseEntered(with event: NSEvent) {
        let prefs = Preferences.shared
        
        // Check if this is for a specific button
        if let userInfo = event.trackingArea?.userInfo as? [String: String],
           let buttonType = userInfo["button"] {
            // This is for a specific button
            if let button = event.trackingArea?.owner as? NSButton {
                if buttonType == "save" {
                    button.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
                } else if buttonType == "paste" {
                    button.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.2).cgColor
                }
            }
            return
        }
        
        // Apply hover effect based on appearance settings
        let backgroundColor: NSColor
        
        if prefs.useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            backgroundColor = isDark ? 
                (NSColor.fromHex("#444444") ?? NSColor.darkGray) : 
                (NSColor.fromHex(prefs.cardBackgroundColor) ?? NSColor.controlBackgroundColor)
        } else if prefs.darkMode {
            // Use dark mode colors
            backgroundColor = NSColor.fromHex("#444444") ?? NSColor.darkGray
        } else {
            // Use light mode colors
            backgroundColor = NSColor.fromHex(prefs.cardBackgroundColor) ?? NSColor.controlBackgroundColor
        }
        
        // Apply the background color with a slightly different alpha for hover effect
        layer?.backgroundColor = backgroundColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha * 0.8)).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        // Check if this is for a specific button
        if let userInfo = event.trackingArea?.userInfo as? [String: String],
           let _ = userInfo["button"] {
            // This is for a specific button
            if let button = event.trackingArea?.owner as? NSButton {
                button.layer?.backgroundColor = NSColor.clear.cgColor
            }
            return
        }
        
        applyPreferences()
    }
    
    private func updateSelectionAppearance() {
        // Update the appearance based on selection state
        if isSelected {
            // Get preferences
            let prefs = Preferences.shared
            
            // Create a selection indicator
            wantsLayer = true
            
            // Apply a highlighted background color based on appearance settings
            let backgroundColor: NSColor
            
            if prefs.useSystemAppearance {
                // Use system appearance
                let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                backgroundColor = isDark ? 
                    (NSColor.fromHex("#444444") ?? NSColor.darkGray) : 
                    (NSColor.fromHex(prefs.cardBackgroundColor) ?? NSColor.controlBackgroundColor)
            } else if prefs.darkMode {
                // Use dark mode colors
                backgroundColor = NSColor.fromHex("#444444") ?? NSColor.darkGray
            } else {
                // Use light mode colors
                backgroundColor = NSColor.fromHex(prefs.cardBackgroundColor) ?? NSColor.controlBackgroundColor
            }
            
            // Use a slightly brighter version of the background color
            let brighterColor = backgroundColor.blended(withFraction: 0.3, of: NSColor.white) ?? backgroundColor
            layer?.backgroundColor = brighterColor.withAlphaComponent(CGFloat(prefs.cardBackgroundAlpha)).cgColor
            
            // Add a border
            layer?.borderWidth = 2.0
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
        } else {
            // Reset to normal appearance
            applyPreferences()
            layer?.borderWidth = 0.0
        }
    }
    
    // Override mouseDown to better handle click events
    override func mouseDown(with event: NSEvent) {
        // Get the click count
        let clickCount = event.clickCount
        print("mouseDown detected with clickCount: \(clickCount)")
        
        // Handle based on click count
        if clickCount >= 2 {
            // This is a double-click or more
            print("Double-click detected in mouseDown for item: \(item.id)")
            viewDoubleClicked()
        } else {
            // This is a single click
            viewClicked()
        }
        
        // Let the event propagate to other handlers
        super.mouseDown(with: event)
    }
}

// Simple EditableTextView class for rich text editing
class EditableTextView: NSTextView {
    // Add properties for smooth scrolling
    private var isScrolling = false
    private var scrollTimer: Timer?
    private var targetScrollPosition: CGPoint?
    private var scrollAnimationDuration: TimeInterval = 0.3
    
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupTextColor()
        setupAppearanceObserver()
        setupTextContainer()
        setupScrollingBehavior()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextColor()
        setupAppearanceObserver()
        setupTextContainer()
        setupScrollingBehavior()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        scrollTimer?.invalidate()
    }
    
    private func setupAppearanceObserver() {
        // Register for appearance change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(effectiveAppearanceDidChange),
            name: NSWindow.didChangeBackingPropertiesNotification,
            object: nil
        )
        
        // Also observe effective appearance changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(effectiveAppearanceDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func effectiveAppearanceDidChange() {
        updateTextColorForEntireText()
    }
    
    // Add method to set up smooth scrolling behavior
    private func setupScrollingBehavior() {
        // Enable smooth scrolling
        enclosingScrollView?.scrollsDynamically = true
        
        // Set scroll elasticity
        enclosingScrollView?.hasVerticalScroller = true
        enclosingScrollView?.hasHorizontalScroller = false
        enclosingScrollView?.autohidesScrollers = true
        
        // Set scroll view appearance
        enclosingScrollView?.scrollerStyle = .overlay
        enclosingScrollView?.scrollerKnobStyle = .light
        
        // Enable responsive scrolling
        enclosingScrollView?.usesPredominantAxisScrolling = true
        
        // Set content insets for better appearance
        textContainerInset = NSSize(width: 8, height: 8)
    }
    
    // Override scrollWheel to implement smooth scrolling
    override func scrollWheel(with event: NSEvent) {
        guard let scrollView = enclosingScrollView else {
            super.scrollWheel(with: event)
            return
        }
        
        // For trackpad scrolling (with phase info), use the default behavior
        if event.phase != [] || event.momentumPhase != [] {
            super.scrollWheel(with: event)
            return
        }
        
        // For mouse wheel scrolling, implement smooth scrolling
        let deltaY = event.scrollingDeltaY
        
        // Calculate target scroll position
        let currentOffset = scrollView.contentView.bounds.origin
        let targetY = max(0, currentOffset.y + deltaY)
        let maxY = max(0, scrollView.documentView!.frame.height - scrollView.contentView.bounds.height)
        let clampedTargetY = min(targetY, maxY)
        
        // Set target position
        targetScrollPosition = CGPoint(x: currentOffset.x, y: clampedTargetY)
        
        // If not already scrolling, start the animation
        if !isScrolling {
            isScrolling = true
            
            // Invalidate existing timer if any
            scrollTimer?.invalidate()
            
            // Create a new timer for smooth animation
            scrollTimer = Timer.scheduledTimer(timeInterval: 1/60, target: self, selector: #selector(updateScroll), userInfo: nil, repeats: true)
            
            // Add the timer to the current run loop
            RunLoop.current.add(scrollTimer!, forMode: .common)
        }
        
        // We can't modify the event's phase, so we'll just handle it ourselves
        // and not call super.scrollWheel to prevent default scrolling
    }
    
    // Method to update scroll position during animation
    @objc private func updateScroll() {
        guard let scrollView = enclosingScrollView,
              let targetPosition = targetScrollPosition else {
            isScrolling = false
            scrollTimer?.invalidate()
            return
        }
        
        // Get current position
        let currentPosition = scrollView.contentView.bounds.origin
        
        // Calculate step size (easing function)
        let step = CGPoint(
            x: (targetPosition.x - currentPosition.x) * 0.3,
            y: (targetPosition.y - currentPosition.y) * 0.3
        )
        
        // Check if we're close enough to target
        if abs(step.y) < 0.5 {
            // We've reached the target (or close enough)
            scrollView.contentView.scroll(to: targetPosition)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            
            // Clean up
            isScrolling = false
            targetScrollPosition = nil
            scrollTimer?.invalidate()
            return
        }
        
        // Update position
        let newPosition = CGPoint(
            x: currentPosition.x + step.x,
            y: currentPosition.y + step.y
        )
        
        // Apply scroll
        scrollView.contentView.scroll(to: newPosition)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    private func setupTextColor() {
        // Set the default text color based on appearance
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDarkMode ? NSColor.white : NSColor.black
        let backgroundColor = isDarkMode ? NSColor.darkGray : NSColor.white
        
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        
        // Update typing attributes
        var attributes = self.typingAttributes
        attributes[.foregroundColor] = textColor
        self.typingAttributes = attributes
        
        // Apply to any existing text, but preserve existing color attributes
        if let textStorage = self.textStorage, textStorage.length > 0 {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            // Only apply color to text that doesn't have a color attribute
            textStorage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                if value == nil {
                    // Only apply color if there isn't already a color attribute
                    textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
                }
            }
            
            // Force layout update
            self.layoutManager?.ensureLayout(for: self.textContainer!)
            self.needsDisplay = true
        }
    }
    
    override func keyDown(with event: NSEvent) {
        // Check if it's Return/Enter key
        if event.keyCode == 36 {
            // Insert a line break instead of submitting the dialog
            self.insertText("\n", replacementRange: self.selectedRange)
        } else {
            super.keyDown(with: event)
        }
    }
    
    // Override to ensure text color is maintained when typing
    override func didChangeText() {
        super.didChangeText()
        
        // Apply the appropriate text color based on appearance
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDarkMode ? NSColor.white : NSColor.black
        
        // Get the typing attributes and update the foreground color
        let typingAttributes = self.typingAttributes
        var updatedAttributes = typingAttributes
        
        // Only set foreground color if it's not already set
        if typingAttributes[.foregroundColor] == nil {
            updatedAttributes[.foregroundColor] = textColor
            self.typingAttributes = updatedAttributes
        }
    }
    
    // Method to update text color for the entire text
    func updateTextColorForEntireText() {
        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDarkMode ? NSColor.white : NSColor.black
        let backgroundColor = isDarkMode ? NSColor.darkGray : NSColor.white
        
        // Update background color
        self.backgroundColor = backgroundColor
        
        // Update text color for all text, but preserve other attributes
        if let textStorage = self.textStorage, textStorage.length > 0 {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            
            // Instead of applying color to everything, only apply to text that doesn't have a color
            textStorage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                if value == nil {
                    // Only apply color if there isn't already a color attribute
                    textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
                }
            }
            
            // Force layout update
            self.layoutManager?.ensureLayout(for: self.textContainer!)
            self.needsDisplay = true
        }
        
        // Update typing attributes for new text
        var attributes = self.typingAttributes
        attributes[.foregroundColor] = textColor
        self.typingAttributes = attributes
    }
    
    private func setupTextContainer() {
        // Ensure text container is properly configured
        if let container = self.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: self.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }
        
        // Ensure layout manager is properly configured
        if let layoutManager = self.layoutManager {
            layoutManager.allowsNonContiguousLayout = false
            layoutManager.usesFontLeading = true
        }
    }
}

// Add this class before the HistoryWindowController class
class HistoryWindowController: NSWindowController {
    private var items: [ClipboardItem] = []
    private var filteredItems: [ClipboardItem] = [] // Add filtered items array
    private var searchText: String = "" // Add search text property
    private var headerView: NSView!
    private var scrollView: NSScrollView!
    private var containerView: NSView!
    private var tabView: NSSegmentedControl!
    private var clearAllButton: NSButton!
    private var searchField: NSSearchField! // Add search field property
    private var searchView: NSView! // Add search view property
    private var cardViews: [ClipboardItemCard] = []
    private var currentTab: Int = 0
    private var selectedItemIndex: Int = 0 // Track the currently selected item
    private var selectedCard: ClipboardItemCard? // Track the currently selected card
    private var targetApplication: NSRunningApplication? // Store the target application
    private var currentlyEditingItemId: UUID? // Track the item being edited
    private var nextItemToFocusAfterDeletion: UUID? // Track the next item to focus on after deletion
    private var currentEditTextView: EditableTextView? // Track the current text view being edited
    private var keyEventMonitor: Any?
    
    init(items: [ClipboardItem]) {
        print("HistoryWindowController init with \(items.count) items")
        for (index, item) in items.enumerated() {
            print("Window item \(index): \(item.content.prefix(30))...")
        }
        
        self.items = items
        self.filteredItems = items // Initialize filteredItems with all items
        
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
        
        // Apply window background color based on appearance settings
        if prefs.useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                window.backgroundColor = NSColor.fromHex("#222222") ?? NSColor.darkGray
            } else {
                window.backgroundColor = prefs.windowBackgroundNSColor()
            }
        } else if prefs.darkMode {
            // Use dark mode colors
            window.backgroundColor = NSColor.fromHex("#222222") ?? NSColor.darkGray
        } else {
            // Use light mode colors
            window.backgroundColor = prefs.windowBackgroundNSColor()
        }
        
        // Apply appearance settings
        if prefs.useSystemAppearance {
            window.appearance = nil // Use system appearance
        } else if prefs.darkMode {
            window.appearance = NSAppearance(named: .darkAqua)
        } else {
            window.appearance = NSAppearance(named: .aqua)
        }
        
        // Make the window appear on top of other applications
        window.level = .floating
        
        // Set window behavior to stay on top but not take focus
        window.collectionBehavior = [.moveToActiveSpace, .transient]
        window.isMovableByWindowBackground = true
        
        super.init(window: window)
        
        // Set the window delegate to self
        window.delegate = self
        
        setupUI()
        
        // Register for history updates
        NotificationCenter.default.addObserver(self, selector: #selector(historyUpdated), name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        
        // Register for preferences changes
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: NSNotification.Name("PreferencesChanged"), object: nil)
        
        // Register for card click notifications
        NotificationCenter.default.addObserver(self, selector: #selector(cardClicked(_:)), name: NSNotification.Name("CardClicked"), object: nil)
        
        // Register for edit item notifications
        NotificationCenter.default.addObserver(self, selector: #selector(editClipboardItem(_:)), name: NSNotification.Name("EditClipboardItem"), object: nil)
        
        // Register for delete item notifications
        NotificationCenter.default.addObserver(self, selector: #selector(handleItemDeletion(_:)), name: NSNotification.Name("DeleteClipboardItem"), object: nil)
        
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
        
        // Create header view with extra height to accommodate search field
        headerView = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 100, width: contentView.bounds.width, height: 100))
        headerView.autoresizingMask = [.width, .minYMargin]
        
        // Add title label
        let titleLabel = NSTextField(frame: NSRect(x: 20, y: 60, width: 200, height: 24))
        titleLabel.stringValue = "Clipboard"
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.textColor = NSColor.labelColor
        
        // Add tab view for All/Pinned tabs
        tabView = NSSegmentedControl(frame: NSRect(x: 200, y: 60, width: 150, height: 24))
        tabView.segmentCount = 2
        tabView.setLabel("All", forSegment: 0)
        tabView.setLabel("Pinned", forSegment: 1)
        tabView.selectedSegment = 0
        tabView.target = self
        tabView.action = #selector(tabChanged)
        tabView.segmentStyle = .texturedRounded
        tabView.autoresizingMask = [.minXMargin]
        
        // Add clear all button
        clearAllButton = NSButton(frame: NSRect(x: headerView.bounds.width - 100, y: 60, width: 80, height: 24))
        clearAllButton.title = "Clear all"
        clearAllButton.bezelStyle = .rounded
        clearAllButton.font = NSFont.systemFont(ofSize: 12)
        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllClicked)
        clearAllButton.autoresizingMask = [.minXMargin]
        
        // Add search field in the header (below the title/tabs)
        searchField = NSSearchField(frame: NSRect(x: 20, y: 20, width: headerView.bounds.width - 40, height: 24))
        searchField.placeholderString = "Search clipboard items..."
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchField.autoresizingMask = [.width]
        
        // Configure search field for better responsiveness
        if let searchFieldCell = searchField.cell as? NSSearchFieldCell {
            searchFieldCell.sendsSearchStringImmediately = true
            searchFieldCell.cancelButtonCell?.target = self
            searchFieldCell.cancelButtonCell?.action = #selector(searchCancelled)
        }
        
        // Add a notification observer for text changes to improve responsiveness
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(searchFieldTextDidChange),
            name: NSControl.textDidChangeNotification,
            object: searchField
        )
        
        headerView.addSubview(titleLabel)
        headerView.addSubview(tabView)
        headerView.addSubview(clearAllButton)
        headerView.addSubview(searchField)
        contentView.addSubview(headerView)
        
        // Create scroll view for cards (adjust for the taller header)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 100))
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
        // Store the current selected item ID if any
        let currentSelectedItemId = selectedCard?.item.id
        
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
        
        // Update the filtered items
        updateFilteredItems()
        
        // Get items to display based on current tab and search filter
        let displayItems: [ClipboardItem]
        if searchText.isEmpty {
            // No search filter, use tab filter only
            if currentTab == 0 {
                displayItems = items
            } else {
                displayItems = items.filter { $0.isPinned }
            }
        } else {
            // Use filtered items
            if currentTab == 0 {
                displayItems = filteredItems
            } else {
                displayItems = filteredItems.filter { $0.isPinned }
            }
        }
        
        // Check if the currently selected item is visible in the new tab
        if let currentSelectedItemId = currentSelectedItemId,
           displayItems.contains(where: { $0.id == currentSelectedItemId }) {
            // If the currently selected item is visible in the new tab, preserve its selection
            updateCardViews(preserveSelectedItemId: currentSelectedItemId)
        } else {
            // Otherwise, just update normally
            updateCardViews()
        }
    }
    
    private func updateCardViews(preserveSelectedItemId: UUID? = nil) {
        // Remove existing cards
        containerView.subviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        
        // Get preferences
        let prefs = Preferences.shared
        
        // Get items to display based on current tab and search filter
        var displayItems: [ClipboardItem] = []
        
        if searchText.isEmpty {
            // No search filter, use tab filter only
            if currentTab == 0 {
                displayItems = items
            } else {
                displayItems = items.filter { $0.isPinned }
            }
        } else {
            // Use filtered items
            if currentTab == 0 {
                displayItems = filteredItems
            } else {
                displayItems = filteredItems.filter { $0.isPinned }
            }
        }
        
        // Determine which item ID to preserve
        var itemIdToPreserve: UUID? = nil
        
        // First priority: explicitly provided ID (from direct calls)
        if let preserveId = preserveSelectedItemId, 
           displayItems.contains(where: { $0.id == preserveId }) {
            itemIdToPreserve = preserveId
        } 
        // Second priority: currently editing item
        else if let editingId = currentlyEditingItemId,
                displayItems.contains(where: { $0.id == editingId }) {
            itemIdToPreserve = editingId
        }
        // Third priority: currently selected item
        else if let currentId = selectedCard?.item.id,
                displayItems.contains(where: { $0.id == currentId }) {
            itemIdToPreserve = currentId
        }
        
        // Update the selected index based on the item to preserve
        if let idToPreserve = itemIdToPreserve,
           let preserveIndex = displayItems.firstIndex(where: { $0.id == idToPreserve }) {
            // Only update if different to avoid unnecessary jumps
            if selectedItemIndex != preserveIndex {
                selectedItemIndex = preserveIndex
            }
        } else if selectedCard == nil {
            // Only reset to the first item if we don't have a current selection
            selectedItemIndex = 0
        }
        
        // Clear the selected card reference since we're rebuilding the view
        selectedCard = nil as ClipboardItemCard?
        
        // Calculate container height based on number of items and preferences
        let containerHeight = CGFloat(displayItems.count * prefs.cardHeight + (displayItems.count - 1) * prefs.cardSpacing + 20)
        containerView.frame = NSRect(x: 0, y: 0, width: containerView.frame.width, height: max(containerHeight, scrollView.bounds.height))
        
        // Create card for each item - start from the top instead of bottom
        var yPosition = Int(containerView.frame.height) - prefs.cardHeight - 10
        
        for (index, item) in displayItems.enumerated() {
            // Add safety check for item content
            guard item.content.count > 0 || item.isImage else { continue }
            
            let cardFrame = NSRect(x: 20, y: CGFloat(yPosition), width: containerView.bounds.width - 40, height: CGFloat(prefs.cardHeight))
            let card = ClipboardItemCard(frame: cardFrame, item: item) { [weak self] selectedItem in
                self?.itemSelected(selectedItem)
            }
            card.autoresizingMask = [NSView.AutoresizingMask.width]
            
            // Set search text for highlighting - use empty string if nil to avoid crashes
            card.searchText = searchText
            
            // Set selection state for the card
            card.isSelected = (index == selectedItemIndex)
            if index == selectedItemIndex {
                selectedCard = card
            }
            
            containerView.addSubview(card)
            cardViews.append(card)
            yPosition -= (prefs.cardHeight + prefs.cardSpacing) // Card height + spacing
        }
        
        // Update window title with count
        if currentTab == 0 {
            window?.title = searchText.isEmpty ? "Clipboard (\(displayItems.count) items)" : "Search Results (\(displayItems.count) items)"
        } else {
            window?.title = searchText.isEmpty ? "Pinned Clipboard Items (\(displayItems.count) items)" : "Pinned Search Results (\(displayItems.count) items)"
        }
        
        // Scroll to selected item instead of top if we have a selection
        if selectedCard != nil {
            scrollToSelectedItem()
        } else {
            // Scroll to top after updating
            scrollToTop()
        }
    }
    
    @objc private func preferencesChanged() {
        // Update UI based on new preferences
        guard let window = self.window else { return }
        
        // Store the current selected item ID if any
        let currentSelectedItemId = selectedCard?.item.id
        
        // Get preferences
        let prefs = Preferences.shared
        
        // Apply window background color based on appearance settings
        if prefs.useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                window.backgroundColor = NSColor.fromHex("#222222") ?? NSColor.darkGray
            } else {
                window.backgroundColor = prefs.windowBackgroundNSColor()
            }
        } else if prefs.darkMode {
            // Use dark mode colors
            window.backgroundColor = NSColor.fromHex("#222222") ?? NSColor.darkGray
        } else {
            // Use light mode colors
            window.backgroundColor = prefs.windowBackgroundNSColor()
        }
        
        // Apply transparency if enabled
        if prefs.fullClipboardTransparency {
            window.isOpaque = false
            window.backgroundColor = window.backgroundColor?.withAlphaComponent(0.85)
        } else {
            window.isOpaque = true
        }
        
        // Apply appearance settings
        if prefs.useSystemAppearance {
            window.appearance = nil // Use system appearance
        } else if prefs.darkMode {
            window.appearance = NSAppearance(named: .darkAqua)
        } else {
            window.appearance = NSAppearance(named: .aqua)
        }
        
        // Force update all card views to apply new appearance settings
        for cardView in cardViews {
            cardView.applyPreferences()
        }
        
        // Update card views layout with preserved selection if possible
        if let currentSelectedItemId = currentSelectedItemId,
           items.contains(where: { $0.id == currentSelectedItemId }) {
            updateCardViews(preserveSelectedItemId: currentSelectedItemId)
        } else {
            updateCardViews()
        }
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
            // Store the current selected item ID if any
            let currentSelectedItemId = selectedCard?.item.id
            
            // Update the items list
            items = appDelegate.getClipboardHistory()
            
            // Update filtered items based on current search text
            // But don't call updateCardViews here, as it will be called below
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                filteredItems = items.filter { item in
                    if currentTab == 1 && !item.isPinned {
                        return false
                    }
                    
                    if item.isImage {
                        // For images, we can only search by timestamp or other metadata
                        return true
                    } else {
                        // Add safety check for empty content
                        guard !item.content.isEmpty else { return false }
                        return item.content.lowercased().contains(searchLower)
                    }
                }
            } else {
                filteredItems = items
            }
            
            // Check if we have a next item to focus on after deletion
            if let nextItemId = nextItemToFocusAfterDeletion, 
               items.contains(where: { $0.id == nextItemId }) {
                // If we have a next item to focus on and it exists, focus on it
                updateCardViews(preserveSelectedItemId: nextItemId)
                // Clear the next item to focus on
                nextItemToFocusAfterDeletion = nil
            }
            // If we don't have a next item to focus on, use the normal logic
            else if let currentSelectedItemId = currentSelectedItemId,
               items.contains(where: { $0.id == currentSelectedItemId }) {
                // If the currently selected item still exists, preserve its selection
                updateCardViews(preserveSelectedItemId: currentSelectedItemId)
            } else {
                // Otherwise, just update normally
                updateCardViews()
            }
        }
    }
    
    private func itemSelected(_ item: ClipboardItem) {
        // Copy the selected item to the clipboard
        copyItemToClipboard(item)
    }
    
    private func copyItemToClipboard(_ item: ClipboardItem) {
        print("===== HISTORY WINDOW COPY OPERATION START =====")
        print("Item selected: \(item.content)")
        print("Item ID: \(item.id)")
        print("Item isRichText: \(item.isRichText)")
        if item.isRichText {
            print("Item richTextData size: \(item.richTextData?.count ?? 0) bytes")
        }
        
        // Get the app delegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            // Store the target application before closing the window
            let targetApp = self.targetApplication
            print("Target application: \(targetApp?.localizedName ?? "Unknown")")
            
            // Always close the window
            if let window = self.window {
                print("Closing window after copying")
                window.close()
            } else {
                print("Cannot close window (window is nil)")
            }
            
            // Find the index of the item
            let itemIndex = items.firstIndex(where: { $0.id == item.id }) ?? 0
            print("Found item at index: \(itemIndex)")
            
            // Create a menu item with the appropriate tag
            let menuItem = NSMenuItem()
            menuItem.tag = itemIndex
            
            // Copy the item to clipboard
            print("Calling AppDelegate.copyItemToClipboard")
            appDelegate.copyItemToClipboard(menuItem)
            
            // Reactivate the target application with a more robust approach
            if let targetApp = targetApp {
                print("Reactivating target app: \(targetApp.localizedName ?? "Unknown")")
                
                // Use a slightly longer delay to ensure the window is fully closed
                // and the clipboard operation is complete before activating the target app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("Activating target application after delay")
                    // Activate the target application with options to bring it to front
                    if #available(macOS 14.0, *) {
                        // In macOS 14+, just use activate() as ignoringOtherApps has no effect
                        targetApp.activate(options: .activateAllWindows)
                    } else {
                        // For older macOS versions, use the previous API
                        targetApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    }
                    
                    // Give the app time to fully activate and restore focus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // If auto-paste is enabled, simulate paste keystroke
                        if Preferences.shared.autoPaste {
                            print("Auto-paste is enabled, simulating paste keystroke")
                            print("isRichText: \(item.isRichText), hasMultipleFormats: \(item.hasMultipleFormats), isImage: \(item.isImage)")
                            // Use the PasteManager directly for better control
                            PasteManager.shared.paste(isRichText: item.isRichText || item.hasMultipleFormats, isImage: item.isImage)
                        } else {
                            print("Auto-paste is disabled, not simulating paste keystroke")
                        }
                    }
                }
            } else {
                print("No target application to reactivate")
            }
        } else {
            print("ERROR: Could not get AppDelegate")
        }
        print("===== HISTORY WINDOW COPY OPERATION END =====")
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
        items = newItems
        updateFilteredItems()
        updateCardViews()
    }
    
    private func setupKeyboardMonitoring() {
        // Make the window first responder to receive key events, but not the search field
        // Add a small delay to ensure this happens after all other initialization
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.containerView)
        }
        
        // Remove any existing monitors to prevent duplicates
        if let existingMonitor = keyEventMonitor {
            NSEvent.removeMonitor(existingMonitor)
            keyEventMonitor = nil
        }
        
        // Set up local event monitor for keyboard events
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            
            // Handle key events
            if self.handleKeyEvent(event) {
                return nil // Event was handled, don't propagate
            }
            
            return event // Event wasn't handled, propagate normally
        }
        
        // Set up local event monitor for mouse events to prevent beep on double-click and triple-click
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            guard let self = self else { return event }
            
            // If it's a double-click or triple-click, we'll handle it in our gesture recognizers
            if event.clickCount >= 2 && event.type == .leftMouseDown {
                // Let our gesture recognizers handle it
                return event
            } else if event.clickCount >= 2 && event.type == .leftMouseUp {
                // Prevent the system beep by consuming the event
                return nil
            }
            
            // Check if the search field is active and the click is outside the search field
            if self.searchField != nil && 
               self.searchField.currentEditor() != nil && 
               event.type == .leftMouseDown {
                
                // Convert the event location to window coordinates
                let locationInWindow = event.locationInWindow
                
                // Convert window coordinates to search field coordinates
                let locationInSearchField = self.searchField.convert(locationInWindow, from: nil)
                
                // If the click is outside the search field, reset focus to the container view
                if !self.searchField.bounds.contains(locationInSearchField) {
                    self.window?.makeFirstResponder(self.containerView)
                }
            }
            
            return event // Not a multi-click, propagate normally
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check if search field is active
        if searchField != nil && searchField.currentEditor() != nil {
            // Let the search field handle the event, but check for Escape key
            if event.keyCode == 53 { // Escape key
                // Clear search and remove focus from search field
                searchField.stringValue = ""
                searchCancelled()
                window?.makeFirstResponder(containerView)
                return true
            }
            return false
        }
        
        // Skip handling if an alert is being shown (for editing)
        if NSApp.modalWindow != nil {
            return false
        }
        
        // Get filtered items based on current tab and search
        let displayItems: [ClipboardItem]
        if searchText.isEmpty {
            displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        } else {
            displayItems = currentTab == 0 ? filteredItems : filteredItems.filter { $0.isPinned }
        }
        
        // Handle arrow keys
        let keyCode = event.keyCode
        
        switch keyCode {
        case 125: // Down arrow
            if !displayItems.isEmpty {
                // Deselect current item
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                if selectedItemIndex < displayItems.count - 1 {
                    // Select next item
                    selectedItemIndex += 1
                } else {
                    // Wrap around to the top when at the bottom
                    selectedItemIndex = 0
                }
                
                // Select the new item
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible
                scrollToSelectedItem(isWrappingAround: selectedItemIndex == 0)
            }
            return true
            
        case 126: // Up arrow
            if !displayItems.isEmpty {
                // Deselect current item
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                if selectedItemIndex > 0 {
                    // Select previous item
                    selectedItemIndex -= 1
                } else {
                    // Wrap around to the bottom when at the top
                    selectedItemIndex = displayItems.count - 1
                }
                
                // Select the new item
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible
                scrollToSelectedItem(isWrappingAround: selectedItemIndex == displayItems.count - 1)
            }
            return true
            
        case 36: // Return/Enter key
            if !displayItems.isEmpty && selectedItemIndex < displayItems.count {
                let item = displayItems[selectedItemIndex]
                
                // For Return/Enter key, paste the item
                itemSelected(item)
            }
            return true
            
        case 53: // Escape key
            // If search field has text, clear it first
            if searchField != nil && !searchText.isEmpty {
                searchField.stringValue = ""
                searchCancelled()
                return true
            }
            
            // Otherwise close the window
            window?.close()
            return true
            
        case 49: // Space key
            if !displayItems.isEmpty && selectedItemIndex < displayItems.count {
                let item = displayItems[selectedItemIndex]
                
                // Show preview alert with the item's content
                let alert = NSAlert()
                alert.messageText = "Preview"
                
                // Log that space key was pressed for debugging
                print("Space key pressed - showing preview for item: \(item.id)")
                
                if item.isImage {
                    // For images, show dimensions or a placeholder message
                    if let image = item.getImage() {
                        alert.informativeText = "Image: \(Int(image.size.width))x\(Int(image.size.height)) pixels"
                    } else {
                        alert.informativeText = "Image preview not available"
                    }
                } else {
                    // Create a scroll view for the preview content
                    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
                    scrollView.hasVerticalScroller = true
                    scrollView.hasHorizontalScroller = false
                    scrollView.autohidesScrollers = true
                    scrollView.borderType = .bezelBorder
                    
                    // Enable smooth scrolling
                    scrollView.scrollsDynamically = true
                    scrollView.usesPredominantAxisScrolling = true
                    scrollView.scrollerStyle = .overlay
                    
                    // Create a text view for the content
                    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 390, height: 200))
                    textView.isEditable = false
                    textView.isSelectable = true
                    textView.font = NSFont.systemFont(ofSize: 12)
                    textView.textContainer?.containerSize = NSSize(width: 390, height: CGFloat.greatestFiniteMagnitude)
                    textView.textContainer?.widthTracksTextView = true
                    textView.isHorizontallyResizable = false
                    textView.isVerticallyResizable = true
                    textView.autoresizingMask = [.width]
                    
                    // Add padding around text
                    textView.textContainerInset = NSSize(width: 10, height: 10)
                    
                    // Set background color based on appearance
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    textView.backgroundColor = isDark ? NSColor(white: 0.15, alpha: 1.0) : NSColor(white: 0.98, alpha: 1.0)
                    
                    if item.isRichText, let richTextData = item.richTextData {
                        // Handle rich text content
                        do {
                            let attributedString = try NSAttributedString(
                                data: richTextData,
                                options: [.documentType: NSAttributedString.DocumentType.rtf],
                                documentAttributes: nil
                            )
                            
                            // Create a mutable copy to ensure we can modify attributes if needed
                            let mutableString = NSMutableAttributedString(attributedString: attributedString)
                            
                            // Check if the text has any color attributes
                            let fullRange = NSRange(location: 0, length: mutableString.length)
                            var hasColorAttribute = false
                            mutableString.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                                if value != nil {
                                    hasColorAttribute = true
                                }
                            }
                            
                            // If no explicit color is set, apply the current text color
                            if !hasColorAttribute {
                                print("No color attribute found, applying explicit text color")
                                // Use white color to ensure visibility in RTF documents
                                let textColor = NSColor.white
                                mutableString.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                            }
                            
                            textView.textStorage?.setAttributedString(mutableString)
                        } catch {
                            print("Error displaying rich text: \(error)")
                            // Fallback to plain text if there's an error
                            textView.string = item.content
                            // Ensure text color is maintained for plain text fallback
                            textView.textColor = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
                            // Force layout and display update
                            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                            textView.needsDisplay = true
                            print("Falling back to plain text due to error")
                        }
                    } else {
                        // Handle plain text content
                        textView.string = item.content
                        // Set text color for plain text
                        textView.textColor = isDark ? NSColor.white : NSColor.black
                    }
                    
                    scrollView.documentView = textView
                    
                    // Make sure the text view fills the scroll view
                    textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
                    textView.minSize = NSSize(width: 0, height: 0)
                    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                    textView.isVerticallyResizable = true
                    textView.isHorizontallyResizable = false
                    textView.autoresizingMask = [.width]
                    
                    // Set the scroll view as the accessory view
                    alert.accessoryView = scrollView
                }
                
                alert.addButton(withTitle: "Close")
                alert.window.minSize = NSSize(width: 400, height: 300) // Set minimum size for better readability
                
                // Set alert appearance to match system
                alert.window.appearance = NSApp.effectiveAppearance
                
                alert.beginSheetModal(for: self.window!) { _ in
                    // Ensure focus returns to the window after closing the preview
                    self.window?.makeFirstResponder(self.containerView)
                }
            }
            return true
            
        case 3: // F key
            if event.modifierFlags.contains(.command) {
                // Command+F to focus search field
                if searchField != nil {
                    window?.makeFirstResponder(searchField)
                    
                    // Select all text if there's any
                    if !searchField.stringValue.isEmpty {
                        searchField.currentEditor()?.selectAll(nil)
                    }
                    return true
                }
            }
            return false
            
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
        // Get filtered items based on current tab and search
        let displayItems: [ClipboardItem]
        if searchText.isEmpty {
            displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        } else {
            displayItems = currentTab == 0 ? filteredItems : filteredItems.filter { $0.isPinned }
        }
        
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
                        selectedCard = nil as ClipboardItemCard?
                    }
                }
                break
            }
        }
    }
    
    private func scrollToSelectedItem(isWrappingAround: Bool = false) {
        guard let selectedCard = selectedCard else { return }
        
        // Convert card frame to scroll view coordinates
        let cardFrameInScrollView = containerView.convert(selectedCard.frame, to: scrollView.contentView)
        
        // Check if the card is already visible in the current view
        let isCardVisible = scrollView.contentView.visibleRect.intersects(cardFrameInScrollView)
        
        if isWrappingAround {
            // For wrap-around scrolling, create a more sophisticated animation
            // First, determine if we're wrapping from top to bottom or bottom to top
            let isScrollingToBottom = selectedItemIndex == (searchText.isEmpty ? 
                (currentTab == 0 ? items.count - 1 : items.filter { $0.isPinned }.count - 1) : 
                (currentTab == 0 ? filteredItems.count - 1 : filteredItems.filter { $0.isPinned }.count - 1))
            
            // Create a two-step animation for smoother transition
            NSAnimationContext.runAnimationGroup({ context in
                // First step: quick fade out
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                
                // If scrolling to bottom, first scroll a bit more down (beyond content)
                // If scrolling to top, first scroll a bit more up (beyond content)
                let intermediatePoint: NSPoint
                if isScrollingToBottom {
                    // Scrolling to bottom - first go a bit beyond the top
                    intermediatePoint = NSPoint(x: 0, y: containerView.frame.height + 50)
                } else {
                    // Scrolling to top - first go a bit beyond the bottom
                    intermediatePoint = NSPoint(x: 0, y: -50)
                }
                
                scrollView.contentView.animator().scroll(intermediatePoint)
            }, completionHandler: {
                // Second step: scroll to the actual target with a nice animation
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.scrollView.contentView.animator().scrollToVisible(cardFrameInScrollView)
                }, completionHandler: nil)
            })
        } else if !isCardVisible {
            // Only scroll if the card is not already visible
            // Regular scrolling with simple animation
            NSAnimationContext.runAnimationGroup({ context in
                // Set animation duration - adjust this value for desired smoothness
                context.duration = 0.2
                // Use ease-in-ease-out timing function for smoother animation
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Animate the scroll
                scrollView.contentView.animator().scrollToVisible(cardFrameInScrollView)
            }, completionHandler: nil)
        }
        // If the card is already visible, don't scroll at all
    }
    
    @objc private func cardClicked(_ notification: Notification) {
        // Get the clicked item ID
        guard let clickedItemId = notification.object as? UUID else { return }
        
        // Get filtered items based on current tab and search
        let displayItems: [ClipboardItem]
        if searchText.isEmpty {
            displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        } else {
            displayItems = currentTab == 0 ? filteredItems : filteredItems.filter { $0.isPinned }
        }
        
        // Find the index of the clicked item
        if let index = displayItems.firstIndex(where: { $0.id == clickedItemId }) {
            // If clicking on the same item that's already selected, we still need to
            // update the selection state to ensure the card knows it's selected
            if index == selectedItemIndex {
                // Just ensure the card is marked as selected
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                return
            }
            
            // Deselect current item
            updateCardSelection(at: selectedItemIndex, isSelected: false)
            
            // Update selected index
            selectedItemIndex = index
            
            // Select the new item
            updateCardSelection(at: selectedItemIndex, isSelected: true)
        }
    }
    
    @objc private func editClipboardItem(_ notification: Notification) {
        print("===== EDIT ITEM START =====")
        // Get the item ID to edit
        guard let itemId = notification.object as? UUID else {
            print("Error: Invalid item ID in EditClipboardItem notification")
            print("===== EDIT ITEM FAILED =====")
            return
        }
        
        // Find the item in the items array
        guard let itemIndex = items.firstIndex(where: { $0.id == itemId }) else {
            print("Error: Could not find item with ID \(itemId) in items array")
            print("===== EDIT ITEM FAILED =====")
            return
        }
        
        // Set the currently editing item ID
        currentlyEditingItemId = itemId
        print("Starting to edit item with ID: \(itemId)")
        
        let item = items[itemIndex]
        print("Item content: \(item.content)")
        print("Item isRichText: \(item.isRichText)")
        if item.isRichText {
            print("Item richTextData size: \(item.richTextData?.count ?? 0) bytes")
        }
        
        // Ensure we're on the main thread for UI operations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                print("Self is nil in async block")
                print("===== EDIT ITEM FAILED =====")
                return
            }
            
            // If it's an image, just show the image viewer instead of edit dialog
            if item.isImage {
                print("Item is an image, opening in Preview")
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
                        
                        // Ensure the app is activated before opening the file
                        NSApp.activate(ignoringOtherApps: true)
                        
                        // Open with default application (Preview on macOS)
                        NSWorkspace.shared.open(tempFile)
                        
                        print("Opening image in Preview: \(tempFile.path)")
                    } else {
                        print("Error: Could not create image data for preview")
                    }
                } catch {
                    print("Error opening image: \(error)")
                }
                
                // Clear the currently editing item ID
                self.currentlyEditingItemId = nil
                print("===== EDIT ITEM COMPLETE (IMAGE) =====")
                return
            }
            
            print("Item is text, opening edit dialog")
            // For text items, show the edit dialog
            // Create an edit dialog
            let alert = NSAlert()
            alert.messageText = "Edit Clipboard Item"
            alert.informativeText = "Modify the text below:"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            
            // Create a scroll view to contain the text view for long content
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.borderType = .bezelBorder
            
            // Enable smooth scrolling
            scrollView.scrollsDynamically = true
            scrollView.usesPredominantAxisScrolling = true
            scrollView.scrollerStyle = .overlay
            
            // Add a subtle background color
            let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            scrollView.backgroundColor = isDarkMode ? NSColor(white: 0.15, alpha: 1.0) : NSColor(white: 0.98, alpha: 1.0)
            
            // Use a text view for better multiline editing
            let textContainer = NSTextContainer(containerSize: NSSize(width: scrollView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            let layoutManager = NSLayoutManager()
            let textStorage = NSTextStorage()
            
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)
            
            let textView = EditableTextView(frame: NSRect(x: 0, y: 0, width: scrollView.frame.width, height: scrollView.frame.height), textContainer: textContainer)
            
            // Store the text view in a property so it can be accessed if needed
            self.currentEditTextView = textView
            
            // Configure text view for rich text editing
            textView.isEditable = true
            textView.isSelectable = true
            textView.isRichText = true  // Always enable rich text editing
            textView.allowsUndo = true
            textView.font = NSFont.systemFont(ofSize: 14)
            
            // Add padding around text
            textView.textContainerInset = NSSize(width: 10, height: 10)
            
            // These settings are now handled when setting up the scroll view
            // textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
            // textView.textContainer?.widthTracksTextView = true
            // textView.isHorizontallyResizable = false
            // textView.isVerticallyResizable = true
            // textView.autoresizingMask = [.width]
            
            // Set text color based on window appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            textView.textColor = isDark ? .white : .black
            
            // Check if we have rich text data
            if item.isRichText, let richTextData = item.richTextData {
                print("Loading rich text data for editing")
                do {
                    // Create attributed string from rich text data
                    let attributedString = try NSAttributedString(
                        data: richTextData,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                    
                    print("Created attributed string from rich text data")
                    print("Attributed string length: \(attributedString.length)")
                    print("Attributed string plain text: \(attributedString.string)")
                    
                    // Set the attributed string to the text view
                    textView.textStorage?.setAttributedString(attributedString)
                    print("Loaded rich text data for editing")
                    
                    // Only apply text color to text that doesn't have color attributes
                    if let textStorage = textView.textStorage {
                        let fullRange = NSRange(location: 0, length: textStorage.length)
                        let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        let textColor = isDarkMode ? NSColor.white : NSColor.black
                        
                        // Only apply color to text that doesn't have a color attribute
                        textStorage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                            if value == nil {
                                // Only apply color if there isn't already a color attribute
                                textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
                            }
                        }
                    }
                    
                    // Force layout and display update
                    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                    textView.needsDisplay = true
                } catch {
                    print("Error displaying rich text in editor: \(error)")
                    // Fall back to plain text if there's an error
                    textView.string = item.content
                    // Ensure text color is maintained for plain text fallback
                    textView.textColor = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
                    print("Falling back to plain text due to error")
                }
            } else {
                // No rich text data, just set plain text
                textView.string = item.content
                // Ensure text color is maintained for plain text
                textView.textColor = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
                // Force layout and display update
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                textView.needsDisplay = true
                print("No rich text data, using plain text but enabling rich text editing")
            }
            
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            
            // Make sure the text view fills the scroll view
            textView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: scrollView.contentSize.height)
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            
            // Set the scroll view as the accessory view
            alert.accessoryView = scrollView
            
            // Ensure alert appears on top of other applications
            NSApp.activate(ignoringOtherApps: true)
            alert.window.level = .floating
            
            // Set window appearance to match system
            alert.window.appearance = NSApp.effectiveAppearance
            
            // Add observer for appearance changes to update text color
            let appearanceObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeBackingPropertiesNotification,
                object: alert.window,
                queue: .main
            ) { _ in
                // Update text color when appearance changes, but preserve rich text attributes
                if let textStorage = textView.textStorage {
                    let fullRange = NSRange(location: 0, length: textStorage.length)
                    let isDarkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    let textColor = isDarkMode ? NSColor.white : NSColor.black
                    
                    // Only apply color to text that doesn't have a color attribute
                    textStorage.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                        if value == nil {
                            // Only apply color if there isn't already a color attribute
                            textStorage.addAttribute(.foregroundColor, value: textColor, range: range)
                        }
                    }
                    
                    // Update background color
                    textView.backgroundColor = isDarkMode ? NSColor.darkGray : NSColor.white
                    
                    // Force layout update
                    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                    textView.needsDisplay = true
                }
            }
            
            // Make the alert window larger for better editing
            let window = alert.window
            let currentFrame = window.frame
            window.setFrame(NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y - 100, width: 550, height: currentFrame.height + 100), display: true)
            
            // Show the dialog
            let response = alert.runModal()
            
            // Remove the appearance observer
            NotificationCenter.default.removeObserver(appearanceObserver)
            
            // Clear the current edit text view reference
            defer {
                self.currentEditTextView = nil
            }
            
            if response == .alertFirstButtonReturn {
                print("User clicked Save")
                // User clicked Save
                var updatedContent: String
                var updatedRichTextData: Data? = nil
                
                // Always treat the content as rich text to preserve formatting
                print("Processing rich text edit")
                // Get the attributed string from the text view
                let attributedString = textView.attributedString()
                
                // Create a mutable copy to ensure we can modify attributes if needed
                let mutableString = NSMutableAttributedString(attributedString: attributedString)
                
                // Check if the text has any color attributes
                let fullRange = NSRange(location: 0, length: mutableString.length)
                var hasColorAttribute = false
                mutableString.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if value != nil {
                        hasColorAttribute = true
                    }
                }
                
                // If no explicit color is set, apply the current text color
                if !hasColorAttribute {
                    print("No color attribute found, applying explicit text color")
                    // Use white color to ensure visibility in RTF documents
                    let textColor = NSColor.white
                    mutableString.addAttribute(.foregroundColor, value: textColor, range: fullRange)
                }
                
                // Convert to plain text for the content field
                updatedContent = mutableString.string
                print("Updated content from rich text: \(updatedContent)")
                
                // Convert to RTF data for storage
                do {
                    // Use RTF document type to preserve all formatting
                    updatedRichTextData = try mutableString.data(
                        from: NSRange(location: 0, length: mutableString.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                    )
                    print("Created rich text data from edited content")
                    print("Rich text data size: \(updatedRichTextData?.count ?? 0) bytes")
                    
                    // Verify that the RTF data can be converted back to the same plain text
                    let verifiedAttributedString = try NSAttributedString(
                        data: updatedRichTextData!,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                    let verifiedPlainText = verifiedAttributedString.string
                    
                    if verifiedPlainText != updatedContent {
                        print("WARNING: Plain text from RTF doesn't match expected content")
                        print("Expected: \(updatedContent)")
                        print("Got from RTF: \(verifiedPlainText)")
                        
                        // Use the verified plain text to ensure consistency
                        updatedContent = verifiedPlainText
                        print("Updated content to match RTF data: \(updatedContent)")
                    } else {
                        print("Verified plain text matches RTF content")
                    }
                } catch {
                    print("Error converting rich text to data: \(error)")
                    
                    // Fallback to plain text if RTF conversion fails
                    updatedContent = textView.string
                    print("Falling back to plain text due to RTF conversion error: \(updatedContent)")
                }
                
                // IMPORTANT: Store the item ID that's being edited in a local variable
                // to ensure it's not affected by any other operations
                let editingItemId = itemId
                print("Saving edits for item with ID: \(editingItemId)")
                
                // First, register for the notification
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.handleItemUpdated(_:)),
                    name: NSNotification.Name("ClipboardHistoryUpdated"),
                    object: nil
                )
                
                // Store the ID of the item being edited for use in the notification handler
                self.currentlyEditingItemId = editingItemId
                
                // Update the item in the clipboard manager
                var userInfo: [String: Any] = ["itemId": editingItemId, "content": updatedContent]
                
                // Always include rich text data if available
                if let richTextData = updatedRichTextData {
                    userInfo["richTextData"] = richTextData
                    print("Including rich text data in update notification")
                    print("Rich text data size: \(richTextData.count) bytes")
                } else {
                    print("No rich text data to include in update notification")
                }
                
                print("Posting UpdateClipboardItem notification")
                NotificationCenter.default.post(
                    name: NSNotification.Name("UpdateClipboardItem"),
                    object: nil,
                    userInfo: userInfo
                )
                print("===== EDIT ITEM COMPLETE (SAVED) =====")
            } else {
                // User clicked Cancel, clear the currently editing item ID
                self.currentlyEditingItemId = nil
                print("User clicked Cancel")
                print("===== EDIT ITEM CANCELLED =====")
            }
            
            // Ensure we're still using accessory activation policy
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    @objc private func handleItemUpdated(_ notification: Notification) {
        // Remove this observer immediately to prevent multiple calls
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name("ClipboardHistoryUpdated"),
            object: nil
        )
        
        // Get the ID of the item that was being edited
        if let editingItemId = currentlyEditingItemId {
            print("History updated after editing item: \(editingItemId)")
            
            // Update the UI with the edited item selected
            DispatchQueue.main.async { [weak self] in
                // Focus on the item we just edited
                print("Focusing on edited item with ID: \(editingItemId)")
                self?.updateCardViews(preserveSelectedItemId: editingItemId)
                
                // Clear the currently editing item ID
                self?.currentlyEditingItemId = nil
            }
        }
    }
    
    @objc private func searchTextChanged(_ sender: NSSearchField) {
        // Cancel any previous delayed searches
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performSearch(_:)), object: nil)
        
        // If the search field is empty, clear results immediately
        if sender.stringValue.isEmpty {
            searchText = ""
            filteredItems = items
            updateCardViews()
            
            // Hide any loading indicators
            showSearchLoading(false)
            return
        }
        
        // Otherwise, debounce the search with a short delay
        // Use a copy of the search field to avoid potential memory issues
        let searchFieldCopy = sender
        perform(#selector(performSearch(_:)), with: searchFieldCopy, afterDelay: 0.2)
    }
    
    @objc private func performSearch(_ sender: NSSearchField) {
        // Remove the unnecessary nil check for sender (it's non-optional)
        
        let newSearchText = sender.stringValue
        
        // Add safety check for empty search text
        if newSearchText.isEmpty {
            // Store the current selected item ID if any
            let currentSelectedItemId = selectedCard?.item.id
            
            searchText = ""
            filteredItems = items
            
            // Preserve selection if possible
            if let currentSelectedItemId = currentSelectedItemId,
               items.contains(where: { $0.id == currentSelectedItemId }) {
                updateCardViews(preserveSelectedItemId: currentSelectedItemId)
            } else {
                updateCardViews()
            }
            
            showSearchLoading(false)
            return
        }
        
        // Only update if the search text has actually changed
        if searchText != newSearchText {
            searchText = newSearchText
            updateFilteredItems()
        }
    }
    
    private func updateFilteredItems() {
        if searchText.isEmpty {
            filteredItems = items
            DispatchQueue.main.async { [weak self] in
                // Preserve current selection if possible
                if let self = self, let currentSelectedItemId = self.selectedCard?.item.id,
                   self.items.contains(where: { $0.id == currentSelectedItemId }) {
                    self.updateCardViews(preserveSelectedItemId: currentSelectedItemId)
                } else {
                    self?.updateCardViews()
                }
            }
            return
        }
        
        // Show loading indicator
        showSearchLoading(true)
        
        // Use a background queue for filtering to avoid UI freezes
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            let searchLower = self.searchText.lowercased()
            
            // Add safety check for empty search text
            if searchLower.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.filteredItems = self.items
                    
                    // Preserve current selection if possible
                    if let currentSelectedItemId = self.selectedCard?.item.id,
                       self.items.contains(where: { $0.id == currentSelectedItemId }) {
                        self.updateCardViews(preserveSelectedItemId: currentSelectedItemId)
                    } else {
                        self.updateCardViews()
                    }
                    
                    self.showSearchLoading(false)
                }
                return
            }
            
            // Store the current selected item ID before filtering
            let currentSelectedItemId = self.selectedCard?.item.id
            
            let filtered = self.items.filter { item in
                if self.currentTab == 1 && !item.isPinned {
                    return false
                }
                
                if item.isImage {
                    // For images, we can only search by timestamp or other metadata
                    return true
                } else {
                    // Add safety check for empty content
                    guard !item.content.isEmpty else { return false }
                    return item.content.lowercased().contains(searchLower)
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.filteredItems = filtered
                
                // Check if the currently selected item is in the filtered results
                if let currentSelectedItemId = currentSelectedItemId,
                   filtered.contains(where: { $0.id == currentSelectedItemId }) {
                    // If the currently selected item is in the filtered results, preserve its selection
                    self.updateCardViews(preserveSelectedItemId: currentSelectedItemId)
                } else {
                    // Otherwise, just update normally
                    self.updateCardViews()
                }
                
                // Hide loading indicator
                self.showSearchLoading(false)
            }
        }
    }
    
    private func showSearchLoading(_ isLoading: Bool) {
        // Only proceed if search field exists
        guard let searchField = searchField else { return }
        
        if isLoading {
            // Add a small activity indicator next to the search field
            if searchField.subviews.first(where: { $0 is NSProgressIndicator }) == nil {
                let activityIndicator = NSProgressIndicator(frame: NSRect(x: searchField.bounds.width - 30, y: 4, width: 16, height: 16))
                activityIndicator.style = .spinning
                activityIndicator.isIndeterminate = true
                activityIndicator.controlSize = .small
                activityIndicator.isDisplayedWhenStopped = false
                activityIndicator.autoresizingMask = [.minXMargin]
                activityIndicator.startAnimation(nil)
                searchField.addSubview(activityIndicator)
            }
        } else {
            // Remove the activity indicator
            searchField.subviews.forEach { subview in
                if let indicator = subview as? NSProgressIndicator {
                    indicator.stopAnimation(nil)
                    indicator.removeFromSuperview()
                }
            }
        }
    }
    
    @objc private func searchCancelled() {
        // This is called when the user clicks the X button in the search field
        // Store the current selected item ID if any
        let currentSelectedItemId = selectedCard?.item.id
        
        searchText = ""
        searchField.stringValue = ""
        filteredItems = items
        
        // Preserve selection if possible
        if let currentSelectedItemId = currentSelectedItemId,
           items.contains(where: { $0.id == currentSelectedItemId }) {
            updateCardViews(preserveSelectedItemId: currentSelectedItemId)
        } else {
            updateCardViews()
        }
        
        // Reset focus to the container view
        window?.makeFirstResponder(containerView)
    }
    
    @objc private func searchFieldTextDidChange(_ notification: Notification) {
        // This is called for every keystroke in the search field
        // It's more responsive than waiting for the action to be triggered
        if let searchField = notification.object as? NSSearchField {
            searchTextChanged(searchField)
        }
    }
    
    // Add this new method to handle item deletion
    @objc private func handleItemDeletion(_ notification: Notification) {
        // Get the item ID being deleted
        guard let itemId = notification.object as? UUID else { return }
        
        // Get the current display items based on tab and search filter
        let displayItems: [ClipboardItem]
        if searchText.isEmpty {
            displayItems = currentTab == 0 ? items : items.filter { $0.isPinned }
        } else {
            displayItems = currentTab == 0 ? filteredItems : filteredItems.filter { $0.isPinned }
        }
        
        // Find the index of the item being deleted
        if let currentIndex = displayItems.firstIndex(where: { $0.id == itemId }) {
            // Determine the next item to focus on
            if currentIndex < displayItems.count - 1 {
                // If not the last item, focus on the next item
                nextItemToFocusAfterDeletion = displayItems[currentIndex + 1].id
                print("Will focus on next item: \(nextItemToFocusAfterDeletion!)")
            } else if displayItems.count > 1 {
                // If it's the last item and there are other items, focus on the first item
                nextItemToFocusAfterDeletion = displayItems[0].id
                print("Will focus on first item: \(nextItemToFocusAfterDeletion!)")
            } else {
                // If it's the only item, there's nothing to focus on
                nextItemToFocusAfterDeletion = nil
                print("No item to focus on after deletion")
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        // Clean up any resources
        
        // Remove the event monitor
        if let keyEventMonitor = keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
        
        // ... existing code ...
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

// MARK: - NSWindowDelegate
extension HistoryWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        // No super call needed
        
        // Ensure the window's first responder is set to the containerView
        // This is crucial for keyboard shortcuts like space to work properly
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.containerView)
        }
    }
} 
