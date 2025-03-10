import Cocoa
import Carbon
import ApplicationServices

class PasteManager {
    static let shared = PasteManager()
    
    // Add a property to track if we're dealing with rich text
    private var isRichTextPaste = false
    
    private init() {
        // Run diagnostics on initialization
        DispatchQueue.global(qos: .background).async {
            self.runDiagnostics()
        }
    }
    
    // Main paste method that tries all available strategies
    func paste(isRichText: Bool = false) {
        Logger.shared.log("PasteManager: Starting paste operation" + (isRichText ? " (Rich Text)" : ""))
        
        // Set the rich text flag
        self.isRichTextPaste = isRichText
        
        // Check for accessibility permissions
        guard AXIsProcessTrusted() else {
            Logger.shared.log("PasteManager: Cannot paste - accessibility permissions not granted")
            // Show a notification to the user
            showAccessibilityNotification()
            // Request permissions via AppDelegate
            NotificationCenter.default.post(name: NSNotification.Name("RequestAccessibilityPermissions"), object: nil)
            return
        }
        
        // Log environment information
        logEnvironmentInfo()
        
        // Try all paste methods in sequence with proper delays
        DispatchQueue.global(qos: .userInitiated).async {
            // Make sure we're not trying to paste into Clipboard Manager itself
            if let frontApp = NSWorkspace.shared.frontmostApplication,
               frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
                Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
                
                // Try to find the previous active application
                if let previousApp = NSWorkspace.shared.runningApplications.first(where: { 
                    $0.isActive == false && 
                    $0.bundleIdentifier != Bundle.main.bundleIdentifier && 
                    $0.activationPolicy == .regular 
                }) {
                    Logger.shared.log("PasteManager: Activating previous app: \(previousApp.localizedName ?? "Unknown")")
                    previousApp.activate(options: .activateIgnoringOtherApps)
                    
                    // Give the app time to activate
                    Thread.sleep(forTimeInterval: 0.3)
                } else {
                    Logger.shared.log("PasteManager: Could not find a suitable target application")
                    DispatchQueue.main.async {
                        self.showPasteFailureNotification()
                    }
                    return
                }
            }
            
            // 1. Try direct paste with Command+V
            if self.tryDirectPasteMethod() {
                Logger.shared.log("PasteManager: Direct paste succeeded")
                return
            }
            
            // 2. Try AppleScript methods
            Thread.sleep(forTimeInterval: 0.3)
            if self.tryAppleScriptPasteMethods() {
                Logger.shared.log("PasteManager: AppleScript paste succeeded")
                return
            }
            
            // 3. Try osascript as a last resort
            Thread.sleep(forTimeInterval: 0.3)
            if self.tryOsascriptPaste() {
                Logger.shared.log("PasteManager: osascript paste succeeded")
                return
            }
            
            // 4. If all else fails, notify the user
            DispatchQueue.main.async {
                self.showPasteFailureNotification()
            }
        }
    }
    
    private func isRunningFromDMG() -> Bool {
        let path = Bundle.main.bundlePath
        return path.contains(".dmg/") || path.contains("/Volumes/")
    }
    
    private func isDebugBuild() -> Bool {
        #if DEBUG
            return true
        #else
            return CommandLine.arguments.contains("--debug")
        #endif
    }
    
    private func runDiagnostics() {
        Logger.shared.log("PasteManager: Running diagnostics...")
        
        // Check bundle ID
        if let bundleID = Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Bundle ID: \(bundleID)")
        } else {
            Logger.shared.log("PasteManager: WARNING - No bundle ID found")
        }
        
        // Check executable path
        if let executablePath = Bundle.main.executablePath {
            Logger.shared.log("PasteManager: Executable path: \(executablePath)")
            
            // Check if executable exists and is executable
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: executablePath) {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: executablePath, isDirectory: &isDir) {
                    if isDir.boolValue {
                        Logger.shared.log("PasteManager: WARNING - Executable path is a directory")
                    } else {
                        Logger.shared.log("PasteManager: Executable exists")
                    }
                }
            } else {
                Logger.shared.log("PasteManager: WARNING - Executable does not exist at path")
            }
        } else {
            Logger.shared.log("PasteManager: WARNING - No executable path found")
        }
        
        // Check for SDEF file
        let sdefPath = Bundle.main.path(forResource: "ClipboardManager", ofType: "sdef")
        if let path = sdefPath {
            Logger.shared.log("PasteManager: SDEF file found at: \(path)")
        } else {
            Logger.shared.log("PasteManager: WARNING - SDEF file not found in bundle")
        }
        
        // Check AppleScript permissions
        checkAppleScriptPermissions()
        
        // Check if we can get frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            Logger.shared.log("PasteManager: Frontmost app: \(frontApp.localizedName ?? "Unknown") (Bundle ID: \(frontApp.bundleIdentifier ?? "unknown"))")
        } else {
            Logger.shared.log("PasteManager: WARNING - Cannot determine frontmost app")
        }
        
        // Check if we can create CGEventSource
        if let _ = CGEventSource(stateID: .combinedSessionState) {
            Logger.shared.log("PasteManager: CGEventSource creation successful")
        } else {
            Logger.shared.log("PasteManager: WARNING - Cannot create CGEventSource")
        }
        
        // Check if osascript is available
        do {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            task.arguments = ["osascript"]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                Logger.shared.log("PasteManager: osascript found at: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            } else {
                Logger.shared.log("PasteManager: WARNING - osascript not found")
            }
        } catch {
            Logger.shared.log("PasteManager: WARNING - Error checking for osascript: \(error.localizedDescription)")
        }
        
        Logger.shared.log("PasteManager: Diagnostics completed")
    }
    
    private func checkAppleScriptPermissions() {
        Logger.shared.log("PasteManager: Checking AppleScript permissions...")
        
        let script = NSAppleScript(source: "tell application \"System Events\" to return name of first process")
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        
        if let error = error {
            Logger.shared.log("PasteManager: AppleScript permissions not granted: \(error)")
        } else {
            if let resultStr = result?.stringValue {
                Logger.shared.log("PasteManager: AppleScript permissions granted. Test result: \(resultStr)")
            } else {
                Logger.shared.log("PasteManager: AppleScript permissions granted but test returned no result.")
            }
        }
    }
    
    private func logEnvironmentInfo() {
        Logger.shared.log("PasteManager: Environment Info:")
        Logger.shared.log("Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        Logger.shared.log("Process path: \(Bundle.main.bundlePath)")
        Logger.shared.log("Running from DMG: \(isRunningFromDMG())")
        Logger.shared.log("Is debug build: \(isDebugBuild())")
        
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            Logger.shared.log("Frontmost app: \(frontmostApp.localizedName ?? "Unknown") (Bundle ID: \(frontmostApp.bundleIdentifier ?? "unknown"))")
        } else {
            Logger.shared.log("Could not determine frontmost app")
        }
    }
    
    // Direct paste method using CGEvent
    private func tryDirectPasteMethod() -> Bool {
        Logger.shared.log("PasteManager: Trying direct paste method")
        
        // Ensure the frontmost application is not our app
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            return false
        }
        
        // Make sure the target application has focus
        // Small delay to ensure the app is ready to receive keyboard events
        Thread.sleep(forTimeInterval: 0.1)
        
        // Create a source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Logger.shared.log("PasteManager: Failed to create event source")
            return false
        }
        
        // Create key down event for Command+V
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            Logger.shared.log("PasteManager: Failed to create keydown event")
            return false
        }
        keyVDown.flags = .maskCommand
        
        // Create key up event for Command+V
        guard let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            Logger.shared.log("PasteManager: Failed to create keyup event")
            return false
        }
        keyVUp.flags = .maskCommand
        
        // Post the events with proper delays
        Logger.shared.log("PasteManager: Posting keydown event...")
        keyVDown.post(tap: .cghidEventTap)
        
        // Increased delay between keydown and keyup for better reliability
        usleep(100000) // 100ms delay
        
        Logger.shared.log("PasteManager: Posting keyup event...")
        keyVUp.post(tap: .cghidEventTap)
        
        // Add a small delay after posting events
        Thread.sleep(forTimeInterval: 0.1)
        
        Logger.shared.log("PasteManager: Direct paste method completed")
        
        // Return true to indicate we attempted the method
        // We can't really know if it succeeded
        return true
    }
    
    // AppleScript paste methods
    private func tryAppleScriptPasteMethods() -> Bool {
        Logger.shared.log("PasteManager: Trying AppleScript paste methods")
        
        // Different AppleScript approaches
        let scripts = [
            // Basic approach
            """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """,
            
            // Target frontmost app
            """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                tell frontApp
                    keystroke "v" using command down
                end tell
            end tell
            """,
            
            // With delays
            """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                tell frontApp
                    delay 0.1
                    keystroke "v" using command down
                    delay 0.1
                end tell
            end tell
            """,
            
            // Alternative syntax
            """
            tell application "System Events"
                key code 9 using {command down}
            end tell
            """
        ]
        
        // Try each script
        for (index, scriptText) in scripts.enumerated() {
            Logger.shared.log("PasteManager: Trying AppleScript method \(index + 1)")
            
            let script = NSAppleScript(source: scriptText)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            
            if let error = error {
                Logger.shared.log("PasteManager: AppleScript method \(index + 1) failed: \(error)")
            } else {
                Logger.shared.log("PasteManager: AppleScript method \(index + 1) succeeded")
                return true
            }
            
            // Small delay between attempts
            usleep(100000) // 100ms
        }
        
        Logger.shared.log("PasteManager: All AppleScript paste methods failed")
        return false
    }
    
    // Shell script paste method using osascript (most reliable for DMG)
    private func tryOsascriptPaste() -> Bool {
        Logger.shared.log("PasteManager: Trying osascript paste method")
        
        // Create a temporary AppleScript file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("paste_script.scpt")
        
        // More robust script with multiple approaches
        let scriptContent = """
        try
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                tell frontApp
                    delay 0.1
                    keystroke "v" using command down
                    delay 0.1
                end tell
            end tell
        on error errMsg
            try
                tell application "System Events"
                    key code 9 using {command down}
                end tell
            on error errMsg2
                try
                    tell application "System Events"
                        keystroke "v" using command down
                    end tell
                on error errMsg3
                    return "All paste methods failed: " & errMsg3
                end try
            end try
        end try
        return "Paste completed successfully"
        """
        
        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Execute the script using osascript
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = [scriptPath.path]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            try task.run()
            task.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                Logger.shared.log("PasteManager: osascript output: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            
            if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                Logger.shared.log("PasteManager: osascript error: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
                // Clean up
                try? FileManager.default.removeItem(at: scriptPath)
                return false
            }
            
            // Clean up
            try FileManager.default.removeItem(at: scriptPath)
            return task.terminationStatus == 0
        } catch {
            Logger.shared.log("PasteManager: osascript paste failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // Fallback method: Just copy to clipboard and let user manually paste
    private func fallbackManualPaste() {
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = "Manual Paste Required"
            notification.informativeText = "Please press Cmd+V to paste the copied content."
            notification.soundName = NSUserNotificationDefaultSoundName
            
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
    
    private func showAccessibilityNotification() {
        let notification = NSUserNotification()
        notification.title = "Accessibility Permissions Required"
        notification.informativeText = "Clipboard Manager needs accessibility permissions to paste. Click to open settings."
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = true
        notification.actionButtonTitle = "Open Settings"
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    private func showPasteFailureNotification() {
        let notification = NSUserNotification()
        notification.title = "Paste Failed"
        notification.informativeText = "Could not automatically paste. Please press Cmd+V manually to paste."
        notification.soundName = NSUserNotificationDefaultSoundName
        
        NSUserNotificationCenter.default.deliver(notification)
    }
    
    // Method to check if the current application supports rich text pasting
    private func currentAppSupportsRichText() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        // List of apps known to support rich text pasting
        let richTextApps = [
            "com.apple.TextEdit",
            "com.apple.Notes",
            "com.apple.mail",
            "com.microsoft.Word",
            "com.microsoft.Outlook",
            "com.google.Chrome",
            "com.apple.Safari",
            "com.apple.Pages",
            "com.apple.iWork.Pages",
            "com.apple.finder" // For text fields in Finder
        ]
        
        if let bundleID = frontApp.bundleIdentifier, richTextApps.contains(bundleID) {
            return true
        }
        
        // For other apps, we'll assume they support rich text if they're not terminal apps
        let terminalApps = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "co.zeit.hyper",
            "com.microsoft.VSCode"
        ]
        
        if let bundleID = frontApp.bundleIdentifier, terminalApps.contains(bundleID) {
            return false
        }
        
        // Default to true for most GUI apps
        return true
    }
} 
