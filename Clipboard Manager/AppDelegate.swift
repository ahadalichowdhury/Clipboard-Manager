import Cocoa
import Carbon
import HotKey
import UserNotifications
import ApplicationServices
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardManager: ClipboardManager!
    private var hotKey: HotKey?
    private var historyWindow: HistoryWindowController?
    private var preferencesWindow: PreferencesWindowController?
    private var isDebugMode: Bool = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check for debug mode
        isDebugMode = CommandLine.arguments.contains("--debug")
        if isDebugMode {
            Logger.shared.log("AppDelegate: Running in DEBUG mode")
        }
        
        // Ensure we're using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
        
        // Apply appearance settings based on preferences
        applyAppearanceSettings()
        
        // Set up notification center delegate - safely handle this to prevent crashes
        do {
            try setupNotifications()
        } catch {
            Logger.shared.log("Warning: Could not set up notifications: \(error.localizedDescription)")
            // Continue without notifications
        }
        
        // Check for accessibility permissions
        checkAccessibilityPermissions()
        
        // Initialize clipboard manager
        clipboardManager = ClipboardManager()
        
        // Setup status bar item
        setupStatusBar()
        
        // Register global hotkey (Cmd+Shift+V)
        registerHotKey()
        
        // Start monitoring clipboard
        clipboardManager.startMonitoring()
        
        // Update login item status based on preferences
        updateLoginItemStatus()
        
        // Show a welcome message
        showWelcomeMessage()
        
        // Register for history updates
        NotificationCenter.default.addObserver(self, selector: #selector(historyUpdated), name: NSNotification.Name("ClipboardHistoryUpdated"), object: nil)
        
        // Register for preferences changes
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged), name: NSNotification.Name("PreferencesChanged"), object: nil)
        
        // Register for accessibility permission requests
        NotificationCenter.default.addObserver(self, selector: #selector(requestAccessibilityPermissions), name: NSNotification.Name("RequestAccessibilityPermissions"), object: nil)
    }
    
    private func setupNotifications() throws {
        // Check if we're running from a proper bundle
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        } else {
            throw NSError(domain: "ClipboardManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not running from a proper bundle, notifications disabled"])
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager.stopMonitoring()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            // Use a clipboard icon
            if let clipboardImage = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard") {
                clipboardImage.size = NSSize(width: 18, height: 18)
                button.image = clipboardImage
            }
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
        
        let menu = NSMenu()
        
        // Add "Show History" item with keyboard shortcut displayed
        let showHistoryItem = NSMenuItem(title: "Show History (⌘⇧V)", action: #selector(showHistory), keyEquivalent: "")
        menu.addItem(showHistoryItem)
        
        // Add "Clear History" item
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // Add "Preferences" item
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ","))
        
        menu.addItem(NSMenuItem.separator())
        
        // Add "About" item
        menu.addItem(NSMenuItem(title: "About Clipboard Manager", action: #selector(showAbout), keyEquivalent: ""))
        
        // Add "Quit" item
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    private func registerHotKey() {
        // Get preferences
        let prefs = Preferences.shared
        
        // Unregister existing hotkey if any
        hotKey = nil
        
        // Determine the key to use
        let keyIndex = prefs.hotkeyKeyIndex
        let keys = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", 
                    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
                    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
                    "space", "tab", "return",
                    "upArrow", "rightArrow", "downArrow", "leftArrow",
                    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]
        
        // Default to 'v' if index is out of range
        let keyString = keyIndex >= 0 && keyIndex < keys.count ? keys[keyIndex] : "v"
        
        // Convert string to Key enum
        guard let key = Key(string: keyString) else {
            print("ERROR: Invalid key string: \(keyString), defaulting to 'v'")
            hotKey = HotKey(key: .v, modifiers: [.command, .shift])
            hotKey?.keyDownHandler = { [weak self] in
                self?.showHistory()
            }
            return
        }
        
        // Determine modifiers
        var modifiers: NSEvent.ModifierFlags = []
        
        if prefs.hotkeyCommand {
            modifiers.insert(.command)
        }
        
        if prefs.hotkeyShift {
            modifiers.insert(.shift)
        }
        
        if prefs.hotkeyOption {
            modifiers.insert(.option)
        }
        
        if prefs.hotkeyControl {
            modifiers.insert(.control)
        }
        
        // Ensure at least one modifier is selected
        if modifiers.isEmpty {
            print("WARNING: No modifiers selected, defaulting to Command")
            modifiers.insert(.command)
        }
        
        // Register the hotkey
        hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey?.keyDownHandler = { [weak self] in
            self?.showHistory()
        }
        
        print("Registered hotkey: \(key) with modifiers: \(modifiers)")
    }
    
    private func showWelcomeMessage() {
        let alert = NSAlert()
        alert.messageText = "Clipboard Manager"
        alert.informativeText = "Clipboard Manager is now running in the menu bar.\n\n" +
                               "• Copy text to add it to your clipboard history\n" +
                               "• Press Cmd+Shift+V to show your clipboard history\n" +
                               "• Click on the clipboard icon in the menu bar for options"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // Ensure alert appears on top of other applications
        safelyActivateApp()
        alert.window.level = .floating
        
        alert.runModal()
        
        // Ensure we're still using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc private func statusBarButtonClicked() {
        statusItem.button?.performClick(nil)
    }
    
    @objc private func historyUpdated() {
        // Update history window if it's open
        if let window = historyWindow, window.window?.isVisible == true {
            // Instead of creating a new window, just update the items in the existing window
            window.updateItems(getClipboardHistory())
            
            // Ensure window is visible and on top
            if let windowObj = historyWindow?.window {
                windowObj.orderFrontRegardless()
            }
        }
    }
    
    func getClipboardHistory() -> [ClipboardItem] {
        return clipboardManager.getHistory()
    }
    
    @objc private func showHistory() {
        // Get the clipboard history
        let items = getClipboardHistory()
        
        if items.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Clipboard History"
            alert.informativeText = "No items in clipboard history"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            
            // Ensure alert appears on top of other applications
            safelyActivateApp()
            alert.window.level = .floating
            
            alert.runModal()
            
            // Ensure we're still using accessory activation policy
            NSApp.setActivationPolicy(.accessory)
            return
        }
        
        // Create and show the history window
        historyWindow = HistoryWindowController(items: items)
        
        // Apply appearance settings to the history window based on preferences
        if let window = historyWindow?.window {
            let prefs = Preferences.shared
            if prefs.useSystemAppearance {
                window.appearance = nil // Use system appearance
            } else if prefs.darkMode {
                window.appearance = NSAppearance(named: .darkAqua)
            } else {
                window.appearance = NSAppearance(named: .aqua)
            }
        }
        
        historyWindow?.showWindow(nil)
        safelyActivateApp()
        
        // Ensure the window is visible and can receive keyboard events
        if let window = historyWindow?.window {
            window.orderFrontRegardless()
            window.makeKey()
            
            // Activate the app to ensure keyboard events are captured
            NSApp.activate(ignoringOtherApps: true)
        }
        
        // Ensure we're still using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc private func clearHistory() {
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Clear Clipboard History"
        alert.informativeText = "Are you sure you want to clear all clipboard history?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        
        // Ensure alert appears on top of other applications
        safelyActivateApp()
        alert.window.level = .floating
        
        if alert.runModal() == .alertFirstButtonReturn {
            // User confirmed, clear history
            NotificationCenter.default.post(name: NSNotification.Name("ClearClipboardHistory"), object: nil)
        }
        
        // Ensure we're still using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About Clipboard Manager"
        alert.informativeText = "Clipboard Manager 1.0\n\n" +
                               "A simple clipboard history manager for macOS.\n\n" +
                               "© 2025 All rights reserved."
        alert.messageText = "Owner: S. M. Ahad Ali Chowdhury"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // Ensure alert appears on top of other applications
        safelyActivateApp()
        alert.window.level = .floating
        
        alert.runModal()
        
        // Ensure we're still using accessory activation policy
        NSApp.setActivationPolicy(.accessory)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    @objc private func preferencesChanged() {
        // Update the history window if it's open
        if let window = historyWindow, window.window?.isVisible == true {
            // Instead of creating a new window, just update the items in the existing window
            window.updateItems(getClipboardHistory())
            
            // Apply appearance settings to the history window based on preferences
            if let historyWindowObj = window.window {
                let prefs = Preferences.shared
                if prefs.useSystemAppearance {
                    historyWindowObj.appearance = nil // Use system appearance
                } else if prefs.darkMode {
                    historyWindowObj.appearance = NSAppearance(named: .darkAqua)
                } else {
                    historyWindowObj.appearance = NSAppearance(named: .aqua)
                }
            }
        }
        
        // Update hotkey if needed
        registerHotKey()
        
        // Update login item status
        updateLoginItemStatus()
        
        // Apply appearance settings
        applyAppearanceSettings()
    }
    
    private func applyAppearanceSettings() {
        // Set the app's appearance to always follow system appearance
        NSApp.appearance = nil // Use system appearance
        
        // Apply the same system appearance to all windows except the clipboard history window
        for window in NSApp.windows {
            // Skip the clipboard history window - it will be handled separately
            if window != historyWindow?.window {
                window.appearance = nil // Always use system appearance
            }
        }
    }
    
    private func updateHotKey() {
        // Unregister existing hotkey
        hotKey = nil
        
        // Register hotkey with current preferences
        registerHotKey()
    }
    
    @objc private func showPreferences() {
        // Debug print to track method call
        print("AppDelegate.showPreferences called")
        
        // Force create a new preferences window controller every time
        preferencesWindow = PreferencesWindowController()
        
        // Make sure we have a window
        guard let window = preferencesWindow?.window else {
            print("ERROR: Failed to create preferences window")
            return
        }
        
        // Set window properties to ensure visibility
        window.level = .floating // Use floating instead of modalPanel to ensure it's visible
        window.isOpaque = true
        window.hasShadow = true
        
        // Show the window and make it key
        preferencesWindow?.showWindow(nil)
        
        // Force the app to be active and bring window to front
        safelyActivateApp()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless() // Add this to force window to front
        
        // Additional check to ensure window is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = self.preferencesWindow?.window {
                if !window.isVisible {
                    print("Window still not visible, forcing again")
                    window.orderFrontRegardless()
                    self.safelyActivateApp()
                }
            }
            
            // Ensure we're still using accessory activation policy
            NSApp.setActivationPolicy(.accessory)
        }
        
        print("Preferences window created and should be visible: \(window), isVisible: \(window.isVisible)")
    }
    
    @objc func copyItemToClipboard(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < getClipboardHistory().count else { return }
        
        let items = getClipboardHistory()
        let item = items[index]
        
        // Tell the clipboard manager to ignore the next clipboard change
        NotificationCenter.default.post(name: NSNotification.Name("IgnoreNextClipboardChange"), object: nil)
        
        // Use the ClipboardManager to copy the item to clipboard
        clipboardManager.copyItemToClipboard(item)
        
        // Show a notification that the item was copied
        showCopiedNotification(item.isImage ? "Image" : item.content)
        
        // Only show manual paste notification if auto-paste is disabled and not called from HistoryWindowController
        // We can detect this by checking if we're on the main thread
        if !Preferences.shared.autoPaste && Thread.isMainThread {
            // Check if we're running from a proper bundle
            if Bundle.main.bundleIdentifier == nil {
                // We're running from the command line, use NSLog instead
                NSLog("Press Cmd+V to paste")
                return
            }
            
            // Show a notification to manually paste
            let content = UNMutableNotificationContent()
            content.title = "Copied to Clipboard"
            content.body = "Press Cmd+V to paste"
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    NSLog("Error showing notification: \(error)")
                }
            }
        }
    }
    
    private func showCopiedNotification(_ contentText: String) {
        // Only show notification if preferences allow it
        let prefs = Preferences.shared
        if prefs.showNotifications {
            // Check if we're running from a proper bundle
            if Bundle.main.bundleIdentifier == nil {
                // We're running from the command line, use NSLog instead
                NSLog("Copied to Clipboard: \(contentText)")
                return
            }
            
            // Use UserNotifications framework
            let content = UNMutableNotificationContent()
            content.title = "Copied to Clipboard"
            
            // Check if this is an image notification
            if contentText == "Image" {
                content.body = "Image copied to clipboard"
            } else {
                // Truncate content for notification
                let displayText = contentText.count > 50 ? String(contentText.prefix(47)) + "..." : contentText
                content.body = displayText
            }
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    NSLog("Error showing notification: \(error)")
                }
            }
        }
    }

    private func simulatePasteKeystroke(isRichText: Bool = false, isImage: Bool = false) {
        Logger.shared.log("Simulating paste keystroke" + (isRichText ? " (Rich Text)" : "") + (isImage ? " (Image)" : ""))
        
        guard AXIsProcessTrusted() else {
            Logger.shared.log("Cannot simulate paste: accessibility permissions not granted")
            // Request permissions if not granted
            checkAccessibilityPermissions()
            return
        }
        
        // Use the centralized PasteManager with rich text and image information
        PasteManager.shared.paste(isRichText: isRichText, isImage: isImage)
    }

    private func checkAccessibilityPermissions() {
        Logger.shared.log("Checking accessibility permissions...")
        Logger.shared.log("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        Logger.shared.log("Process path: \(Bundle.main.bundlePath)")
        
        // First check if we already have permissions
        if AXIsProcessTrusted() {
            Logger.shared.log("Accessibility permissions already granted.")
            // Check if we can also use AppleScript
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkAppleScriptPermissions()
            }
            return
        }
        
        // If we don't have permissions, prompt the user
        Logger.shared.log("Accessibility permissions not granted. Prompting user.")
        
        // Use both methods to request permissions
        // 1. System prompt
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // 2. Our custom dialog with more detailed instructions
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.showAccessibilityInstructions()
        }
    }
    
    private func showAccessibilityInstructions() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Required"
        alert.informativeText = "To enable automatic pasting, Clipboard Manager needs accessibility permissions.\n\n" +
                               "1. Open System Settings\n" +
                               "2. Go to Privacy & Security > Accessibility\n" +
                               "3. Add or check Clipboard Manager in the list\n" +
                               "4. Restart the app after granting permissions\n\n" +
                               "Without this permission, you'll need to manually paste (Cmd+V) after selecting an item."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        NSApp.activate(ignoringOtherApps: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Settings to the Accessibility section
            // Use the newer URL format for macOS Ventura and later
            if #available(macOS 13.0, *) {
                let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                NSWorkspace.shared.open(prefpaneURL)
            } else {
                // Fallback for older macOS versions
                let prefpaneURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
                NSWorkspace.shared.open(prefpaneURL)
            }
        }
    }
    
    private func checkAppleScriptPermissions() {
        Logger.shared.log("Checking AppleScript permissions...")
        
        let script = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        
        if let error = error {
            Logger.shared.log("AppleScript permissions not granted: \(error)")
            // Show dialog to request permissions
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showAppleScriptInstructions()
            }
        } else {
            if let resultStr = result?.stringValue {
                Logger.shared.log("AppleScript permissions granted. Test result: \(resultStr)")
            } else {
                Logger.shared.log("AppleScript permissions granted but test returned no result.")
            }
        }
    }
    
    private func showAppleScriptInstructions() {
        let alert = NSAlert()
        alert.messageText = "Automation Permissions Required"
        alert.informativeText = "To enable automatic pasting, Clipboard Manager needs automation permissions.\n\n" +
                               "1. Open System Settings\n" +
                               "2. Go to Privacy & Security > Automation\n" +
                               "3. Allow Clipboard Manager to control System Events\n" +
                               "4. Restart the app after granting permissions\n\n" +
                               "Without this permission, you'll need to manually paste (Cmd+V) after selecting an item."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        NSApp.activate(ignoringOtherApps: true)
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Open System Settings to the Automation section
            // Use the newer URL format for macOS Ventura and later
            if #available(macOS 13.0, *) {
                let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
                NSWorkspace.shared.open(prefpaneURL)
            } else {
                // Fallback for older macOS versions
                let prefpaneURL = URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane")
                NSWorkspace.shared.open(prefpaneURL)
            }
        }
    }
    
    @objc private func requestAccessibilityPermissions() {
        // Check if we already have permissions
        if !AXIsProcessTrusted() {
            checkAccessibilityPermissions()
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the notification even when the app is in the foreground
        completionHandler([.banner, .sound])
    }
    
    // Helper method to safely activate the app without changing its activation policy
    private func safelyActivateApp() {
        // Save current activation policy
        let currentPolicy = NSApp.activationPolicy()
        
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)
        
        // Restore activation policy if needed
        if currentPolicy != NSApp.activationPolicy() {
            NSApp.setActivationPolicy(currentPolicy)
        }
    }
    
    // MARK: - Login Item Management
    
    private func updateLoginItemStatus() {
        if Preferences.shared.launchAtStartup {
            enableLoginItem()
        } else {
            disableLoginItem()
        }
    }
    
    private func enableLoginItem() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            Logger.shared.log("Error: Could not get bundle identifier")
            return
        }
        
        if #available(macOS 13.0, *) {
            // Use the newer API for macOS 13 (Ventura) and later
            do {
                try SMAppService.mainApp.register()
                Logger.shared.log("Successfully registered app as login item using SMAppService")
            } catch {
                Logger.shared.log("Error registering app as login item: \(error.localizedDescription)")
            }
        } else {
            // Use the older API for macOS 12 and earlier
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, true)
            Logger.shared.log("Setting login item enabled: \(success ? "success" : "failed")")
        }
    }
    
    private func disableLoginItem() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            Logger.shared.log("Error: Could not get bundle identifier")
            return
        }
        
        if #available(macOS 13.0, *) {
            // Use the newer API for macOS 13 (Ventura) and later
            do {
                try SMAppService.mainApp.unregister()
                Logger.shared.log("Successfully unregistered app as login item using SMAppService")
            } catch {
                Logger.shared.log("Error unregistering app as login item: \(error.localizedDescription)")
            }
        } else {
            // Use the older API for macOS 12 and earlier
            let success = SMLoginItemSetEnabled(bundleIdentifier as CFString, false)
            Logger.shared.log("Setting login item disabled: \(success ? "success" : "failed")")
        }
    }
} 
