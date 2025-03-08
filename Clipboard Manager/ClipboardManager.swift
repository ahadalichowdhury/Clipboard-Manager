import Cocoa
import UserNotifications

struct ClipboardItem: Codable, Identifiable {
    let id: UUID
    var content: String
    let timestamp: Date
    var isPinned: Bool
    
    init(content: String, isPinned: Bool = false) {
        self.id = UUID()
        self.content = content
        self.timestamp = Date()
        self.isPinned = isPinned
    }
}

class ClipboardManager {
    private var history: [ClipboardItem] = []
    private var lastContent: String = ""
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
            print("Item \(index): \(item.content.prefix(30))... Pinned: \(item.isPinned)")
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
        guard let pasteboard = NSPasteboard.general.string(forType: .string) else {
            return
        }
        
        // Skip if content hasn't changed or is empty
        if pasteboard.isEmpty || pasteboard == lastContent {
            return
        }
        
        // Skip if we should ignore this change
        if ignoreNextClipboardChange {
            lastContent = pasteboard
            ignoreNextClipboardChange = false
            return
        }
        
        // Check if this content already exists in history
        let existingItem = history.first(where: { $0.content == pasteboard })
        if existingItem != nil {
            // Content already exists in history, just update lastContent
            lastContent = pasteboard
            return
        }
        
        print("New clipboard content detected: \(pasteboard.prefix(30))...")
        
        // Update last content
        lastContent = pasteboard
        
        // Add to history
        let item = ClipboardItem(content: pasteboard)
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
    
    private func addToHistory(_ item: ClipboardItem) {
        print("Adding to history: \(item.content.prefix(30))...")
        
        // Remove duplicates (preserve pin state if it exists)
        if let existingIndex = history.firstIndex(where: { $0.content == item.content }) {
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
        
        let displayText = item.content
        content.body = displayText.count > 50 ? String(displayText.prefix(47)) + "..." : displayText
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
} 