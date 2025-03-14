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
    func paste(isRichText: Bool = false, isImage: Bool = false) {
        Logger.shared.log("===== PASTE OPERATION START =====")
        Logger.shared.log("PasteManager: Starting paste operation" + (isRichText ? " (Rich Text)" : "") + (isImage ? " (Image)" : ""))
        
        // Set the rich text flag
        self.isRichTextPaste = isRichText || isImage // Treat images like rich text for pasting
        Logger.shared.log("Set isRichTextPaste to: \(self.isRichTextPaste)")
        
        // Check clipboard content
        let pasteboard = NSPasteboard.general
        var hasRichTextData = false
        var hasImageData = false
        
        // Check for image data
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            Logger.shared.log("Clipboard contains image data: \(imageData.count) bytes")
            hasImageData = true
        }
        
        if let rtfData = pasteboard.data(forType: .rtf) {
            Logger.shared.log("Clipboard contains RTF data: \(rtfData.count) bytes")
            hasRichTextData = true
        } else {
            Logger.shared.log("Clipboard does NOT contain RTF data")
            
            // Check for HTML data which can be treated as rich text
            if let htmlData = pasteboard.data(forType: .html) ?? 
                             pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: "Apple HTML pasteboard type")) {
                Logger.shared.log("Clipboard contains HTML data: \(htmlData.count) bytes")
                
                // Try to convert HTML to RTF
                do {
                    let attributedString = try NSAttributedString(
                        data: htmlData,
                        options: [.documentType: NSAttributedString.DocumentType.html],
                        documentAttributes: nil
                    )
                    
                    let rtfData = try attributedString.data(
                        from: NSRange(location: 0, length: attributedString.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                    )
                    
                    Logger.shared.log("Converted HTML to RTF: \(rtfData.count) bytes")
                    
                    // Set the RTF data to the clipboard
                    pasteboard.setData(rtfData, forType: .rtf)
                    
                    // Use writeObjects for better compatibility
                    pasteboard.writeObjects([attributedString])
                    
                    hasRichTextData = true
                } catch {
                    Logger.shared.log("Error converting HTML to RTF: \(error)")
                }
            }
        }
        
        if let stringData = pasteboard.string(forType: .string) {
            Logger.shared.log("Clipboard contains string data: \(stringData)")
        } else {
            Logger.shared.log("Clipboard does NOT contain string data")
        }
        
        // Check for accessibility permissions
        guard AXIsProcessTrusted() else {
            Logger.shared.log("PasteManager: Cannot paste - accessibility permissions not granted")
            // Show a notification to the user
            showAccessibilityNotification()
            // Request permissions via AppDelegate
            NotificationCenter.default.post(name: NSNotification.Name("RequestAccessibilityPermissions"), object: nil)
            Logger.shared.log("===== PASTE OPERATION FAILED (No Accessibility Permissions) =====")
            return
        }
        
        // Log environment information
        logEnvironmentInfo()
        
        // Try all paste methods in sequence with proper delays
        DispatchQueue.global(qos: .userInitiated).async {
            // Make sure the target application is active and not Clipboard Manager itself
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
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
                        Logger.shared.log("===== PASTE OPERATION FAILED (No Target App) =====")
                        return
                    }
                } else {
                    // Ensure the target application is fully activated
                    Logger.shared.log("PasteManager: Ensuring target app is activated: \(frontApp.localizedName ?? "Unknown")")
                    
                    // Activate the target application with options to bring it to front
                    if #available(macOS 14.0, *) {
                        // In macOS 14+, just use activate() as ignoringOtherApps has no effect
                        frontApp.activate(options: .activateAllWindows)
                    } else {
                        // For older macOS versions, use the previous API
                        frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    }
                    
                    // Give the app time to activate
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
            
            // If this is an image paste and we have image data, try the special image paste method first
            if isImage && hasImageData {
                Logger.shared.log("Detected image paste operation with image data")
                if self.tryImagePasteMethod() {
                    Logger.shared.log("PasteManager: Image paste succeeded")
                    Logger.shared.log("===== PASTE OPERATION COMPLETED (Image Method) =====")
                    return
                }
            }
            
            // If this is a rich text paste and we have rich text data, try the special rich text paste method first
            if self.isRichTextPaste && hasRichTextData {
                if self.tryRichTextPasteMethod() {
                    Logger.shared.log("PasteManager: Rich text paste succeeded")
                    Logger.shared.log("===== PASTE OPERATION COMPLETED (Rich Text Method) =====")
                    return
                }
            }
            
            // 1. Try direct paste with Command+V
            if self.tryDirectPasteMethod() {
                Logger.shared.log("PasteManager: Direct paste succeeded")
                Logger.shared.log("===== PASTE OPERATION COMPLETED (Direct Method) =====")
                return
            }
            
            // 2. Try AppleScript methods
            Thread.sleep(forTimeInterval: 0.3)
            if self.tryAppleScriptPasteMethods() {
                Logger.shared.log("PasteManager: AppleScript paste succeeded")
                Logger.shared.log("===== PASTE OPERATION COMPLETED (AppleScript Method) =====")
                return
            }
            
            // 3. Try osascript as a last resort
            Thread.sleep(forTimeInterval: 0.3)
            if self.tryOsascriptPaste() {
                Logger.shared.log("PasteManager: osascript paste succeeded")
                Logger.shared.log("===== PASTE OPERATION COMPLETED (Osascript Method) =====")
                return
            }
            
            // 4. If all else fails, notify the user
            DispatchQueue.main.async {
                self.showPasteFailureNotification()
            }
            Logger.shared.log("===== PASTE OPERATION FAILED (All Methods Failed) =====")
        }
    }
    
    // Method to paste to a specific target application without changing focus
    func pasteToApp(targetApp: NSRunningApplication, isRichText: Bool = false, isImage: Bool = false) {
        Logger.shared.log("===== PASTE TO APP OPERATION START =====")
        Logger.shared.log("PasteManager: Starting paste to app operation" + (isRichText ? " (Rich Text)" : "") + (isImage ? " (Image)" : ""))
        Logger.shared.log("Target application: \(targetApp.localizedName ?? "Unknown") (Bundle ID: \(targetApp.bundleIdentifier ?? "unknown"))")
        
        // Set the rich text flag
        self.isRichTextPaste = isRichText || isImage // Treat images like rich text for pasting
        Logger.shared.log("Set isRichTextPaste to: \(self.isRichTextPaste)")
        
        // Check clipboard content
        let pasteboard = NSPasteboard.general
        var hasRichTextData = false
        var hasImageData = false
        
        // Check for image data
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            Logger.shared.log("Clipboard contains image data: \(imageData.count) bytes")
            hasImageData = true
        }
        
        if let rtfData = pasteboard.data(forType: .rtf) {
            Logger.shared.log("Clipboard contains RTF data: \(rtfData.count) bytes")
            hasRichTextData = true
        }
        
        if let stringData = pasteboard.string(forType: .string) {
            Logger.shared.log("Clipboard contains string data: \(stringData)")
        } else {
            Logger.shared.log("Clipboard does NOT contain string data")
        }
        
        // Check for accessibility permissions
        guard AXIsProcessTrusted() else {
            Logger.shared.log("PasteManager: Cannot paste - accessibility permissions not granted")
            // Show a notification to the user
            showAccessibilityNotification()
            // Request permissions via AppDelegate
            NotificationCenter.default.post(name: NSNotification.Name("RequestAccessibilityPermissions"), object: nil)
            Logger.shared.log("===== PASTE TO APP OPERATION FAILED (No Accessibility Permissions) =====")
            return
        }
        
        // Log environment information
        logEnvironmentInfo()
        
        // Try all paste methods in sequence with proper delays
        DispatchQueue.global(qos: .userInitiated).async {
            // Ensure the frontmost application is not our app
            if targetApp.bundleIdentifier == Bundle.main.bundleIdentifier {
                Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
                Logger.shared.log("===== PASTE TO APP OPERATION FAILED (Target is Clipboard Manager) =====")
                return
            }
            
            // Get the app name for AppleScript
            guard let appName = targetApp.localizedName else {
                Logger.shared.log("PasteManager: Cannot determine target app name")
                Logger.shared.log("===== PASTE TO APP OPERATION FAILED (No App Name) =====")
                return
            }
            
            // Try AppleScript paste methods first as they're more reliable for targeting specific apps
            if self.tryAppleScriptPasteToApp(appName: appName, isRichText: isRichText, isImage: isImage) {
                Logger.shared.log("PasteManager: AppleScript paste to app succeeded")
                Logger.shared.log("===== PASTE TO APP OPERATION COMPLETED (AppleScript Method) =====")
                return
            }
            
            // If AppleScript fails, try osascript as a fallback
            if self.tryOsascriptPasteToApp(appName: appName, isRichText: isRichText, isImage: isImage) {
                Logger.shared.log("PasteManager: osascript paste to app succeeded")
                Logger.shared.log("===== PASTE TO APP OPERATION COMPLETED (Osascript Method) =====")
                return
            }
            
            // If all else fails, try the direct paste method
            // This requires activating the app, which might disrupt cursor position
            Logger.shared.log("PasteManager: AppleScript methods failed, falling back to direct paste")
            
            // Activate the target application with options to bring it to front
            if #available(macOS 14.0, *) {
                // In macOS 14+, just use activate() as ignoringOtherApps has no effect
                targetApp.activate(options: .activateAllWindows)
            } else {
                // For older macOS versions, use the previous API
                targetApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            
            // Give the app time to activate
            Thread.sleep(forTimeInterval: 0.2)
            
            // Try direct paste method
            if self.tryDirectPasteMethod() {
                Logger.shared.log("PasteManager: Direct paste method succeeded")
                Logger.shared.log("===== PASTE TO APP OPERATION COMPLETED (Direct Method) =====")
                return
            }
            
            // If all else fails, notify the user
            DispatchQueue.main.async {
                self.showPasteFailureNotification()
            }
            Logger.shared.log("===== PASTE TO APP OPERATION FAILED (All Methods Failed) =====")
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
        Logger.shared.log("===== DIRECT PASTE METHOD START =====")
        Logger.shared.log("PasteManager: Trying direct paste method")
        Logger.shared.log("isRichTextPaste: \(isRichTextPaste)")
        
        // Check clipboard content again right before pasting
        let pasteboard = NSPasteboard.general
        var hasImageData = false
        
        // Check for image data
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            Logger.shared.log("Clipboard contains image data before paste: \(imageData.count) bytes")
            hasImageData = true
            
            // For images, make sure we have a valid NSImage
            if let image = NSImage(data: imageData) {
                Logger.shared.log("Valid image found: \(image.size.width)x\(image.size.height)")
                
                // Ensure the image is properly set on the clipboard
                pasteboard.clearContents()
                let success = pasteboard.writeObjects([image])
                Logger.shared.log("Re-wrote image to clipboard: \(success)")
            }
        }
        
        if let rtfData = pasteboard.data(forType: .rtf) {
            Logger.shared.log("Clipboard contains RTF data before paste: \(rtfData.count) bytes")
            
            // Add more detailed logging for RTF data
            if isRichTextPaste {
                // Try to convert RTF to attributed string to see the actual content
                do {
                    let attributedString = try NSAttributedString(
                        data: rtfData,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                    Logger.shared.log("RTF content as plain text: \(attributedString.string)")
                } catch {
                    Logger.shared.log("Error converting RTF to attributed string: \(error)")
                }
            }
        } else {
            Logger.shared.log("Clipboard does NOT contain RTF data before paste")
        }
        
        if let stringData = pasteboard.string(forType: .string) {
            Logger.shared.log("Clipboard contains string data before paste: \(stringData)")
        } else {
            Logger.shared.log("Clipboard does NOT contain string data before paste")
        }
        
        // Log all available types on the clipboard
        Logger.shared.log("All available clipboard types: \(pasteboard.types?.map { $0.rawValue } ?? [])")
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            Logger.shared.log("===== DIRECT PASTE METHOD FAILED =====")
            return false
        }
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            Logger.shared.log("===== DIRECT PASTE METHOD FAILED =====")
            return false
        }
        
        // Ensure the target application is fully activated
        Logger.shared.log("PasteManager: Ensuring target app is activated: \(frontApp.localizedName ?? "Unknown")")
        
        // Activate the target application with options to bring it to front
        if #available(macOS 14.0, *) {
            // In macOS 14+, just use activate() as ignoringOtherApps has no effect
            frontApp.activate(options: .activateAllWindows)
        } else {
            // For older macOS versions, use the previous API
            frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        
        // Make sure the target application has focus
        // Small delay to ensure the app is ready to receive keyboard events
        Thread.sleep(forTimeInterval: 0.2)
        
        // Create a source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Logger.shared.log("PasteManager: Failed to create event source")
            Logger.shared.log("===== DIRECT PASTE METHOD FAILED =====")
            return false
        }
        
        Logger.shared.log("PasteManager: CGEventSource creation successful")
        
        // Create key down event for Command+V
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) else {
            Logger.shared.log("PasteManager: Failed to create keydown event")
            Logger.shared.log("===== DIRECT PASTE METHOD FAILED =====")
            return false
        }
        keyVDown.flags = .maskCommand
        
        // Create key up event for Command+V
        guard let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            Logger.shared.log("PasteManager: Failed to create keyup event")
            Logger.shared.log("===== DIRECT PASTE METHOD FAILED =====")
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
        Logger.shared.log("===== DIRECT PASTE METHOD END =====")
        
        // Return true to indicate we attempted the method
        // We can't really know if it succeeded
        return true
    }
    
    // AppleScript paste methods
    private func tryAppleScriptPasteMethods() -> Bool {
        Logger.shared.log("PasteManager: Trying AppleScript paste methods")
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            return false
        }
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            return false
        }
        
        Logger.shared.log("PasteManager: Target application for AppleScript paste: \(appName)")
        
        // Different AppleScript approaches that specifically target the frontmost app
        let scripts = [
            // Target specific app with activation
            """
            tell application "\(appName)"
                activate
                delay 0.2
                tell application "System Events"
                    tell process "\(appName)"
                        keystroke "v" using command down
                    end tell
                end tell
            end tell
            """,
            
            // Basic approach with explicit app targeting
            """
            tell application "System Events"
                tell application process "\(appName)"
                    keystroke "v" using command down
                end tell
            end tell
            """,
            
            // Target frontmost app with explicit check
            """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                if name of frontApp is "\(appName)" then
                    tell frontApp
                        keystroke "v" using command down
                    end tell
                end if
            end tell
            """,
            
            // With delays and explicit app targeting
            """
            tell application "\(appName)"
                activate
                delay 0.2
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.1
                        keystroke "v" using command down
                        delay 0.1
                    end tell
                end tell
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
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            return false
        }
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            return false
        }
        
        Logger.shared.log("PasteManager: Target application for osascript paste: \(appName)")
        
        // Create a temporary AppleScript file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("paste_script.scpt")
        
        // More robust script with multiple approaches and explicit app targeting
        let scriptContent = """
        try
            tell application "\(appName)"
                activate
                delay 0.2
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.1
                        keystroke "v" using command down
                        delay 0.1
                    end tell
                end tell
            end tell
        on error errMsg
            try
                tell application "System Events"
                    tell application process "\(appName)"
                        key code 9 using {command down}
                    end tell
                end tell
            on error errMsg2
                try
                    tell application "\(appName)"
                        activate
                        delay 0.2
                        tell application "System Events"
                            keystroke "v" using command down
                        end tell
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
    
    // Special method for pasting rich text
    private func tryRichTextPasteMethod() -> Bool {
        Logger.shared.log("===== RICH TEXT PASTE METHOD START =====")
        Logger.shared.log("PasteManager: Trying rich text paste method")
        
        // Check clipboard content again right before pasting
        let pasteboard = NSPasteboard.general
        var rtfData: Data? = nil
        var attributedString: NSAttributedString? = nil
        var hasImageData = false
        
        // Check for image data
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            hasImageData = true
            Logger.shared.log("Clipboard contains image data before rich text paste: \(imageData.count) bytes")
        }
        
        // First check for RTF data
        if let data = pasteboard.data(forType: .rtf) {
            rtfData = data
            Logger.shared.log("Clipboard contains RTF data before rich text paste: \(data.count) bytes")
            
            // Try to convert RTF to attributed string
            do {
                attributedString = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                Logger.shared.log("RTF content as plain text: \(attributedString!.string)")
            } catch {
                Logger.shared.log("Error converting RTF to attributed string: \(error)")
            }
        } 
        // If no RTF data, check for HTML data
        else if let htmlData = pasteboard.data(forType: .html) ?? 
                              pasteboard.data(forType: NSPasteboard.PasteboardType(rawValue: "Apple HTML pasteboard type")) {
            Logger.shared.log("Clipboard contains HTML data before rich text paste: \(htmlData.count) bytes")
            
            // Try to convert HTML to attributed string and then to RTF
            do {
                attributedString = try NSAttributedString(
                    data: htmlData,
                    options: [.documentType: NSAttributedString.DocumentType.html],
                    documentAttributes: nil
                )
                Logger.shared.log("HTML content as plain text: \(attributedString!.string)")
                
                // Create a mutable copy to ensure we can modify attributes if needed
                let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString!)
                
                // Check if the text has any color attributes
                let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
                var hasColorAttribute = false
                mutableAttributedString.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
                    if value != nil {
                        hasColorAttribute = true
                    }
                }
                
                // If no explicit color is set, apply white color to ensure visibility in RTF documents
                if !hasColorAttribute {
                    Logger.shared.log("No color attribute found in HTML, applying explicit white color for RTF compatibility")
                    mutableAttributedString.addAttribute(.foregroundColor, value: NSColor.white, range: fullRange)
                }
                
                // Update the attributed string reference
                attributedString = mutableAttributedString
                
                // Convert to RTF data
                rtfData = try attributedString!.data(
                    from: NSRange(location: 0, length: attributedString!.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                Logger.shared.log("Converted HTML to RTF data: \(rtfData!.count) bytes")
            } catch {
                Logger.shared.log("Error converting HTML to attributed string: \(error)")
            }
        }
        
        // If we couldn't get RTF data or attributed string, fail
        if rtfData == nil || attributedString == nil {
            Logger.shared.log("Clipboard does NOT contain RTF or HTML data before rich text paste")
            Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
            return false
        }
        
        // Create a new attributed string with the same attributes to ensure formatting is preserved
        Logger.shared.log("Creating fresh attributed string to ensure formatting is preserved")
        let newAttributedString = NSMutableAttributedString(attributedString: attributedString!)
        
        // Check if the text has any color attributes
        let fullRange = NSRange(location: 0, length: newAttributedString.length)
        var hasColorAttribute = false
        newAttributedString.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value != nil {
                hasColorAttribute = true
            }
        }
        
        // If no explicit color is set, apply white color to ensure visibility in RTF documents
        if !hasColorAttribute {
            Logger.shared.log("No color attribute found in final attributed string, applying explicit white color for RTF compatibility")
            newAttributedString.addAttribute(.foregroundColor, value: NSColor.white, range: fullRange)
        }
        
        // Clear the pasteboard and set the attributed string directly
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([newAttributedString])
        Logger.shared.log("Writing fresh attributed string to pasteboard: \(success)")
        
        // Also set the RTF data for all common RTF formats to maximize compatibility
        let rtfFormats: [NSPasteboard.PasteboardType] = [
            .rtf,
            .init("NeXT Rich Text Format v1.0 pasteboard type"),
            .init("com.apple.notes.richtext"),
            .init("public.rtf"),
            .init("Apple Rich Text Format")
        ]
        
        // Get the fresh RTF data from the attributed string
        do {
            let freshRtfData = try newAttributedString.data(
                from: NSRange(location: 0, length: newAttributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            
            Logger.shared.log("Created fresh RTF data: \(freshRtfData.count) bytes")
            
            for format in rtfFormats {
                pasteboard.setData(freshRtfData, forType: format)
                Logger.shared.log("Set fresh RTF data for format: \(format.rawValue)")
            }
            
            // Also set plain text as fallback
            pasteboard.setString(attributedString!.string, forType: .string)
            Logger.shared.log("Set plain text fallback: \(attributedString!.string)")
        } catch {
            Logger.shared.log("Error creating fresh RTF data: \(error)")
            
            // Use the original RTF data as fallback
            for format in rtfFormats {
                pasteboard.setData(rtfData!, forType: format)
                Logger.shared.log("Set original RTF data for format: \(format.rawValue)")
            }
            
            // Also set plain text as fallback
            pasteboard.setString(attributedString!.string, forType: .string)
            Logger.shared.log("Set plain text fallback: \(attributedString!.string)")
        }
        
        // Log all available types on the clipboard
        Logger.shared.log("All available clipboard types: \(pasteboard.types?.map { $0.rawValue } ?? [])")
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
            return false
        }
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
            return false
        }
        
        Logger.shared.log("PasteManager: Frontmost app for rich text paste: \(appName)")
        
        // Ensure the target application is fully activated
        Logger.shared.log("PasteManager: Ensuring target app is activated: \(appName)")
        
        // Activate the target application with options to bring it to front
        if #available(macOS 14.0, *) {
            // In macOS 14+, just use activate() as ignoringOtherApps has no effect
            frontApp.activate(options: .activateAllWindows)
        } else {
            // For older macOS versions, use the previous API
            frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        
        // Give the app time to fully activate
        Thread.sleep(forTimeInterval: 0.2)
        
        // Try multiple AppleScript approaches for rich text pasting
        let scriptOptions = [
            // Option 1: Use Edit menu's Paste command with explicit app targeting
            """
            tell application "\(appName)"
                activate
                delay 0.2
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.2
                        click menu item "Paste" of menu "Edit" of menu bar 1
                        delay 0.2
                    end tell
                end tell
            end tell
            """,
            
            // Option 2: Use Command+V but with longer delays and explicit app targeting
            """
            tell application "\(appName)"
                activate
                delay 0.3
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.3
                        keystroke "v" using command down
                        delay 0.3
                    end tell
                end tell
            end tell
            """,
            
            // Option 3: Try to paste with formatting explicitly with explicit app targeting
            """
            tell application "\(appName)"
                activate
                delay 0.2
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.2
                        try
                            click menu item "Paste with Formatting" of menu "Edit" of menu bar 1
                        on error
                            click menu item "Paste" of menu "Edit" of menu bar 1
                        end try
                        delay 0.2
                    end tell
                end tell
            end tell
            """
        ]
        
        // Try each script option
        for (index, scriptText) in scriptOptions.enumerated() {
            Logger.shared.log("PasteManager: Trying rich text paste AppleScript option \(index + 1)")
            
            let script = NSAppleScript(source: scriptText)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            
            if let error = error {
                Logger.shared.log("PasteManager: Rich text paste AppleScript option \(index + 1) failed: \(error)")
                // Try the next option
                Thread.sleep(forTimeInterval: 0.2)
            } else {
                Logger.shared.log("PasteManager: Rich text paste AppleScript option \(index + 1) succeeded")
                Logger.shared.log("===== RICH TEXT PASTE METHOD END =====")
                return true
            }
        }
        
        // If all options failed, try one more approach with osascript
        Logger.shared.log("PasteManager: All AppleScript options failed, trying osascript approach")
        
        do {
            // Create a temporary AppleScript file
            let tempDir = FileManager.default.temporaryDirectory
            let scriptPath = tempDir.appendingPathComponent("rich_paste_script.scpt")
            
            let scriptContent = """
            tell application "\(appName)"
                activate
                delay 0.3
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.3
                        try
                            click menu item "Paste with Formatting" of menu "Edit" of menu bar 1
                        on error
                            try
                                click menu item "Paste" of menu "Edit" of menu bar 1
                            on error
                                keystroke "v" using command down
                            end try
                        end try
                        delay 0.3
                    end tell
                end tell
            end tell
            """
            
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Execute the script using osascript
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = [scriptPath.path]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            
            try task.run()
            task.waitUntilExit()
            
            // Clean up
            try FileManager.default.removeItem(at: scriptPath)
            
            if task.terminationStatus == 0 {
                Logger.shared.log("PasteManager: osascript approach succeeded")
                Logger.shared.log("===== RICH TEXT PASTE METHOD END =====")
                return true
            } else {
                Logger.shared.log("PasteManager: osascript approach failed")
            }
        } catch {
            Logger.shared.log("PasteManager: osascript error: \(error)")
        }
        
        // If all else fails, try direct paste method
        if tryDirectPasteMethod() {
            Logger.shared.log("PasteManager: Direct paste method succeeded for rich text")
            Logger.shared.log("===== RICH TEXT PASTE METHOD END =====")
            return true
        }
        
        Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
        return false
    }
    
    // Special method for pasting images
    private func tryImagePasteMethod() -> Bool {
        Logger.shared.log("===== IMAGE PASTE METHOD START =====")
        Logger.shared.log("PasteManager: Trying image paste method")
        
        // Check clipboard content again right before pasting
        let pasteboard = NSPasteboard.general
        var imageData: Data? = nil
        var hasImageData = false
        
        // Check for image data
        if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            imageData = data
            hasImageData = true
            Logger.shared.log("Clipboard contains image data before image paste: \(data.count) bytes")
        }
        
        // If we couldn't get image data, fail
        if !hasImageData || imageData == nil {
            Logger.shared.log("Clipboard does NOT contain image data before image paste")
            Logger.shared.log("===== IMAGE PASTE METHOD FAILED =====")
            return false
        }
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            Logger.shared.log("===== IMAGE PASTE METHOD FAILED =====")
            return false
        }
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            Logger.shared.log("===== IMAGE PASTE METHOD FAILED =====")
            return false
        }
        
        Logger.shared.log("PasteManager: Frontmost app for image paste: \(appName)")
        
        // Ensure the target application is fully activated
        Logger.shared.log("PasteManager: Ensuring target app is activated: \(appName)")
        
        // Activate the target application with options to bring it to front
        if #available(macOS 14.0, *) {
            // In macOS 14+, just use activate() as ignoringOtherApps has no effect
            frontApp.activate(options: .activateAllWindows)
        } else {
            // For older macOS versions, use the previous API
            frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        
        // Give the app time to fully activate
        Thread.sleep(forTimeInterval: 0.2)
        
        // Try multiple AppleScript approaches for image pasting
        let scriptOptions = [
            // Option 1: Use Edit menu's Paste command with explicit app targeting
            """
            tell application "\(appName)"
                activate
                delay 0.2
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.2
                        click menu item "Paste" of menu "Edit" of menu bar 1
                        delay 0.2
                    end tell
                end tell
            end tell
            """,
            
            // Option 2: Use Command+V but with longer delays and explicit app targeting
            """
            tell application "\(appName)"
                activate
                delay 0.3
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.3
                        keystroke "v" using command down
                        delay 0.3
                    end tell
                end tell
            end tell
            """
        ]
        
        // Try each script option
        for (index, scriptText) in scriptOptions.enumerated() {
            Logger.shared.log("PasteManager: Trying image paste AppleScript option \(index + 1)")
            
            let script = NSAppleScript(source: scriptText)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            
            if let error = error {
                Logger.shared.log("PasteManager: Image paste AppleScript option \(index + 1) failed: \(error)")
                // Try the next option
                Thread.sleep(forTimeInterval: 0.2)
            } else {
                Logger.shared.log("PasteManager: Image paste AppleScript option \(index + 1) succeeded")
                Logger.shared.log("===== IMAGE PASTE METHOD END =====")
                return true
            }
        }
        
        // If all options failed, try one more approach with osascript
        Logger.shared.log("PasteManager: All AppleScript options failed, trying osascript approach")
        
        do {
            // Create a temporary AppleScript file
            let tempDir = FileManager.default.temporaryDirectory
            let scriptPath = tempDir.appendingPathComponent("image_paste_script.scpt")
            
            let scriptContent = """
            tell application "\(appName)"
                activate
                delay 0.3
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.3
                        try
                            click menu item "Paste" of menu "Edit" of menu bar 1
                        on error
                            keystroke "v" using command down
                        end try
                        delay 0.3
                    end tell
                end tell
            end tell
            """
            
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Execute the script using osascript
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = [scriptPath.path]
            
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            
            try task.run()
            task.waitUntilExit()
            
            // Clean up
            try FileManager.default.removeItem(at: scriptPath)
            
            if task.terminationStatus == 0 {
                Logger.shared.log("PasteManager: osascript approach succeeded")
                Logger.shared.log("===== IMAGE PASTE METHOD END =====")
                return true
            } else {
                Logger.shared.log("PasteManager: osascript approach failed")
            }
        } catch {
            Logger.shared.log("PasteManager: osascript error: \(error)")
        }
        
        // If all else fails, try direct paste method
        if tryDirectPasteMethod() {
            Logger.shared.log("PasteManager: Direct paste method succeeded for image")
            Logger.shared.log("===== IMAGE PASTE METHOD END =====")
            return true
        }
        
        Logger.shared.log("===== IMAGE PASTE METHOD FAILED =====")
        return false
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
    
    // AppleScript paste methods specifically targeting an app
    private func tryAppleScriptPasteToApp(appName: String, isRichText: Bool = false, isImage: Bool = false) -> Bool {
        Logger.shared.log("PasteManager: Trying AppleScript paste to app: \(appName)")
        
        // Different AppleScript approaches that specifically target the app
        var scripts = [String]()
        
        if isRichText || isImage {
            // For rich text or images, try menu item paste first
            scripts.append("""
            tell application "\(appName)"
                tell application "System Events"
                    tell process "\(appName)"
                        delay 0.1
                        try
                            click menu item "Paste" of menu "Edit" of menu bar 1
                        on error
                            keystroke "v" using command down
                        end try
                        delay 0.1
                    end tell
                end tell
            end tell
            """)
            
            // For rich text, also try paste with formatting
            if isRichText {
                scripts.append("""
                tell application "\(appName)"
                    tell application "System Events"
                        tell process "\(appName)"
                            delay 0.1
                            try
                                click menu item "Paste with Formatting" of menu "Edit" of menu bar 1
                            on error
                                click menu item "Paste" of menu "Edit" of menu bar 1
                            end try
                            delay 0.1
                        end tell
                    end tell
                end tell
                """)
            }
        }
        
        // Add standard command+v paste for all types
        scripts.append("""
        tell application "\(appName)"
            tell application "System Events"
                tell process "\(appName)"
                    delay 0.1
                    keystroke "v" using command down
                    delay 0.1
                end tell
            end tell
        end tell
        """)
        
        // Try each script
        for (index, scriptText) in scripts.enumerated() {
            Logger.shared.log("PasteManager: Trying AppleScript paste to app method \(index + 1)")
            
            let script = NSAppleScript(source: scriptText)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            
            if let error = error {
                Logger.shared.log("PasteManager: AppleScript paste to app method \(index + 1) failed: \(error)")
            } else {
                Logger.shared.log("PasteManager: AppleScript paste to app method \(index + 1) succeeded")
                return true
            }
            
            // Small delay between attempts
            usleep(100000) // 100ms
        }
        
        Logger.shared.log("PasteManager: All AppleScript paste to app methods failed")
        return false
    }
    
    // Shell script paste method using osascript targeting a specific app
    private func tryOsascriptPasteToApp(appName: String, isRichText: Bool = false, isImage: Bool = false) -> Bool {
        Logger.shared.log("PasteManager: Trying osascript paste to app: \(appName)")
        
        // Create a temporary AppleScript file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("paste_to_app_script.scpt")
        
        // More robust script with multiple approaches
        let scriptContent: String
        
        if isRichText {
            scriptContent = """
            try
                tell application "\(appName)"
                    tell application "System Events"
                        tell process "\(appName)"
                            delay 0.1
                            try
                                click menu item "Paste with Formatting" of menu "Edit" of menu bar 1
                            on error
                                try
                                    click menu item "Paste" of menu "Edit" of menu bar 1
                                on error
                                    keystroke "v" using command down
                                end try
                            end try
                            delay 0.1
                        end tell
                    end tell
                end tell
            on error errMsg
                try
                    tell application "\(appName)"
                        tell application "System Events"
                            tell process "\(appName)"
                                delay 0.1
                                keystroke "v" using command down
                                delay 0.1
                            end tell
                        end tell
                    end tell
                on error errMsg2
                    return "All paste methods failed: " & errMsg2
                end try
            end try
            return "Paste completed successfully"
            """
        } else if isImage {
            scriptContent = """
            try
                tell application "\(appName)"
                    tell application "System Events"
                        tell process "\(appName)"
                            delay 0.1
                            try
                                click menu item "Paste" of menu "Edit" of menu bar 1
                            on error
                                keystroke "v" using command down
                            end try
                            delay 0.1
                        end tell
                    end tell
                end tell
            on error errMsg
                try
                    tell application "\(appName)"
                        tell application "System Events"
                            tell process "\(appName)"
                                delay 0.1
                                keystroke "v" using command down
                                delay 0.1
                            end tell
                        end tell
                    end tell
                on error errMsg2
                    return "All paste methods failed: " & errMsg2
                end try
            end try
            return "Paste completed successfully"
            """
        } else {
            // Plain text - simpler script
            scriptContent = """
            try
                tell application "\(appName)"
                    tell application "System Events"
                        tell process "\(appName)"
                            delay 0.1
                            keystroke "v" using command down
                            delay 0.1
                        end tell
                    end tell
                end tell
            on error errMsg
                return "Paste failed: " & errMsg
            end try
            return "Paste completed successfully"
            """
        }
        
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
            Logger.shared.log("PasteManager: osascript paste to app failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // Universal paste method that works with any application
    func universalPaste() {
        Logger.shared.log("===== UNIVERSAL PASTE OPERATION START =====")
        Logger.shared.log("PasteManager: Starting universal paste operation")
        
        // Check for accessibility permissions
        guard AXIsProcessTrusted() else {
            Logger.shared.log("PasteManager: Cannot paste - accessibility permissions not granted")
            // Show a notification to the user
            showAccessibilityNotification()
            // Request permissions via AppDelegate
            NotificationCenter.default.post(name: NSNotification.Name("RequestAccessibilityPermissions"), object: nil)
            Logger.shared.log("===== UNIVERSAL PASTE OPERATION FAILED (No Accessibility Permissions) =====")
            return
        }
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            Logger.shared.log("===== UNIVERSAL PASTE OPERATION FAILED (No Frontmost App) =====")
            return
        }
        
        // Log the target application
        Logger.shared.log("PasteManager: Target application for paste: \(frontApp.localizedName ?? "Unknown") (Bundle ID: \(frontApp.bundleIdentifier ?? "unknown"))")
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            
            // Try to find another application to paste to
            if let previousApp = NSWorkspace.shared.runningApplications.first(where: { 
                $0.isActive == false && 
                $0.bundleIdentifier != Bundle.main.bundleIdentifier && 
                $0.activationPolicy == .regular 
            }) {
                Logger.shared.log("PasteManager: Found alternative app to paste to: \(previousApp.localizedName ?? "Unknown")")
                
                // Skip the ensureApplicationActivation method and directly activate
                // This is more direct and less likely to cause Finder to become active
                if #available(macOS 14.0, *) {
                    previousApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                } else {
                    previousApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                }
                
                // Small delay to ensure activation takes effect
                Thread.sleep(forTimeInterval: 0.1)
                
                // Verify the app was actually activated
                if let currentFrontApp = NSWorkspace.shared.frontmostApplication,
                   currentFrontApp.bundleIdentifier == previousApp.bundleIdentifier {
                    Logger.shared.log("PasteManager: Successfully activated alternative app")
                    // Directly try the most reliable paste method
                    tryUniversalDirectPaste()
                } else {
                    Logger.shared.log("PasteManager: Failed to activate alternative app, trying again with longer delay")
                    // Try again with a longer delay
                    Thread.sleep(forTimeInterval: 0.2)
                    previousApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                    Thread.sleep(forTimeInterval: 0.2)
                    tryUniversalDirectPaste()
                }
                return
            } else {
                Logger.shared.log("PasteManager: Could not find a suitable target application")
                DispatchQueue.main.async {
                    self.showPasteFailureNotification()
                }
                Logger.shared.log("===== UNIVERSAL PASTE OPERATION FAILED (No Target App) =====")
                return
            }
        }
        
        // Skip the ensureApplicationActivation method and directly activate
        // This is more direct and less likely to cause Finder to become active
        if #available(macOS 14.0, *) {
            frontApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        } else {
            frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        }
        
        // Small delay to ensure activation takes effect
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify the app is still frontmost
        if let currentFrontApp = NSWorkspace.shared.frontmostApplication, 
           currentFrontApp.bundleIdentifier == frontApp.bundleIdentifier {
            Logger.shared.log("PasteManager: Target app is confirmed frontmost, proceeding with paste")
            // Directly try the most reliable paste method
            tryUniversalDirectPaste()
        } else {
            Logger.shared.log("PasteManager: Target app is not frontmost, trying to reactivate")
            // Try to reactivate the app with stronger options
            if #available(macOS 14.0, *) {
                frontApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            } else {
                frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            Thread.sleep(forTimeInterval: 0.2)
            tryUniversalDirectPaste()
        }
    }
    
    // Helper method to perform a universal paste to the frontmost application
    private func universalPasteToFrontmostApp() {
        // Try multiple paste methods in sequence
        DispatchQueue.global(qos: .userInteractive).async {
            // 0. Try app-specific paste methods first if applicable
            if self.tryAppSpecificPaste() {
                Logger.shared.log("PasteManager: App-specific paste succeeded")
                Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (App-Specific Method) =====")
                return
            }
            
            // 1. Try direct paste with Command+V (most universal)
            if self.tryUniversalDirectPaste() {
                Logger.shared.log("PasteManager: Universal direct paste succeeded")
                Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (Direct Method) =====")
                return
            }
            
            // 2. Try AppleScript methods
            Thread.sleep(forTimeInterval: 0.05)
            if self.tryUniversalAppleScriptPaste() {
                Logger.shared.log("PasteManager: Universal AppleScript paste succeeded")
                Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (AppleScript Method) =====")
                return
            }
            
            // 3. Try direct NSPasteboard manipulation
            Thread.sleep(forTimeInterval: 0.05)
            if self.tryDirectNSPasteboardPaste() {
                // If we successfully manipulated the pasteboard, try the direct paste method again
                Thread.sleep(forTimeInterval: 0.1)
                if self.tryUniversalDirectPaste() {
                    Logger.shared.log("PasteManager: NSPasteboard refresh + direct paste succeeded")
                    Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (NSPasteboard Refresh Method) =====")
                    return
                }
            }
            
            // 4. Try osascript as a fallback
            Thread.sleep(forTimeInterval: 0.05)
            if self.tryUniversalOsascriptPaste() {
                Logger.shared.log("PasteManager: Universal osascript paste succeeded")
                Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (Osascript Method) =====")
                return
            }
            
            // 5. Try NSResponder paste as a last resort
            Thread.sleep(forTimeInterval: 0.05)
            if self.tryNSResponderPaste() {
                Logger.shared.log("PasteManager: NSResponder paste succeeded")
                Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (NSResponder Method) =====")
                return
            }
            
            // 6. If all else fails, try one more direct paste with longer delays
            Thread.sleep(forTimeInterval: 0.1)
            Logger.shared.log("PasteManager: Trying final direct paste with longer delays")
            
            // Create a source
            if let source = CGEventSource(stateID: .combinedSessionState) {
                // Create key down event for Command+V
                if let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) {
                    keyVDown.flags = .maskCommand
                    
                    // Create key up event for Command+V
                    if let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
                        keyVUp.flags = .maskCommand
                        
                        // Post the events with longer delays
                        Logger.shared.log("PasteManager: Posting final keydown event...")
                        keyVDown.post(tap: .cghidEventTap)
                        
                        // Much longer delay between keydown and keyup
                        Thread.sleep(forTimeInterval: 0.2)
                        
                        Logger.shared.log("PasteManager: Posting final keyup event...")
                        keyVUp.post(tap: .cghidEventTap)
                        
                        Logger.shared.log("PasteManager: Final direct paste attempt completed")
                        Logger.shared.log("===== UNIVERSAL PASTE OPERATION COMPLETED (Final Direct Method) =====")
                        return
                    }
                }
            }
            
            // 7. If all else fails, notify the user
            DispatchQueue.main.async {
                self.showPasteFailureNotification()
            }
            Logger.shared.log("===== UNIVERSAL PASTE OPERATION FAILED (All Methods Failed) =====")
        }
    }
    
    // Direct universal paste method using CGEvent
    private func tryUniversalDirectPaste() -> Bool {
        Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD START =====")
        Logger.shared.log("PasteManager: Trying universal direct paste method")
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            Logger.shared.log("PasteManager: Cannot determine frontmost application")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (No Frontmost App) =====")
            return false
        }
        
        // Log the target application
        Logger.shared.log("PasteManager: Target application for paste: \(frontApp.localizedName ?? "Unknown") (Bundle ID: \(frontApp.bundleIdentifier ?? "unknown"))")
        
        // Ensure the frontmost application is not our app
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Target is Clipboard Manager) =====")
            return false
        }
        
        // Verify the target application is still frontmost before proceeding
        // This is crucial to prevent Finder from becoming active
        if let currentFrontApp = NSWorkspace.shared.frontmostApplication,
           currentFrontApp.bundleIdentifier != frontApp.bundleIdentifier {
            Logger.shared.log("PasteManager: Target application is no longer frontmost. Current frontmost: \(currentFrontApp.localizedName ?? "Unknown")")
            
            // Try to reactivate the target application
            Logger.shared.log("PasteManager: Attempting to reactivate target application")
            if #available(macOS 14.0, *) {
                frontApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            } else {
                frontApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            }
            
            // Small delay to ensure activation takes effect
            Thread.sleep(forTimeInterval: 0.1)
            
            // Verify activation again
            if let verifyFrontApp = NSWorkspace.shared.frontmostApplication,
               verifyFrontApp.bundleIdentifier != frontApp.bundleIdentifier {
                Logger.shared.log("PasteManager: Failed to reactivate target application")
                Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Cannot Activate Target) =====")
                return false
            }
        }
        
        // Create a source with HID state for more accurate simulation
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            Logger.shared.log("PasteManager: Failed to create HID event source")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (No Event Source) =====")
            return false
        }
        
        // The 'v' key has virtual keycode 9
        let vKeyCode: CGKeyCode = 9
        let cmdKeyCode: CGKeyCode = 0x37 // Command key code
        
        // Create key down event for Command key first
        guard let cmdKeyDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true) else {
            Logger.shared.log("PasteManager: Failed to create Command key down event")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Cannot Create Command Down Event) =====")
            return false
        }
        
        // Create key down event for 'v' key with Command modifier
        guard let vKeyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) else {
            Logger.shared.log("PasteManager: Failed to create 'v' key down event")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Cannot Create V Down Event) =====")
            return false
        }
        vKeyDown.flags = .maskCommand
        
        // Create key up event for 'v' key with Command modifier
        guard let vKeyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            Logger.shared.log("PasteManager: Failed to create 'v' key up event")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Cannot Create V Up Event) =====")
            return false
        }
        vKeyUp.flags = .maskCommand
        
        // Create key up event for Command key
        guard let cmdKeyUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false) else {
            Logger.shared.log("PasteManager: Failed to create Command key up event")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Cannot Create Command Up Event) =====")
            return false
        }
        
        // Verify the target application is still frontmost before posting events
        if let currentFrontApp = NSWorkspace.shared.frontmostApplication,
           currentFrontApp.bundleIdentifier != frontApp.bundleIdentifier {
            Logger.shared.log("PasteManager: Target application lost focus before posting events")
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Target Lost Focus) =====")
            return false
        }
        
        // Post the events with precise timing to simulate a real user pressing Cmd+V
        Logger.shared.log("PasteManager: Posting Command key down event...")
        cmdKeyDown.post(tap: .cghidEventTap)
        
        // Small delay between Command key down and 'v' key down
        usleep(20000) // 20ms
        
        // Verify the target application is still frontmost after Command key down
        if let currentFrontApp = NSWorkspace.shared.frontmostApplication,
           currentFrontApp.bundleIdentifier != frontApp.bundleIdentifier {
            Logger.shared.log("PasteManager: Target application lost focus after Command key down")
            
            // Release the Command key to avoid it being stuck
            cmdKeyUp.post(tap: .cghidEventTap)
            
            Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD FAILED (Target Lost Focus After Command Down) =====")
            return false
        }
        
        Logger.shared.log("PasteManager: Posting 'v' key down event...")
        vKeyDown.post(tap: .cghidEventTap)
        
        // Delay between key down and key up events
        usleep(50000) // 50ms
        
        Logger.shared.log("PasteManager: Posting 'v' key up event...")
        vKeyUp.post(tap: .cghidEventTap)
        
        // Small delay between 'v' key up and Command key up
        usleep(20000) // 20ms
        
        Logger.shared.log("PasteManager: Posting Command key up event...")
        cmdKeyUp.post(tap: .cghidEventTap)
        
        // Small delay after all events
        Thread.sleep(forTimeInterval: 0.05)
        
        Logger.shared.log("PasteManager: Universal direct paste method completed successfully")
        Logger.shared.log("===== UNIVERSAL DIRECT PASTE METHOD COMPLETED =====")
        return true
    }
    
    // Universal AppleScript paste method
    private func tryUniversalAppleScriptPaste() -> Bool {
        Logger.shared.log("PasteManager: Trying universal AppleScript paste method")
        
        // Get the frontmost app name for AppleScript
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            Logger.shared.log("PasteManager: Could not determine frontmost app")
            return false
        }
        
        // Different AppleScript approaches
        let scripts = [
            // Target specific app with activation
            """
            tell application "System Events"
                tell process "\(appName)"
                    keystroke "v" using command down
                end tell
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
            """,
            
            // New: Try with longer delays
            """
            tell application "System Events"
                delay 0.2
                keystroke "v" using command down
                delay 0.2
            end tell
            """,
            
            // New: Try with application activation first
            """
            tell application "\(appName)" to activate
            delay 0.2
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        ]
        
        // Try each script
        for (index, scriptText) in scripts.enumerated() {
            Logger.shared.log("PasteManager: Trying universal AppleScript method \(index + 1)")
            
            let script = NSAppleScript(source: scriptText)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            
            if let error = error {
                Logger.shared.log("PasteManager: Universal AppleScript method \(index + 1) failed: \(error)")
            } else {
                Logger.shared.log("PasteManager: Universal AppleScript method \(index + 1) succeeded")
                return true
            }
            
            // Small delay between attempts
            usleep(100000) // 100ms
        }
        
        Logger.shared.log("PasteManager: All universal AppleScript paste methods failed")
        return false
    }
    
    // Universal osascript paste method
    private func tryUniversalOsascriptPaste() -> Bool {
        Logger.shared.log("PasteManager: Trying universal osascript paste method")
        
        // Create a temporary AppleScript file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("universal_paste_script.scpt")
        
        // Get the frontmost app name for more targeted script
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        
        // Enhanced script with multiple approaches
        let scriptContent = """
        -- Try multiple paste approaches for maximum compatibility
        
        -- Approach 1: Basic Command+V
        try
            tell application "System Events"
                keystroke "v" using command down
            end tell
            return "Basic Command+V succeeded"
        on error errMsg
            log "Basic approach failed: " & errMsg
        end try
        
        -- Approach 2: Target specific app if available
        try
            tell application "System Events"
                tell process "\(appName)"
                    keystroke "v" using command down
                end tell
            end tell
            return "App-specific approach succeeded"
        on error errMsg
            log "App-specific approach failed: " & errMsg
        end try
        
        -- Approach 3: With delays
        try
            delay 0.2
            tell application "System Events"
                keystroke "v" using command down
            end tell
            delay 0.1
            return "Delayed approach succeeded"
        on error errMsg
            log "Delayed approach failed: " & errMsg
        end try
        
        -- Approach 4: Using key code
        try
            tell application "System Events"
                key code 9 using {command down}
            end tell
            return "Key code approach succeeded"
        on error errMsg
            log "Key code approach failed: " & errMsg
        end try
        
        -- If we get here, all approaches failed
        error "All paste approaches failed"
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
            
            // Clean up
            try FileManager.default.removeItem(at: scriptPath)
            
            if task.terminationStatus == 0 {
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                    Logger.shared.log("PasteManager: Universal osascript succeeded: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                } else {
                    Logger.shared.log("PasteManager: Universal osascript succeeded with no output")
                }
                return true
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                    Logger.shared.log("PasteManager: Universal osascript error: \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                Logger.shared.log("PasteManager: Universal osascript approach failed")
                return false
            }
        } catch {
            Logger.shared.log("PasteManager: Universal osascript error: \(error)")
            return false
        }
    }
    
    // New method: Try paste using NSPasteboard and NSResponder
    private func tryNSResponderPaste() -> Bool {
        Logger.shared.log("PasteManager: Trying NSResponder paste method")
        
        // This method attempts to use the NSResponder paste: method
        // It may work in some contexts where the app is properly respecting responder chain
        
        // Get the key window
        guard let keyWindow = NSApplication.shared.keyWindow else {
            Logger.shared.log("PasteManager: No key window available for NSResponder paste")
            return false
        }
        
        // Try to find a valid responder
        var responder: NSResponder? = keyWindow.firstResponder
        
        // If no first responder, try the window itself
        if responder == nil {
            responder = keyWindow
        }
        
        // Try to perform paste: action
        if let responder = responder, responder.responds(to: #selector(NSResponder.paste(_:))) {
            Logger.shared.log("PasteManager: Found responder that responds to paste:")
            
            // Perform the paste action on the main thread
            var success = false
            let semaphore = DispatchSemaphore(value: 0)
            
            DispatchQueue.main.async {
                responder.paste(nil)
                success = true
                semaphore.signal()
            }
            
            // Wait for the main thread action to complete (with timeout)
            _ = semaphore.wait(timeout: .now() + 1.0)
            
            Logger.shared.log("PasteManager: NSResponder paste \(success ? "succeeded" : "failed")")
            return success
        }
        
        Logger.shared.log("PasteManager: No suitable responder found for NSResponder paste")
        return false
    }
    
    // New method: Try paste using direct NSPasteboard manipulation
    private func tryDirectNSPasteboardPaste() -> Bool {
        Logger.shared.log("PasteManager: Trying direct NSPasteboard paste method")
        
        // This method attempts to use NSPasteboard directly to paste content
        // It may work in some contexts where the app is properly handling pasteboard changes
        
        // Get the current pasteboard content
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        
        // Try to "refresh" the pasteboard by writing the same content back to it
        // This can sometimes trigger apps to recognize new content
        
        // Check what types of data we have
        let types = pasteboard.types ?? []
        Logger.shared.log("PasteManager: Current pasteboard types: \(types)")
        
        var success = false
        
        // Try to preserve and rewrite each type of data
        for type in types {
            if let data = pasteboard.data(forType: type) {
                // Clear and set the data for this type
                pasteboard.clearContents()
                if pasteboard.setData(data, forType: type) {
                    Logger.shared.log("PasteManager: Successfully rewrote data for type: \(type)")
                    success = true
                }
            } else if let string = pasteboard.string(forType: type) {
                // Clear and set the string for this type
                pasteboard.clearContents()
                if pasteboard.setString(string, forType: type) {
                    Logger.shared.log("PasteManager: Successfully rewrote string for type: \(type)")
                    success = true
                }
            }
        }
        
        // Check if the pasteboard change count increased
        let newChangeCount = pasteboard.changeCount
        Logger.shared.log("PasteManager: Pasteboard change count: \(currentChangeCount) -> \(newChangeCount)")
        
        // If we successfully rewrote at least one type, or the change count increased, consider it a success
        return success || (newChangeCount > currentChangeCount)
    }
    
    // Method to handle special cases for specific applications
    private func tryAppSpecificPaste() -> Bool {
        Logger.shared.log("PasteManager: Trying app-specific paste method")
        
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontApp.bundleIdentifier else {
            Logger.shared.log("PasteManager: Could not determine frontmost app")
            return false
        }
        
        Logger.shared.log("PasteManager: Checking for special handling for app: \(bundleId)")
        
        // Handle specific applications that might need custom paste handling
        switch bundleId {
        case "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint":
            // Microsoft Office apps sometimes need special handling
            return tryMicrosoftOfficePaste(appName: frontApp.localizedName ?? "Microsoft Office")
            
        case "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac":
            // Web browsers might need special handling for certain input fields
            return tryBrowserPaste(appName: frontApp.localizedName ?? "Browser")
            
        case "com.apple.Terminal", "com.googlecode.iterm2":
            // Terminal apps often need special handling
            return tryTerminalPaste(appName: frontApp.localizedName ?? "Terminal")
            
        default:
            // No special handling for this app
            Logger.shared.log("PasteManager: No special handling for app: \(bundleId)")
            return false
        }
    }
    
    // Special paste method for Microsoft Office apps
    private func tryMicrosoftOfficePaste(appName: String) -> Bool {
        Logger.shared.log("PasteManager: Trying Microsoft Office paste for \(appName)")
        
        // Microsoft Office apps sometimes need a different approach
        let script = """
        tell application "\(appName)"
            activate
            delay 0.2
            tell application "System Events"
                keystroke "v" using command down
            end tell
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            Logger.shared.log("PasteManager: Microsoft Office paste failed: \(error)")
            return false
        } else {
            Logger.shared.log("PasteManager: Microsoft Office paste succeeded")
            return true
        }
    }
    
    // Special paste method for web browsers
    private func tryBrowserPaste(appName: String) -> Bool {
        Logger.shared.log("PasteManager: Trying browser paste for \(appName)")
        
        // For browsers, we'll try a sequence of methods
        
        // 1. First try standard Command+V
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }
        
        keyVDown.flags = .maskCommand
        keyVUp.flags = .maskCommand
        
        keyVDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        keyVUp.post(tap: .cghidEventTap)
        
        // 2. If that doesn't work, try with AppleScript
        Thread.sleep(forTimeInterval: 0.2)
        
        let script = """
        tell application "\(appName)"
            activate
            delay 0.2
            tell application "System Events"
                keystroke "v" using command down
            end tell
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            Logger.shared.log("PasteManager: Browser AppleScript paste failed: \(error)")
            return false
        } else {
            Logger.shared.log("PasteManager: Browser paste succeeded")
            return true
        }
    }
    
    // Special paste method for terminal apps
    private func tryTerminalPaste(appName: String) -> Bool {
        Logger.shared.log("PasteManager: Trying terminal paste for \(appName)")
        
        // Terminal apps often use Command+V or a custom shortcut
        
        // Try standard Command+V first
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }
        
        keyVDown.flags = .maskCommand
        keyVUp.flags = .maskCommand
        
        keyVDown.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        keyVUp.post(tap: .cghidEventTap)
        
        // For iTerm2, also try Command+Shift+V as an alternative
        if appName.contains("iTerm") {
            Thread.sleep(forTimeInterval: 0.2)
            
            guard let keyVDown2 = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyVUp2 = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
                return true // Return true since we already tried Command+V
            }
            
            keyVDown2.flags = [.maskCommand, .maskShift]
            keyVUp2.flags = [.maskCommand, .maskShift]
            
            keyVDown2.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.1)
            keyVUp2.post(tap: .cghidEventTap)
        }
        
        Logger.shared.log("PasteManager: Terminal paste completed")
        return true
    }
} 
