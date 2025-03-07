import Cocoa
import Foundation

// Check for debug flag
let isDebugMode = CommandLine.arguments.contains("--debug")

// Log startup information
Logger.shared.log("Starting Clipboard Manager")
Logger.shared.log("Log file location: \(Logger.shared.getLogFilePath())")

if isDebugMode {
    Logger.shared.log("Running in DEBUG mode")
    Logger.shared.log("Command line arguments: \(CommandLine.arguments)")
}

// Create and run the application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Enable debug logging for accessibility if in debug mode
if isDebugMode {
    UserDefaults.standard.set(true, forKey: "AXSEnableDebugLogging")
    UserDefaults.standard.set(true, forKey: "AXSEnableLogging")
    Logger.shared.log("Enabled accessibility debug logging")
}

// Run the app
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv) 


