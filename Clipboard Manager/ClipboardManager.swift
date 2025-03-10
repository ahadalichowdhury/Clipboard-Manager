import Cocoa
import UserNotifications

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    var content: String
    let timestamp: Date
    var isPinned: Bool
    var imageData: Data?
    var richTextData: Data?
    var pasteboardItems: [PasteboardItemData]?
    
    var isImage: Bool {
        return imageData != nil
    }
    
    var isRichText: Bool {
        return richTextData != nil
    }
    
    var hasMultipleFormats: Bool {
        return pasteboardItems != nil && pasteboardItems!.count > 0
    }
    
    init(content: String, imageData: Data? = nil, richTextData: Data? = nil, pasteboardItems: [PasteboardItemData]? = nil, isPinned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.imageData = imageData
        self.richTextData = richTextData
        self.pasteboardItems = pasteboardItems
        self.timestamp = Date()
        self.isPinned = isPinned
    }
    
    func getImage() -> NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }
    
    // Custom encoding for Codable
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, isPinned, imageData, richTextData, pasteboardItems
    }
}

// Structure to store pasteboard item data for multiple formats
struct PasteboardItemData: Codable {
    let type: String
    let data: Data
    
    init(type: NSPasteboard.PasteboardType, data: Data) {
        self.type = type.rawValue
        self.data = data
    }
}

class ClipboardManager {
    private var history: [ClipboardItem] = []
    private var lastContent: String = ""
    private var lastImageData: Data?
    private var lastRichTextData: Data?
    private var timer: Timer?
    private let historyFilePath: URL
    private var notificationsEnabled = false
    private var ignoreNextClipboardChange = false
    
    // Common pasteboard types to capture
    private let commonPasteboardTypes: [NSPasteboard.PasteboardType] = [
        .rtf,
        .rtfd,
        .html,
        .string,
        .tiff,
        .png,
        .pdf,
        .fileURL,
        .URL
    ]
    
    init() {
        print("Initializing ClipboardManager...")
        
        // Get the application support directory
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipboardDir = appSupportDir.appendingPathComponent("ClipboardManager", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: clipboardDir, withIntermediateDirectories: true)
        
        // Set history file path
        historyFilePath = clipboardDir.appendingPathComponent("history.json")
        print("History file path: \(historyFilePath.path)")
        
        // Request notification permission
        requestNotificationPermission()
        
        // Load history from file
        loadHistory()
        
        print("Clipboard history loaded with \(history.count) items")
        for (index, item) in history.enumerated() {
            print("Item \(index): \(item.content.prefix(30))... Pinned: \(item.isPinned) IsImage: \(item.isImage) IsRichText: \(item.isRichText)")
        }
        
        // Register for notifications
        NotificationCenter.default.addObserver(self, selector: #selector(clearHistory), name: NSNotification.Name("ClearClipboardHistory"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(togglePinItem(_:)), name: NSNotification.Name("TogglePinClipboardItem"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(deleteItem(_:)), name: NSNotification.Name("DeleteClipboardItem"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: NSNotification.Name("PreferencesChanged"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ignoreNextChange), name: NSNotification.Name("IgnoreNextClipboardChange"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateItem(_:)), name: NSNotification.Name("UpdateClipboardItem"), object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func requestNotificationPermission() {
        // Check if we're running from a proper bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("Not running from a proper bundle, notifications disabled")
            notificationsEnabled = false
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.notificationsEnabled = granted
                if let error = error {
                    print("Notification permission error: \(error)")
                }
                
                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied")
                }
            }
        }
    }
    
    @objc private func preferencesChanged() {
        // Check if we need to trim history based on new max history items setting
        let prefs = Preferences.shared
        
        // Enforce the max history limit (accounting for pinned items)
        let pinnedItems = history.filter { $0.isPinned }
        let unpinnedItems = history.filter { !$0.isPinned }
        
        // Calculate how many unpinned items we can keep
        let maxUnpinnedItems = max(0, prefs.maxHistoryItems - pinnedItems.count)
        
        // If we have more unpinned items than allowed, remove the oldest ones
        if unpinnedItems.count > maxUnpinnedItems {
            // Sort unpinned items by timestamp (newest first)
            let sortedUnpinnedItems = unpinnedItems.sorted { $0.timestamp > $1.timestamp }
            
            // Keep only the newest maxUnpinnedItems
            let itemsToKeep = sortedUnpinnedItems.prefix(maxUnpinnedItems)
            
            // Create a set of IDs to keep for efficient lookup
            let idsToKeep = Set(itemsToKeep.map { $0.id })
            
            // Remove items that are not in the keep list and not pinned
            history = history.filter { idsToKeep.contains($0.id) || $0.isPinned }
            
            // Save the updated history to disk
            saveHistory()
            
            print("Trimmed history to \(history.count) items (\(pinnedItems.count) pinned, \(maxUnpinnedItems) unpinned)")
            
            // Notify that history was updated
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        }
    }
    
    func startMonitoring() {
        print("Starting clipboard monitoring...")
        
        // Check clipboard every 0.5 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    func stopMonitoring() {
        print("Stopping clipboard monitoring...")
        timer?.invalidate()
        timer = nil
    }
    
    func getHistory() -> [ClipboardItem] {
        print("Getting clipboard history, \(history.count) items available")
        
        // Return sorted history with pinned items at the top, then by timestamp (newest first)
        return history.sorted { (item1, item2) -> Bool in
            if item1.isPinned && !item2.isPinned {
                return true
            } else if !item1.isPinned && item2.isPinned {
                return false
            } else {
                return item1.timestamp > item2.timestamp
            }
        }
    }
    
    @objc func clearHistory() {
        print("Clearing clipboard history")
        history.removeAll()
        saveHistory()
        
        // Notify that history was cleared
        NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
    }
    
    @objc func togglePinItem(_ notification: Notification) {
        guard let itemID = notification.object as? UUID else { return }
        
        print("Toggling pin for item with ID: \(itemID)")
        
        if let index = history.firstIndex(where: { $0.id == itemID }) {
            var item = history[index]
            item.isPinned.toggle()
            history[index] = item
            
            print("Item \(item.content.prefix(30))... is now \(item.isPinned ? "pinned" : "unpinned")")
            
            saveHistory()
            
            // Notify that history was updated
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        }
    }
    
    @objc func deleteItem(_ notification: Notification) {
        guard let itemID = notification.object as? UUID else { return }
        
        print("Deleting item with ID: \(itemID)")
        
        if let index = history.firstIndex(where: { $0.id == itemID }) {
            let item = history[index]
            print("Deleting item: \(item.content.prefix(30))...")
            
            history.remove(at: index)
            saveHistory()
            
            // Notify that history was updated
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        }
    }
    
    @objc func ignoreNextChange() {
        print("Setting ignoreNextClipboardChange flag")
        
        // Set the flag to ignore the next clipboard change
        ignoreNextClipboardChange = true
        
        // Reset the flag after a longer delay to ensure it's only used for the next change
        // but also ensure it doesn't get stuck if no clipboard change occurs
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.ignoreNextClipboardChange {
                print("Resetting ignoreNextClipboardChange flag after timeout")
                self.ignoreNextClipboardChange = false
            }
        }
    }
    
    @objc func updateItem(_ notification: Notification) {
        print("===== ITEM UPDATE START =====")
        guard let userInfo = notification.userInfo,
              let itemID = userInfo["itemId"] as? UUID,
              let newContent = userInfo["content"] as? String else {
            print("ERROR: Missing required information in updateItem notification")
            print("===== ITEM UPDATE FAILED =====")
            return
        }
        
        print("Updating item with ID: \(itemID)")
        print("New content: \(newContent)")
        
        if let index = history.firstIndex(where: { $0.id == itemID }) {
            var item = history[index]
            
            print("Found item at index \(index)")
            print("Original content: \(item.content)")
            print("Original isRichText: \(item.isRichText)")
            if item.isRichText {
                print("Original richTextData size: \(item.richTextData?.count ?? 0) bytes")
            }
            
            // Update the content
            item.content = newContent
            print("Updated content to: \(item.content)")
            
            // Check if we have rich text data in the notification
            if let richTextData = userInfo["richTextData"] as? Data {
                print("Updating rich text data for item")
                print("New richTextData size: \(richTextData.count) bytes")
                
                // Extract the plain text from the rich text data to ensure they're in sync
                do {
                    let attributedString = try NSAttributedString(
                        data: richTextData,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                    let plainText = attributedString.string
                    print("Extracted plain text from rich text data: \(plainText)")
                    
                    // Update the content to match the attributed string
                    if plainText != newContent {
                        print("WARNING: Plain text doesn't match content. Updating content to match rich text data.")
                        item.content = plainText
                        print("Updated content to match rich text data: \(plainText)")
                    }
                } catch {
                    print("Error extracting plain text from rich text data: \(error)")
                }
                
                item.richTextData = richTextData
                
                // If the item has multiple formats, update all RTF-related formats in pasteboardItems
                if item.hasMultipleFormats, let pasteboardItems = item.pasteboardItems {
                    print("Updating RTF formats in pasteboardItems")
                    var updatedPasteboardItems: [PasteboardItemData] = []
                    
                    for pbItem in pasteboardItems {
                        let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                        
                        // If this is an RTF format, use the updated rich text data
                        if type == .rtf || type.rawValue.contains("rtf") || type.rawValue.contains("richtext") || type.rawValue.contains("Rich Text Format") {
                            print("Updating pasteboardItem for format: \(type.rawValue) with new rich text data")
                            updatedPasteboardItems.append(PasteboardItemData(type: type, data: richTextData))
                        } 
                        // If this is a plain text format, update it with the content from the rich text
                        else if type == .string || type.rawValue.contains("string") || type.rawValue.contains("text") {
                            print("Updating plain text format: \(type.rawValue) with content from rich text")
                            if let textData = item.content.data(using: .utf8) {
                                updatedPasteboardItems.append(PasteboardItemData(type: type, data: textData))
                            } else {
                                // If we can't convert to UTF-8, keep the original data
                                updatedPasteboardItems.append(pbItem)
                            }
                        } else {
                            // For non-RTF formats, keep the original data
                            updatedPasteboardItems.append(pbItem)
                        }
                    }
                    
                    // Update the pasteboardItems array
                    item.pasteboardItems = updatedPasteboardItems
                    print("Updated \(updatedPasteboardItems.count) pasteboardItems")
                }
            } else {
                print("No rich text data in notification")
            }
            
            // Save the updated item back to history
            history[index] = item
            
            print("Item updated: \(item.content)")
            print("Updated isRichText: \(item.isRichText)")
            if item.isRichText {
                print("Updated richTextData size: \(item.richTextData?.count ?? 0) bytes")
            }
            
            // Save the updated history
            saveHistory()
            
            // Update the clipboard with the new content if it's the most recent item or pinned
            if index == 0 || item.isPinned {
                print("Updating clipboard with edited item (index: \(index), isPinned: \(item.isPinned))")
                
                // Use the copyItemToClipboard method to ensure consistent behavior
                copyItemToClipboard(item)
            } else {
                print("Not updating clipboard (not most recent or pinned)")
            }
            
            // Notify that history was updated
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
            print("Posted ClipboardHistoryUpdated notification")
            print("===== ITEM UPDATE COMPLETE =====")
        } else {
            print("ERROR: Could not find item with ID \(itemID) in history")
            print("===== ITEM UPDATE FAILED =====")
        }
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Skip if we should ignore this change
        if ignoreNextClipboardChange {
            print("Ignoring clipboard change due to ignoreNextClipboardChange flag")
            ignoreNextClipboardChange = false
            return
        }
        
        // Capture all available types in the pasteboard
        let availableTypes = pasteboard.types ?? []
        var pasteboardItems: [PasteboardItemData] = []
        
        // Check if we have multiple formats to preserve
        if availableTypes.count > 1 {
            for type in availableTypes {
                if let data = pasteboard.data(forType: type) {
                    pasteboardItems.append(PasteboardItemData(type: type, data: data))
                }
            }
        }
        
        // Check for rich text first
        if let rtfData = pasteboard.data(forType: .rtf) ?? pasteboard.data(forType: .rtfd) {
            // Skip if rich text hasn't changed
            if let lastRichTextData = self.lastRichTextData, lastRichTextData == rtfData {
                return
            }
            
            // Get plain text representation for display
            let plainText = pasteboard.string(forType: .string) ?? "[Rich Text]"
            
            // Check if this content already exists in history (improved duplicate detection)
            let existingItem = history.first(where: { 
                // Check if the content matches
                if $0.content == plainText {
                    return true
                }
                
                // Check if the RTF data matches or is very similar (within 10% size difference)
                if let itemRtfData = $0.richTextData {
                    let sizeDifference = abs(Double(itemRtfData.count) - Double(rtfData.count)) / Double(itemRtfData.count)
                    if sizeDifference < 0.1 {
                        // The RTF data is very similar in size, likely the same content with minor edits
                        return true
                    }
                }
                
                return false
            })
            
            if existingItem != nil {
                // Content already exists in history, just update lastRichTextData
                self.lastRichTextData = rtfData
                return
            }
            
            // Update last rich text data
            self.lastRichTextData = rtfData
            
            print("New clipboard rich text detected: \(plainText.prefix(30))...")
            
            // Add to history
            let item = ClipboardItem(
                content: plainText,
                richTextData: rtfData,
                pasteboardItems: pasteboardItems.isEmpty ? nil : pasteboardItems
            )
            addToHistory(item)
            
            // Show notification only if preferences allow and permissions are granted
            let prefs = Preferences.shared
            if prefs.showNotifications && notificationsEnabled {
                showNotification(for: item)
            }
            
            return
        }
        
        // Check for image next
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            // Skip if image hasn't changed
            if let lastImageData = self.lastImageData, lastImageData == imageData {
                return
            }
            
            // Update last image data
            self.lastImageData = imageData
            
            // Create a description for the image
            let description = "[Image] \(NSImage(data: imageData)?.size.width ?? 0)x\(NSImage(data: imageData)?.size.height ?? 0)"
            
            // Check if this image already exists in history
            let existingItem = history.first(where: { 
                if let itemImageData = $0.imageData {
                    return itemImageData == imageData
                }
                return false
            })
            
            if existingItem != nil {
                // Image already exists in history
                return
            }
            
            print("New clipboard image detected: \(description)")
            
            // Add to history
            let item = ClipboardItem(
                content: description, 
                imageData: imageData,
                pasteboardItems: pasteboardItems.isEmpty ? nil : pasteboardItems
            )
            addToHistory(item)
            
            // Show notification only if preferences allow and permissions are granted
            let prefs = Preferences.shared
            if prefs.showNotifications && notificationsEnabled {
                showNotification(for: item)
            }
            
            return
        }
        
        // If no rich text or image, check for plain text
        if let text = pasteboard.string(forType: .string) {
            // Skip if content hasn't changed or is empty
            if text.isEmpty || text == lastContent {
                return
            }
            
            // Check if this content already exists in history (improved duplicate detection)
            let existingItem = history.first(where: { 
                // Check for exact match
                if $0.content == text {
                    return true
                }
                
                // Check if the content is very similar (e.g., just added a few characters)
                if $0.content.count > 0 && text.count > 0 {
                    // If one is a substring of the other with at least 80% similarity
                    if $0.content.contains(text) && Double(text.count) / Double($0.content.count) > 0.8 {
                        return true
                    }
                    if text.contains($0.content) && Double($0.content.count) / Double(text.count) > 0.8 {
                        return true
                    }
                }
                
                return false
            })
            
            if existingItem != nil {
                // Content already exists in history, just update lastContent
                lastContent = text
                return
            }
            
            // Update last content
            lastContent = text
            
            print("New clipboard content detected: \(text.prefix(30))...")
            
            // Add to history
            let item = ClipboardItem(
                content: text,
                pasteboardItems: pasteboardItems.isEmpty ? nil : pasteboardItems
            )
            addToHistory(item)
            
            // Show notification only if preferences allow and permissions are granted
            let prefs = Preferences.shared
            if prefs.showNotifications && notificationsEnabled {
                showNotification(for: item)
            }
            
            // Auto-paste if enabled in preferences
            if prefs.autoPaste {
                print("Auto-paste is enabled, attempting to paste...")
                // Use a slight delay to ensure the clipboard content is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Pass the rich text flag if this is a rich text item
                    if item.isRichText {
                        PasteManager.shared.paste(isRichText: true)
                    } else if item.hasMultipleFormats {
                        // Check if we have HTML data which should be treated as rich text
                        let pasteboard = NSPasteboard.general
                        if pasteboard.data(forType: .html) != nil || 
                           pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: "Apple HTML pasteboard type")) != nil {
                            print("HTML data detected, treating as rich text")
                            PasteManager.shared.paste(isRichText: true)
                        } else {
                            PasteManager.shared.paste()
                        }
                    } else {
                        PasteManager.shared.paste()
                    }
                }
            }
        }
    }
    
    private func addToHistory(_ item: ClipboardItem) {
        print("Adding to history: \(item.content.prefix(30))... IsImage: \(item.isImage)")
        
        // Remove duplicates (preserve pin state if it exists)
        if let existingIndex = history.firstIndex(where: { 
            if item.isImage && $0.isImage {
                return item.imageData == $0.imageData
            } else {
                return $0.content == item.content
            }
        }) {
            let isPinned = history[existingIndex].isPinned
            history.remove(at: existingIndex)
            
            // If it was pinned, keep it pinned
            if isPinned {
                var newItem = item
                newItem.isPinned = true
                history.insert(newItem, at: 0)
            } else {
                history.insert(item, at: 0)
            }
        } else {
            // Add new item at the beginning
            history.insert(item, at: 0)
        }
        
        // Get max history items from preferences
        let prefs = Preferences.shared
        
        // Enforce the max history limit (accounting for pinned items)
        let pinnedItems = history.filter { $0.isPinned }
        let unpinnedItems = history.filter { !$0.isPinned }
        
        // Calculate how many unpinned items we can keep
        let maxUnpinnedItems = max(0, prefs.maxHistoryItems - pinnedItems.count)
        
        // If we have more unpinned items than allowed, remove the oldest ones
        if unpinnedItems.count > maxUnpinnedItems {
            // Sort unpinned items by timestamp (newest first)
            let sortedUnpinnedItems = unpinnedItems.sorted { $0.timestamp > $1.timestamp }
            
            // Keep only the newest maxUnpinnedItems
            let itemsToKeep = sortedUnpinnedItems.prefix(maxUnpinnedItems)
            
            // Create a set of IDs to keep for efficient lookup
            let idsToKeep = Set(itemsToKeep.map { $0.id })
            
            // Remove items that are not in the keep list and not pinned
            history = history.filter { idsToKeep.contains($0.id) || $0.isPinned }
        }
        
        print("History now has \(history.count) items (\(pinnedItems.count) pinned, \(unpinnedItems.count) unpinned, max unpinned: \(maxUnpinnedItems))")
        
        // Save history to file
        saveHistory()
        
        // Notify that history was updated
        NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
    }
    
    // Method to copy an item back to the clipboard
    func copyItemToClipboard(_ item: ClipboardItem) {
        print("===== CLIPBOARD OPERATION START =====")
        print("Copying item to clipboard: \(item.content)")
        print("Item ID: \(item.id)")
        print("Is Rich Text: \(item.isRichText)")
        print("Has Multiple Formats: \(item.hasMultipleFormats)")
        
        // Set flag to ignore the next clipboard change BEFORE modifying the clipboard
        ignoreNextClipboardChange = true
        print("Set ignoreNextClipboardChange to true")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        // If this is a rich text item, handle it specially to ensure formatting is preserved
        if item.isRichText, let richTextData = item.richTextData {
            print("Item has rich text data, ensuring it's properly formatted")
            print("Rich text data size: \(richTextData.count) bytes")
            
            // Try to create an attributed string from the rich text data
            do {
                let attributedString = try NSAttributedString(
                    data: richTextData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                print("Created attributed string from rich text data: \(attributedString.string)")
                
                // Create a fresh mutable copy to ensure all attributes are preserved
                let mutableString = NSMutableAttributedString(attributedString: attributedString)
                print("Created mutable copy of attributed string")
                
                // Get the plain text directly from the attributed string - this ensures it matches the RTF content
                let plainText = attributedString.string
                print("Extracted plain text from attributed string: \(plainText)")
                
                // Update the item's content to match the attributed string
                // This ensures the content is in sync with the rich text data
                if plainText != item.content {
                    print("Updating item content to match attributed string")
                    // We're not modifying the original item, just ensuring the clipboard gets the right content
                }
                
                // Use writeObjects for better compatibility - this is the most reliable way
                let success = pasteboard.writeObjects([mutableString])
                print("Writing attributed string to pasteboard: \(success)")
                
                // Also get fresh RTF data from the attributed string
                let freshRtfData = try mutableString.data(
                    from: NSRange(location: 0, length: mutableString.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                print("Created fresh RTF data: \(freshRtfData.count) bytes")
                
                // Set RTF data for all common RTF formats to maximize compatibility
                let rtfFormats: [NSPasteboard.PasteboardType] = [
                    .rtf,
                    .init("NeXT Rich Text Format v1.0 pasteboard type"),
                    .init("com.apple.notes.richtext"),
                    .init("public.rtf"),
                    .init("Apple Rich Text Format")
                ]
                
                for format in rtfFormats {
                    pasteboard.setData(freshRtfData, forType: format)
                    print("Set fresh RTF data for format: \(format.rawValue)")
                }
                
                // Also set plain text for apps that don't support rich text
                // Use the plain text from the attributed string, not the item's content
                pasteboard.setString(plainText, forType: .string)
                print("Set plain text fallback: \(plainText)")
                
                // If we have multiple formats, also set those (except for RTF formats which we've already handled)
                if item.hasMultipleFormats, let pasteboardItems = item.pasteboardItems {
                    print("Setting additional formats from pasteboardItems")
                    
                    for pbItem in pasteboardItems {
                        let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                        
                        // Skip RTF formats as we've already set those with fresh data
                        if type == .rtf || type.rawValue.contains("rtf") || type.rawValue.contains("richtext") || type.rawValue.contains("Rich Text Format") {
                            continue
                        }
                        
                        // Skip plain text formats as we've already set those with the updated text
                        if type == .string || type.rawValue.contains("string") || type.rawValue.contains("text") {
                            continue
                        }
                        
                        // For non-RTF formats, use the original data
                        pasteboard.setData(pbItem.data, forType: type)
                        print("Set additional format: \(type.rawValue) with \(pbItem.data.count) bytes")
                    }
                }
                
                // Update tracking variables directly with the item's data to prevent re-adding
                lastRichTextData = freshRtfData  // Use the fresh RTF data
                print("Updated lastRichTextData with fresh RTF data: \(freshRtfData.count) bytes")
                lastContent = plainText  // Use the plain text from the attributed string
                print("Updated lastContent: \(plainText)")
                
                // Verify the clipboard contents
                verifyClipboardContents(item, freshRtfData, plainText)
            } catch {
                print("Error processing rich text data: \(error)")
                
                // Fallback to setting the RTF data directly
                print("Falling back to setting RTF data directly")
                
                // Set rich text data for all relevant RTF formats
                let rtfFormats: [NSPasteboard.PasteboardType] = [
                    .rtf,
                    .init("NeXT Rich Text Format v1.0 pasteboard type"),
                    .init("com.apple.notes.richtext"),
                    .init("public.rtf"),
                    .init("Apple Rich Text Format")
                ]
                
                for format in rtfFormats {
                    pasteboard.setData(richTextData, forType: format)
                    print("Set rich text data for format: \(format.rawValue) with \(richTextData.count) bytes")
                }
                
                // Also set plain text for apps that don't support rich text
                pasteboard.setString(item.content, forType: .string)
                
                // If we have multiple formats, also set those (except for RTF formats which we've already handled)
                if item.hasMultipleFormats, let pasteboardItems = item.pasteboardItems {
                    print("Setting additional formats from pasteboardItems")
                    
                    for pbItem in pasteboardItems {
                        let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                        
                        // Skip RTF formats as we've already set those
                        if type == .rtf || type.rawValue.contains("rtf") || type.rawValue.contains("richtext") || type.rawValue.contains("Rich Text Format") {
                            continue
                        }
                        
                        // For non-RTF formats, use the original data
                        pasteboard.setData(pbItem.data, forType: type)
                        print("Set additional format: \(type.rawValue) with \(pbItem.data.count) bytes")
                    }
                }
                
                // Update tracking variables
                lastRichTextData = richTextData
                lastContent = item.content
            }
        }
        // If we have multiple formats but it's not rich text, check for HTML data
        else if item.hasMultipleFormats, let pasteboardItems = item.pasteboardItems {
            print("Setting multiple formats to clipboard")
            
            // Check if we have HTML data that we can convert to RTF
            var htmlData: Data? = nil
            var htmlType: NSPasteboard.PasteboardType? = nil
            
            for pbItem in pasteboardItems {
                let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                if type == .html || type.rawValue.contains("HTML") {
                    htmlData = pbItem.data
                    htmlType = type
                    print("Found HTML data: \(pbItem.data.count) bytes, type: \(type.rawValue)")
                    break
                }
            }
            
            // If we have HTML data, try to convert it to RTF
            if let htmlData = htmlData, let htmlType = htmlType {
                print("Converting HTML data to RTF")
                do {
                    // Create an attributed string from the HTML data
                    let attributedString = try NSAttributedString(
                        data: htmlData,
                        options: [.documentType: NSAttributedString.DocumentType.html],
                        documentAttributes: nil
                    )
                    print("Created attributed string from HTML data: \(attributedString.string)")
                    
                    // Create RTF data from the attributed string
                    let rtfData = try attributedString.data(
                        from: NSRange(location: 0, length: attributedString.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                    )
                    print("Created RTF data from HTML: \(rtfData.count) bytes")
                    
                    // Use writeObjects for better compatibility
                    let success = pasteboard.writeObjects([attributedString])
                    print("Writing attributed string to pasteboard: \(success)")
                    
                    // Set RTF data for all common RTF formats
                    let rtfFormats: [NSPasteboard.PasteboardType] = [
                        .rtf,
                        .init("NeXT Rich Text Format v1.0 pasteboard type"),
                        .init("com.apple.notes.richtext"),
                        .init("public.rtf"),
                        .init("Apple Rich Text Format")
                    ]
                    
                    for format in rtfFormats {
                        pasteboard.setData(rtfData, forType: format)
                        print("Set RTF data for format: \(format.rawValue)")
                    }
                    
                    // Also set the original HTML data
                    pasteboard.setData(htmlData, forType: htmlType)
                    print("Set original HTML data for format: \(htmlType.rawValue)")
                    
                    // Set plain text as fallback
                    pasteboard.setString(attributedString.string, forType: .string)
                    print("Set plain text fallback: \(attributedString.string)")
                    
                    // Set other formats (except HTML and RTF which we've already handled)
                    for pbItem in pasteboardItems {
                        let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                        if type == htmlType || type == .rtf || type.rawValue.contains("rtf") || 
                           type.rawValue.contains("richtext") || type.rawValue.contains("Rich Text Format") {
                            continue
                        }
                        
                        pasteboard.setData(pbItem.data, forType: type)
                        print("Set additional format: \(type.rawValue) with \(pbItem.data.count) bytes")
                    }
                    
                    // Update tracking variables
                    lastRichTextData = rtfData
                    lastContent = item.content
                    print("Updated lastRichTextData with RTF data converted from HTML: \(rtfData.count) bytes")
                    print("Updated lastContent: \(lastContent)")
                    
                } catch {
                    print("Error converting HTML to RTF: \(error)")
                    
                    // Fallback to setting all formats directly
                    for pbItem in pasteboardItems {
                        let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                        pasteboard.setData(pbItem.data, forType: type)
                        print("Set format: \(type.rawValue) with \(pbItem.data.count) bytes")
                    }
                    
                    // Update tracking variables
                    lastContent = item.content
                }
            } else {
                // No HTML data, just set all formats directly
                for pbItem in pasteboardItems {
                    let type = NSPasteboard.PasteboardType(rawValue: pbItem.type)
                    pasteboard.setData(pbItem.data, forType: type)
                    print("Set format: \(type.rawValue) with \(pbItem.data.count) bytes")
                }
                
                // Update tracking variables
                if item.isRichText, let richTextData = item.richTextData {
                    lastRichTextData = richTextData
                }
                lastContent = item.content
            }
        }
        // If it's an image
        else if item.isImage, let image = item.getImage() {
            print("Setting image to clipboard")
            
            // Copy image to clipboard
            pasteboard.writeObjects([image])
            
            // Update last image data to prevent re-adding
            lastImageData = item.imageData
            print("Updated lastImageData with \(item.imageData?.count ?? 0) bytes")
        }
        // If it's plain text
        else {
            print("Setting plain text to clipboard: \(item.content)")
            
            // Copy text to clipboard
            pasteboard.setString(item.content, forType: .string)
            
            // Update last content to prevent re-adding
            lastContent = item.content
            print("Updated lastContent: \(lastContent)")
            
            // Verify what was actually set to the clipboard
            if let clipboardString = pasteboard.string(forType: .string) {
                print("Verified string on clipboard: \(clipboardString)")
            } else {
                print("WARNING: Failed to verify string on clipboard!")
            }
        }
        
        // Make sure the flag is still set (in case it was reset by a timer)
        ignoreNextClipboardChange = true
        
        print("===== CLIPBOARD OPERATION END =====")
    }
    
    // Helper function to verify clipboard contents and retry if necessary
    private func verifyClipboardContents(_ item: ClipboardItem, _ richTextData: Data, _ expectedPlainText: String? = nil) {
        let pasteboard = NSPasteboard.general
        
        // Verify what was actually set to the clipboard
        if let clipboardRtfData = pasteboard.data(forType: .rtf) {
            print("Verified RTF data on clipboard: \(clipboardRtfData.count) bytes")
            
            // Check if the RTF data on the clipboard matches the expected data
            if clipboardRtfData.count != richTextData.count {
                print("WARNING: RTF data size mismatch! Expected \(richTextData.count) bytes, got \(clipboardRtfData.count) bytes")
                
                // Try setting the RTF data again
                print("Retrying setting RTF data to clipboard")
                pasteboard.setData(richTextData, forType: .rtf)
                
                // Verify again
                if let retryClipboardRtfData = pasteboard.data(forType: .rtf) {
                    print("After retry: RTF data on clipboard: \(retryClipboardRtfData.count) bytes")
                }
            }
            
            // Add more detailed logging for RTF data
            do {
                let attributedString = try NSAttributedString(
                    data: clipboardRtfData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                print("RTF content as plain text: \(attributedString.string)")
                
                // Check if the plain text content matches the expected content
                let plainTextToCheck = expectedPlainText ?? item.content
                if attributedString.string != plainTextToCheck {
                    print("WARNING: RTF content mismatch! Expected: \(plainTextToCheck), got: \(attributedString.string)")
                }
            } catch {
                print("Error converting RTF to attributed string: \(error)")
            }
        } else {
            print("WARNING: Failed to verify RTF data on clipboard!")
            
            // Try setting the RTF data again
            print("Retrying setting RTF data to clipboard")
            pasteboard.setData(richTextData, forType: .rtf)
            
            // Verify again
            if let retryClipboardRtfData = pasteboard.data(forType: .rtf) {
                print("After retry: RTF data on clipboard: \(retryClipboardRtfData.count) bytes")
            }
        }
        
        if let clipboardString = pasteboard.string(forType: .string) {
            print("Verified string on clipboard: \(clipboardString)")
            
            // Check if the string content matches the expected content
            let plainTextToCheck = expectedPlainText ?? item.content
            if clipboardString != plainTextToCheck {
                print("WARNING: String content mismatch! Expected: \(plainTextToCheck), got: \(clipboardString)")
                
                // Try setting the string again
                print("Retrying setting string to clipboard")
                pasteboard.setString(plainTextToCheck, forType: .string)
                
                // Verify again
                if let retryClipboardString = pasteboard.string(forType: .string) {
                    print("After retry: String on clipboard: \(retryClipboardString)")
                }
            }
        } else {
            print("WARNING: Failed to verify string on clipboard!")
            
            // Try setting the string again
            print("Retrying setting string to clipboard")
            let plainTextToCheck = expectedPlainText ?? item.content
            pasteboard.setString(plainTextToCheck, forType: .string)
            
            // Verify again
            if let retryClipboardString = pasteboard.string(forType: .string) {
                print("After retry: String on clipboard: \(retryClipboardString)")
            }
        }
    }
    
    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            try data.write(to: historyFilePath)
            print("History saved to file successfully")
        } catch {
            print("Error saving history: \(error)")
        }
    }
    
    private func loadHistory() {
        do {
            if FileManager.default.fileExists(atPath: historyFilePath.path) {
                print("Loading history from file: \(historyFilePath.path)")
                let data = try Data(contentsOf: historyFilePath)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                history = try decoder.decode([ClipboardItem].self, from: data)
                
                // Sort history after loading to ensure newest items are at the top
                history.sort { $0.timestamp > $1.timestamp }
            }
        } catch {
            print("Error loading history: \(error)")
            history = []
        }
    }
    
    private func showNotification(for item: ClipboardItem) {
        // Skip notifications if not enabled in preferences
        let prefs = Preferences.shared
        if !prefs.showNotifications || !notificationsEnabled {
            return
        }
        
        // Check if we're running from a proper bundle
        guard Bundle.main.bundleIdentifier != nil else {
            print("Not running from a proper bundle, notifications disabled")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "Clipboard Manager"
        
        if item.isImage {
            content.body = "Image copied to clipboard"
        } else {
            let displayText = item.content
            content.body = displayText.count > 50 ? String(displayText.prefix(47)) + "..." : displayText
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
} 