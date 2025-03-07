import Foundation

class Logger {
    static let shared = Logger()
    
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let logFile: URL
    private let logFileURL: String
    
    private init() {
        logDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFile = logDirectory.appendingPathComponent("ClipboardManager.log")
        logFileURL = logFile.path
        
        // Create or clear the log file
        fileManager.createFile(atPath: logFileURL, contents: "=== Clipboard Manager Log ===\n".data(using: .utf8), attributes: nil)
    }
    
    func log(_ items: Any...) {
        // Standard print to console
        print(items)
        
        // Also write to log file
        if let fileHandle = FileHandle(forWritingAtPath: logFileURL) {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let text = "[\(timestamp)] " + items.map { "\($0)" }.joined(separator: " ") + "\n"
            fileHandle.seekToEndOfFile()
            fileHandle.write(text.data(using: .utf8)!)
            fileHandle.closeFile()
        }
    }
    
    func getLogFilePath() -> String {
        return logFileURL
    }
} 