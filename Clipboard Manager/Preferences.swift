import Cocoa

class Preferences: Codable {
    // Appearance
    var useSystemAppearance: Bool = true
    var darkMode: Bool = false
    var customizeAppearance: Bool = false // Controls whether to show customization options
    var cardBackgroundColor: String = "#FFFFFF" // Hex color
    var cardBackgroundAlpha: Float = 1.0 // 0.0 to 1.0
    var textColor: String = "#000000" // Hex color
    var fullClipboardTransparency: Bool = false // Controls full clipboard window transparency
    var windowBackgroundColor: String = "#F0F0F0" // Hex color for clipboard window background

    // Size
    var cardHeight: Int = 100
    var cardSpacing: Int = 10
    var windowWidth: Int = 500
    var windowHeight: Int = 600
    var maxHistoryItems: Int = 20

    // Behavior
    var showNotifications: Bool = true
    var autoPaste: Bool = false // Whether to automatically paste after copying
    var launchAtStartup: Bool = true // Whether to launch the app at system startup

    // Hotkey
    var hotkeyKeyIndex: Int = 21 // Default to "V" (index 21 in the popup)
    var hotkeyCommand: Bool = true // Default to Command key
    var hotkeyShift: Bool = true // Default to Shift key
    var hotkeyOption: Bool = false // Default to no Option key
    var hotkeyControl: Bool = false // Default to no Control key

    // Singleton instance
    static let shared = Preferences()

    // File path for saving preferences
    private let preferencesFilePath: URL

    private init() {
        // Get the application support directory
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipboardDir = appSupportDir.appendingPathComponent("ClipboardManager", isDirectory: true)

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: clipboardDir, withIntermediateDirectories: true)

        // Set preferences file path
        preferencesFilePath = clipboardDir.appendingPathComponent("preferences.json")

        // Load preferences from file
        loadPreferences()
    }

    // MARK: - Color Conversion

    func cardBackgroundNSColor() -> NSColor {
        let color = NSColor.fromHex(cardBackgroundColor) ?? NSColor.controlBackgroundColor
        return color.withAlphaComponent(CGFloat(cardBackgroundAlpha))
    }

    func textNSColor() -> NSColor {
        return NSColor.fromHex(textColor) ?? NSColor.labelColor
    }

    func windowBackgroundNSColor() -> NSColor {
        if useSystemAppearance {
            // Use system appearance
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if isDark {
                return NSColor.fromHex("#222222") ?? NSColor.darkGray
            } else {
                return NSColor.fromHex(windowBackgroundColor) ?? NSColor.windowBackgroundColor
            }
        } else if darkMode {
            // Use dark mode colors
            return NSColor.fromHex("#222222") ?? NSColor.darkGray
        } else {
            // Use light mode colors
            return NSColor.fromHex(windowBackgroundColor) ?? NSColor.windowBackgroundColor
        }
    }

    func adaptToSystemAppearance() {
        if useSystemAppearance {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

            if isDark {
                // Dark mode
                cardBackgroundColor = "#333333"
                textColor = "#FFFFFF"
                windowBackgroundColor = "#222222"
            } else {
                // Light mode
                cardBackgroundColor = "#FFFFFF"
                textColor = "#000000"
                windowBackgroundColor = "#F0F0F0"
            }
        }
    }

    // MARK: - Save & Load

    func savePreferences() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            try data.write(to: preferencesFilePath)
            print("Preferences saved successfully")
        } catch {
            print("Error saving preferences: \(error)")
        }
    }

    private func loadPreferences() {
        do {
            if FileManager.default.fileExists(atPath: preferencesFilePath.path) {
                let data = try Data(contentsOf: preferencesFilePath)
                let decoder = JSONDecoder()
                let loadedPreferences = try decoder.decode(Preferences.self, from: data)

                // Copy all properties from loaded preferences
                self.useSystemAppearance = loadedPreferences.useSystemAppearance
                self.darkMode = loadedPreferences.darkMode
                self.customizeAppearance = loadedPreferences.customizeAppearance
                self.cardBackgroundColor = loadedPreferences.cardBackgroundColor
                self.cardBackgroundAlpha = loadedPreferences.cardBackgroundAlpha
                self.textColor = loadedPreferences.textColor
                self.fullClipboardTransparency = loadedPreferences.fullClipboardTransparency

                // Handle the new windowBackgroundColor property (might not exist in older preference files)
                if let windowBgColor = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "windowBackgroundColor" })?.value as? String {
                    self.windowBackgroundColor = windowBgColor
                }

                self.cardHeight = loadedPreferences.cardHeight
                self.cardSpacing = loadedPreferences.cardSpacing
                self.windowWidth = loadedPreferences.windowWidth
                self.windowHeight = loadedPreferences.windowHeight
                self.maxHistoryItems = loadedPreferences.maxHistoryItems
                self.showNotifications = loadedPreferences.showNotifications

                // Handle the new autoPaste property (might not exist in older preference files)
                if let autoPasteValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "autoPaste" })?.value as? Bool {
                    self.autoPaste = autoPasteValue
                }

                // Handle the new launchAtStartup property (might not exist in older preference files)
                if let launchAtStartupValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "launchAtStartup" })?.value as? Bool {
                    self.launchAtStartup = launchAtStartupValue
                }

                // Handle the new hotkey properties (might not exist in older preference files)
                if let hotkeyKeyIndexValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "hotkeyKeyIndex" })?.value as? Int {
                    self.hotkeyKeyIndex = hotkeyKeyIndexValue
                }

                if let hotkeyCommandValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "hotkeyCommand" })?.value as? Bool {
                    self.hotkeyCommand = hotkeyCommandValue
                }

                if let hotkeyShiftValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "hotkeyShift" })?.value as? Bool {
                    self.hotkeyShift = hotkeyShiftValue
                }

                if let hotkeyOptionValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "hotkeyOption" })?.value as? Bool {
                    self.hotkeyOption = hotkeyOptionValue
                }

                if let hotkeyControlValue = Mirror(reflecting: loadedPreferences).children.first(where: { $0.label == "hotkeyControl" })?.value as? Bool {
                    self.hotkeyControl = hotkeyControlValue
                }

                print("Preferences loaded successfully")
            } else {
                // First run, save default preferences
                savePreferences()
            }
        } catch {
            print("Error loading preferences: \(error)")
            // Save default preferences
            savePreferences()
        }

        // Adapt to system appearance if needed
        adaptToSystemAppearance()
    }
}

// MARK: - NSColor Extension for Hex Colors

extension NSColor {
    static func fromHex(_ hex: String) -> NSColor? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    func toHex() -> String {
        guard let rgbColor = usingColorSpace(.sRGB) else {
            return "#000000"
        }

        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))

        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // Add a method to blend colors for selection highlighting
    func blended(withFraction fraction: CGFloat, of color: NSColor) -> NSColor? {
        guard let rgb1 = self.usingColorSpace(.sRGB),
              let rgb2 = color.usingColorSpace(.sRGB) else {
            return nil
        }

        let r = rgb1.redComponent * (1 - fraction) + rgb2.redComponent * fraction
        let g = rgb1.greenComponent * (1 - fraction) + rgb2.greenComponent * fraction
        let b = rgb1.blueComponent * (1 - fraction) + rgb2.blueComponent * fraction
        let a = rgb1.alphaComponent * (1 - fraction) + rgb2.alphaComponent * fraction

        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
}