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
        Logger.shared.log("===== PASTE OPERATION START =====")
        Logger.shared.log("PasteManager: Starting paste operation" + (isRichText ? " (Rich Text)" : ""))
        
        // Set the rich text flag
        self.isRichTextPaste = isRichText
        Logger.shared.log("Set isRichTextPaste to: \(isRichText)")
        
        // Check clipboard content
        let pasteboard = NSPasteboard.general
        var hasRichTextData = false
        
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
                    Logger.shared.log("===== PASTE OPERATION FAILED (No Target App) =====")
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
        
        // Ensure the frontmost application is not our app
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            Logger.shared.log("===== DIRECT PASTE METHOD FAILED =====")
            return false
        }
        
        // Make sure the target application has focus
        // Small delay to ensure the app is ready to receive keyboard events
        Thread.sleep(forTimeInterval: 0.1)
        
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
    
    // Special method for pasting rich text
    private func tryRichTextPasteMethod() -> Bool {
        Logger.shared.log("===== RICH TEXT PASTE METHOD START =====")
        Logger.shared.log("PasteManager: Trying rich text paste method")
        
        // Check clipboard content again right before pasting
        let pasteboard = NSPasteboard.general
        var rtfData: Data? = nil
        var attributedString: NSAttributedString? = nil
        
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
        
        // Ensure the frontmost application is not our app
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            Logger.shared.log("PasteManager: Cannot paste into Clipboard Manager itself")
            Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
            return false
        }
        
        // Get the frontmost app name for AppleScript
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let appName = frontApp.localizedName else {
            Logger.shared.log("PasteManager: Could not determine frontmost app")
            Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
            return false
        }
        
        Logger.shared.log("PasteManager: Frontmost app for rich text paste: \(appName)")
        
        // Try multiple AppleScript approaches for rich text pasting
        let scriptOptions = [
            // Option 1: Use Edit menu's Paste command
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
            
            // Option 2: Use Command+V but with longer delays
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
            
            // Option 3: Try to paste with formatting explicitly (works in some apps)
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
        
        Logger.shared.log("===== RICH TEXT PASTE METHOD FAILED =====")
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
} 
