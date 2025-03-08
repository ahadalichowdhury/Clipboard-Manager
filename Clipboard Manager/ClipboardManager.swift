import Cocoa
import UserNotifications

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    var content: String
    let timestamp: Date
    var isPinned: Bool
    var imageData: Data?
    
    var isImage: Bool {
        return imageData != nil
    }
    
    init(content: String, imageData: Data? = nil, isPinned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.imageData = imageData
        self.timestamp = Date()
        self.isPinned = isPinned
    }
    
    func getImage() -> NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }
    
    // Custom encoding for Codable
    enum CodingKeys: String, CodingKey {
        case id, content, timestamp, isPinned, imageData
    }
}

class ClipboardManager {
    private var history: [ClipboardItem] = []
    private var lastContent: String = ""
    private var lastImageData: Data?
    private var timer: Timer?
    private let historyFilePath: URL
    private var notificationsEnabled = false
    private var ignoreNextClipboardChange = false
    
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
            print("Item \(index): \(item.content.prefix(30))... Pinned: \(item.isPinned) IsImage: \(item.isImage)")
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
        
        // Limit history size (only remove unpinned items)
        let unpinnedItems = history.filter { !$0.isPinned }
        let pinnedItems = history.filter { $0.isPinned }
        
        if unpinnedItems.count > prefs.maxHistoryItems {
            let itemsToKeep = unpinnedItems.prefix(prefs.maxHistoryItems)
            history = Array(itemsToKeep) + pinnedItems
            saveHistory()
            
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
        // Set the flag to ignore the next clipboard change
        ignoreNextClipboardChange = true
        
        // Reset the flag after a short delay to ensure it's only used for the next change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.ignoreNextClipboardChange = false
        }
    }
    
    @objc func updateItem(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let itemID = userInfo["itemId"] as? UUID,
              let newContent = userInfo["content"] as? String else { return }
        
        print("Updating item with ID: \(itemID)")
        
        if let index = history.firstIndex(where: { $0.id == itemID }) {
            var item = history[index]
            
            // Update the content
            item.content = newContent
            history[index] = item
            
            print("Item updated: \(item.content.prefix(30))...")
            
            // Save the updated history
            saveHistory()
            
            // Update the clipboard with the new content if it's the most recent item
            if index == 0 || item.isPinned {
                // Tell the clipboard manager to ignore the next clipboard change
                ignoreNextClipboardChange = true
                
                // Update the clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(newContent, forType: .string)
                lastContent = newContent
            }
            
            // Notify that history was updated
            NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        }
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // Check for image first
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
            let item = ClipboardItem(content: description, imageData: imageData)
            addToHistory(item)
            
            // Show notification only if preferences allow and permissions are granted
            let prefs = Preferences.shared
            if prefs.showNotifications && notificationsEnabled {
                showNotification(for: item)
            }
            
            return
        }
        
        // If no image, check for text
        if let text = pasteboard.string(forType: .string) {
            // Skip if content hasn't changed or is empty
            if text.isEmpty || text == lastContent {
                return
            }
            
            // Skip if we should ignore this change
            if ignoreNextClipboardChange {
                lastContent = text
                ignoreNextClipboardChange = false
                return
            }
            
            // Check if this content already exists in history
            let existingItem = history.first(where: { $0.content == text })
            if existingItem != nil {
                // Content already exists in history, just update lastContent
                lastContent = text
                return
            }
            
            print("New clipboard content detected: \(text.prefix(30))...")
            
            // Update last content
            lastContent = text
            
            // Add to history
            let item = ClipboardItem(content: text)
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
                    PasteManager.shared.paste()
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
        
        // Limit history size (only remove unpinned items)
        let unpinnedItems = history.filter { !$0.isPinned }
        let pinnedItems = history.filter { $0.isPinned }
        
        if unpinnedItems.count > prefs.maxHistoryItems {
            let itemsToKeep = unpinnedItems.prefix(prefs.maxHistoryItems)
            history = Array(itemsToKeep) + pinnedItems
        }
        
        print("History now has \(history.count) items")
        
        // Save history to file
        saveHistory()
        
        // Notify that history was updated
        NotificationCenter.default.post(name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
    }
    
    // Method to copy an item back to the clipboard
    func copyItemToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.isImage, let image = item.getImage() {
            // Copy image to clipboard
            pasteboard.writeObjects([image])
        } else {
            // Copy text to clipboard
            pasteboard.setString(item.content, forType: .string)
        }
        
        // Update last content/image to prevent re-adding
        if item.isImage {
            lastImageData = item.imageData
        } else {
            lastContent = item.content
        }
        
        // Set flag to ignore the next clipboard change
        ignoreNextClipboardChange = true
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