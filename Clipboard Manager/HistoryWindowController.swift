import Cocoa
import UserNotifications
import ApplicationServices
import UniformTypeIdentifiers

class ClipboardItemCard: NSView {
    private var contentLabel: NSTextField!
    private var imageView: NSImageView?
    private var pinButton: NSButton!
    private var menuButton: NSButton!
    private var saveButton: NSButton?
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
            
            // Add format indicator for images
            addFormatIndicator("Image")
            
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
        } else {
            // Setup text label for text content
            contentLabel = NSTextField(frame: NSRect(x: 16, y: 16, width: frame.width - 80, height: frame.height - 32))
            contentLabel.isEditable = false
            contentLabel.isBordered = false
            contentLabel.drawsBackground = false
            contentLabel.cell?.wraps = true
            contentLabel.cell?.isScrollable = true
            contentLabel.cell?.truncatesLastVisibleLine = true
            contentLabel.autoresizingMask = [.width, .height]
            contentLabel.font = NSFont.systemFont(ofSize: 14)
            contentLabel.allowsEditingTextAttributes = true
            contentLabel.preferredMaxLayoutWidth = frame.width - 80
            
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
            clickGesture.delaysPrimaryMouseButtonEvents = true
            contentLabel.addGestureRecognizer(clickGesture)
            
            // Add double-click gesture for editing
            let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(viewDoubleClicked))
            doubleClickGesture.numberOfClicksRequired = 2
            doubleClickGesture.delaysPrimaryMouseButtonEvents = true
            contentLabel.addGestureRecognizer(doubleClickGesture)
            
            // Make sure double-click takes precedence
            doubleClickGesture.delaysPrimaryMouseButtonEvents = true
            
            // Add save button for text items (similar to image items)
            saveButton = NSButton(frame: NSRect(x: frame.width - 90, y: frame.height - 30, width: 24, height: 24))
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
        // Check if this is part of a double-click sequence
        if NSApp.currentEvent?.clickCount ?? 0 > 1 {
            // This is part of a double-click, let the double-click handler handle it
            return
        }
        
        // Get the current selection state before notifying
        let wasSelected = isSelected
        
        // Notify that this card was clicked (for selection)
        NotificationCenter.default.post(name: NSNotification.Name("CardClicked"), object: item.id)
        
        // If the item was already selected before this click, then perform the paste action
        if wasSelected {
            // Second click on already selected item - copy to clipboard and paste
            clickAction?(item)
        }
        // First click just selects the item (handled by the CardClicked notification)
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
                if let txtType = UTType(filenameExtension: "txt") {
                    print("Using UTType for txt: \(txtType.identifier)")
                    savePanel.allowedContentTypes = [txtType]
                } else {
                    print("Falling back to allowedFileTypes for txt")
                    savePanel.allowedFileTypes = ["txt"]
                }
            case "rtf":
                if let rtfType = UTType(filenameExtension: "rtf") {
                    print("Using UTType for rtf: \(rtfType.identifier)")
                    savePanel.allowedContentTypes = [rtfType]
                } else {
                    print("Falling back to allowedFileTypes for rtf")
                    savePanel.allowedFileTypes = ["rtf"]
                }
            case "doc":
                if let docType = UTType(filenameExtension: "doc") {
                    print("Using UTType for doc: \(docType.identifier)")
                    savePanel.allowedContentTypes = [docType]
                } else {
                    print("Falling back to allowedFileTypes for doc")
                    savePanel.allowedFileTypes = ["doc"]
                }
            default:
                if let txtType = UTType(filenameExtension: "txt") {
                    print("Using UTType for default txt: \(txtType.identifier)")
                    savePanel.allowedContentTypes = [txtType]
                } else {
                    print("Falling back to allowedFileTypes for default txt")
                    savePanel.allowedFileTypes = ["txt"]
                }
            }
        } else {
            // Fallback for older macOS versions
            print("Using older macOS API with allowedFileTypes")
            savePanel.allowedFileTypes = [fileExtension]
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
            savePanel.allowedFileTypes = fileType == .png ? ["png"] : ["jpg", "jpeg"]
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
        
        // Check if this is for a specific button
        if let userInfo = event.trackingArea?.userInfo as? [String: String],
           let buttonType = userInfo["button"], buttonType == "save" {
            // This is for the save button
            if let button = event.trackingArea?.owner as? NSButton {
                button.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
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
           let buttonType = userInfo["button"], buttonType == "save" {
            // This is for the save button
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
}

// Add this class before the HistoryWindowController class
class EditableTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        // Check if it's Return/Enter key
        if event.keyCode == 36 {
            // Insert a line break instead of submitting the dialog
            self.insertText("\n", replacementRange: self.selectedRange)
        } else {
            super.keyDown(with: event)
        }
    }
}

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
        
        // Update the card views
        updateFilteredItems()
        updateCardViews()
    }
    
    private func updateCardViews() {
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
        
        // Reset selected item index to the most recent item (top item)
        selectedItemIndex = 0
        selectedCard = nil
        
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
        
        // Scroll to top after updating
        scrollToTop()
    }
    
    @objc private func preferencesChanged() {
        // Update UI based on new preferences
        guard let window = self.window else { return }
        
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
        
        // Update card views layout
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
            
            // Update filtered items based on current search text
            updateFilteredItems()
            
            updateCardViews()
        }
    }
    
    private func itemSelected(_ item: ClipboardItem) {
        // Copy the selected item to the clipboard
        copyItemToClipboard(item)
    }
    
    private func copyItemToClipboard(_ item: ClipboardItem) {
        print("Item selected: \(item.content.prefix(30))...")
        
        // Get the app delegate
        if let appDelegate = NSApp.delegate as? AppDelegate {
            // Store the target application before closing the window
            let targetApp = self.targetApplication
            
            // Close the window first
            if let window = self.window, Preferences.shared.closeAfterCopy {
                window.close()
            }
            
            // Find the index of the item
            let itemIndex = items.firstIndex(where: { $0.id == item.id }) ?? 0
            
            // Create a menu item with the appropriate tag
            let menuItem = NSMenuItem()
            menuItem.tag = itemIndex
            
            // Copy the item to clipboard
            appDelegate.copyItemToClipboard(menuItem)
            
            // Reactivate the target application with a more robust approach
            if let targetApp = targetApp {
                print("Reactivating target app: \(targetApp.localizedName ?? "Unknown")")
                
                // Use a slightly longer delay to ensure the window is fully closed
                // and the clipboard operation is complete before activating the target app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Activate the target application with options to bring it to front
                    targetApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    
                    // Give the app time to fully activate and restore focus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // If auto-paste is enabled, simulate paste keystroke
                        if Preferences.shared.autoPaste {
                            // Use the PasteManager directly for better control
                            PasteManager.shared.paste(isRichText: item.isRichText || item.hasMultipleFormats)
                        }
                    }
                }
            }
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
            if selectedItemIndex < displayItems.count - 1 {
                // Deselect current item
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                // Select next item
                selectedItemIndex += 1
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible
                scrollToSelectedItem()
            } else if !displayItems.isEmpty {
                // Wrap around to the top when at the bottom
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                // Select first item
                selectedItemIndex = 0
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible with special wrap-around animation
                scrollToSelectedItem(isWrappingAround: true)
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
            } else if !displayItems.isEmpty {
                // Wrap around to the bottom when at the top
                updateCardSelection(at: selectedItemIndex, isSelected: false)
                
                // Select last item
                selectedItemIndex = displayItems.count - 1
                updateCardSelection(at: selectedItemIndex, isSelected: true)
                
                // Ensure the selected item is visible with special wrap-around animation
                scrollToSelectedItem(isWrappingAround: true)
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
                        selectedCard = nil
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
        } else {
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
        let textView = EditableTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
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
        // Add safety check for nil sender
        guard sender != nil else { return }
        
        let newSearchText = sender.stringValue
        
        // Add safety check for empty search text
        if newSearchText.isEmpty {
            searchText = ""
            filteredItems = items
            updateCardViews()
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
                self?.updateCardViews()
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
                    self.updateCardViews()
                    self.showSearchLoading(false)
                }
                return
            }
            
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
                self.updateCardViews()
                
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
        searchText = ""
        searchField.stringValue = ""
        filteredItems = items
        updateCardViews()
        
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
        // Ensure the search field doesn't get focus automatically
        // Set focus to the container view instead
        // Add a small delay to ensure this happens after all other initialization
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self.containerView)
        }
    }
} 
