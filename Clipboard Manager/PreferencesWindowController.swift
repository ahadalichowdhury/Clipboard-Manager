import Cocoa

// Custom color picker similar to Terminal style
class TerminalStyleColorPicker: NSView {
    private var colorButtons: [NSButton] = []
    private var selectedColorButton: NSButton?
    private var currentColor: NSColor = .white
    private var colorChangeAction: ((NSColor) -> Void)?
    private var hiddenColorWell: NSColorWell?
    
    // Terminal-style preset colors (first row)
    private let presetColors: [NSColor] = [
        .white,
        .black,
        NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1.0), // Light Gray
        NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),    // Gray
        NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0),    // Red
        NSColor(red: 0.2, green: 0.7, blue: 0.2, alpha: 1.0),    // Green
        NSColor(red: 0.95, green: 0.8, blue: 0.2, alpha: 1.0),   // Yellow
        NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1.0),    // Blue
        NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1.0),    // Magenta
        NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1.0),    // Cyan
        NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0),    // Brown
        NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)     // Dark Green
    ]
    
    // Additional colors (second row)
    private let additionalColors: [NSColor] = [
        NSColor(red: 1.0, green: 0.8, blue: 0.8, alpha: 1.0),    // Light Pink
        NSColor(red: 0.8, green: 1.0, blue: 0.8, alpha: 1.0),    // Light Green
        NSColor(red: 0.8, green: 0.8, blue: 1.0, alpha: 1.0),    // Light Blue
        NSColor(red: 1.0, green: 1.0, blue: 0.8, alpha: 1.0),    // Light Yellow
        NSColor(red: 0.8, green: 1.0, blue: 1.0, alpha: 1.0),    // Light Cyan
        NSColor(red: 1.0, green: 0.8, blue: 1.0, alpha: 1.0),    // Light Magenta
        NSColor(red: 0.6, green: 0.0, blue: 0.0, alpha: 1.0),    // Dark Red
        NSColor(red: 0.0, green: 0.6, blue: 0.0, alpha: 1.0),    // Dark Green
        NSColor(red: 0.0, green: 0.0, blue: 0.6, alpha: 1.0),    // Dark Blue
        NSColor(red: 0.6, green: 0.6, blue: 0.0, alpha: 1.0),    // Dark Yellow
        NSColor(red: 0.0, green: 0.6, blue: 0.6, alpha: 1.0),    // Dark Cyan
        NSColor(red: 0.6, green: 0.0, blue: 0.6, alpha: 1.0)     // Dark Magenta
    ]
    
    init(frame: NSRect, initialColor: NSColor, action: @escaping (NSColor) -> Void) {
        super.init(frame: frame)
        self.currentColor = initialColor
        self.colorChangeAction = action
        setupColorButtons()
        
        // Add a hidden color well to handle the system color panel properly
        hiddenColorWell = NSColorWell(frame: NSRect(x: -100, y: -100, width: 20, height: 20))
        hiddenColorWell?.target = self
        hiddenColorWell?.action = #selector(colorWellChanged)
        if let colorWell = hiddenColorWell {
            addSubview(colorWell)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupColorButtons() {
        let buttonSize: CGFloat = 20
        let spacing: CGFloat = 5
        let buttonsPerRow = 6
        
        // First row of colors
        for (index, color) in presetColors.enumerated() {
            let row = index / buttonsPerRow
            let col = index % buttonsPerRow
            
            let x = CGFloat(col) * (buttonSize + spacing)
            let y = frame.height - CGFloat(row + 1) * (buttonSize + spacing)
            
            let button = NSButton(frame: NSRect(x: x, y: y, width: buttonSize, height: buttonSize))
            button.bezelStyle = .regularSquare
            button.isBordered = true
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 3
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.gray.cgColor
            button.tag = index
            button.target = self
            button.action = #selector(colorButtonClicked)
            
            // Highlight the button if it matches the current color
            if color.isClose(to: currentColor) {
                selectedColorButton = button
                button.layer?.borderWidth = 2
                button.layer?.borderColor = NSColor.systemBlue.cgColor
            }
            
            addSubview(button)
            colorButtons.append(button)
        }
        
        // Second row of colors (additional colors)
        for (index, color) in additionalColors.enumerated() {
            let row = (index / buttonsPerRow) + 2 // Start after the first row
            let col = index % buttonsPerRow
            
            let x = CGFloat(col) * (buttonSize + spacing)
            let y = frame.height - CGFloat(row + 1) * (buttonSize + spacing)
            
            let button = NSButton(frame: NSRect(x: x, y: y, width: buttonSize, height: buttonSize))
            button.bezelStyle = .regularSquare
            button.isBordered = true
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 3
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.gray.cgColor
            button.tag = index + presetColors.count // Offset tag by the number of preset colors
            button.target = self
            button.action = #selector(additionalColorButtonClicked)
            
            // Highlight the button if it matches the current color
            if color.isClose(to: currentColor) {
                selectedColorButton = button
                button.layer?.borderWidth = 2
                button.layer?.borderColor = NSColor.systemBlue.cgColor
            }
            
            addSubview(button)
            colorButtons.append(button)
        }
        
        // Add "Custom..." button at the bottom
        let customButtonY = frame.height - CGFloat((presetColors.count / buttonsPerRow) + 3) * (buttonSize + spacing) - 10
        let customButton = NSButton(frame: NSRect(x: 0, y: customButtonY, width: 80, height: 20))
        customButton.title = "Custom..."
        customButton.bezelStyle = .rounded
        customButton.font = NSFont.systemFont(ofSize: 10)
        customButton.target = self
        customButton.action = #selector(customColorButtonClicked)
        
        addSubview(customButton)
    }
    
    @objc private func colorButtonClicked(_ sender: NSButton) {
        // Update selected button
        selectedColorButton?.layer?.borderWidth = 1
        selectedColorButton?.layer?.borderColor = NSColor.gray.cgColor
        
        sender.layer?.borderWidth = 2
        sender.layer?.borderColor = NSColor.systemBlue.cgColor
        selectedColorButton = sender
        
        // Get the selected color
        let selectedColor = presetColors[sender.tag]
        currentColor = selectedColor
        
        // Call the action
        colorChangeAction?(selectedColor)
    }
    
    @objc private func additionalColorButtonClicked(_ sender: NSButton) {
        // Update selected button
        selectedColorButton?.layer?.borderWidth = 1
        selectedColorButton?.layer?.borderColor = NSColor.gray.cgColor
        
        sender.layer?.borderWidth = 2
        sender.layer?.borderColor = NSColor.systemBlue.cgColor
        selectedColorButton = sender
        
        // Get the selected color (accounting for the offset in the tag)
        let selectedColor = additionalColors[sender.tag - presetColors.count]
        currentColor = selectedColor
        
        // Call the action
        colorChangeAction?(selectedColor)
    }
    
    @objc private func customColorButtonClicked(_ sender: NSButton) {
        // Use the hidden color well to open the system color panel
        hiddenColorWell?.color = currentColor
        hiddenColorWell?.performClick(nil)
    }
    
    @objc private func colorWellChanged(_ sender: NSColorWell) {
        // Update our color
        currentColor = sender.color
        
        // Deselect all preset buttons
        selectedColorButton?.layer?.borderWidth = 1
        selectedColorButton?.layer?.borderColor = NSColor.gray.cgColor
        selectedColorButton = nil
        
        // Call the action
        colorChangeAction?(currentColor)
    }
    
    var color: NSColor {
        get { return currentColor }
        set {
            currentColor = newValue
            
            // Update selected button
            selectedColorButton?.layer?.borderWidth = 1
            selectedColorButton?.layer?.borderColor = NSColor.gray.cgColor
            selectedColorButton = nil
            
            // Check if the new color matches any preset
            for (index, presetColor) in presetColors.enumerated() {
                if presetColor.isClose(to: newValue) {
                    selectedColorButton = colorButtons[index]
                    selectedColorButton?.layer?.borderWidth = 2
                    selectedColorButton?.layer?.borderColor = NSColor.systemBlue.cgColor
                    break
                }
            }
            
            // If no match in presets, check additional colors
            if selectedColorButton == nil {
                for (index, additionalColor) in additionalColors.enumerated() {
                    if additionalColor.isClose(to: newValue) {
                        let buttonIndex = index + presetColors.count
                        if buttonIndex < colorButtons.count {
                            selectedColorButton = colorButtons[buttonIndex]
                            selectedColorButton?.layer?.borderWidth = 2
                            selectedColorButton?.layer?.borderColor = NSColor.systemBlue.cgColor
                            break
                        }
                    }
                }
            }
        }
    }
}

// Simple custom color picker window
class CustomColorPickerWindow: NSWindowController {
    private var redSlider: NSSlider!
    private var greenSlider: NSSlider!
    private var blueSlider: NSSlider!
    private var redValueLabel: NSTextField!
    private var greenValueLabel: NSTextField!
    private var blueValueLabel: NSTextField!
    private var colorPreview: NSView!
    private var currentColor: NSColor
    private var onColorSelected: (NSColor) -> Void
    
    init(initialColor: NSColor, onColorSelected: @escaping (NSColor) -> Void) {
        self.currentColor = initialColor
        self.onColorSelected = onColorSelected
        
        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Choose Custom Color"
        window.isReleasedWhenClosed = false
        
        // Ensure the window is movable
        window.isMovableByWindowBackground = false
        
        // Initialize with window first
        super.init(window: window)
        
        // Set delegate to handle window closing (moved after super.init)
        window.delegate = self
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let window = self.window, 
              let contentView = window.contentView else { return }
        
        // Extract RGB components from the current color
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        if let rgbColor = currentColor.usingColorSpace(.sRGB) {
            rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        }
        
        // Color preview
        colorPreview = NSView(frame: NSRect(x: 20, y: 140, width: 260, height: 40))
        colorPreview.wantsLayer = true
        colorPreview.layer?.backgroundColor = currentColor.cgColor
        colorPreview.layer?.cornerRadius = 5
        colorPreview.layer?.borderWidth = 1
        colorPreview.layer?.borderColor = NSColor.gray.cgColor
        contentView.addSubview(colorPreview)
        
        // Red slider
        let redLabel = NSTextField(labelWithString: "Red:")
        redLabel.frame = NSRect(x: 20, y: 110, width: 50, height: 20)
        contentView.addSubview(redLabel)
        
        redValueLabel = NSTextField(frame: NSRect(x: 240, y: 110, width: 40, height: 20))
        redValueLabel.isEditable = false
        redValueLabel.isBordered = false
        redValueLabel.drawsBackground = false
        redValueLabel.stringValue = String(format: "%.2f", red)
        contentView.addSubview(redValueLabel)
        
        redSlider = NSSlider(frame: NSRect(x: 70, y: 110, width: 160, height: 20))
        redSlider.minValue = 0.0
        redSlider.maxValue = 1.0
        redSlider.floatValue = Float(red)
        redSlider.target = self
        redSlider.action = #selector(sliderChanged)
        redSlider.tag = 0 // Red
        contentView.addSubview(redSlider)
        
        // Green slider
        let greenLabel = NSTextField(labelWithString: "Green:")
        greenLabel.frame = NSRect(x: 20, y: 80, width: 50, height: 20)
        contentView.addSubview(greenLabel)
        
        greenValueLabel = NSTextField(frame: NSRect(x: 240, y: 80, width: 40, height: 20))
        greenValueLabel.isEditable = false
        greenValueLabel.isBordered = false
        greenValueLabel.drawsBackground = false
        greenValueLabel.stringValue = String(format: "%.2f", green)
        contentView.addSubview(greenValueLabel)
        
        greenSlider = NSSlider(frame: NSRect(x: 70, y: 80, width: 160, height: 20))
        greenSlider.minValue = 0.0
        greenSlider.maxValue = 1.0
        greenSlider.floatValue = Float(green)
        greenSlider.target = self
        greenSlider.action = #selector(sliderChanged)
        greenSlider.tag = 1 // Green
        contentView.addSubview(greenSlider)
        
        // Blue slider
        let blueLabel = NSTextField(labelWithString: "Blue:")
        blueLabel.frame = NSRect(x: 20, y: 50, width: 50, height: 20)
        contentView.addSubview(blueLabel)
        
        blueValueLabel = NSTextField(frame: NSRect(x: 240, y: 50, width: 40, height: 20))
        blueValueLabel.isEditable = false
        blueValueLabel.isBordered = false
        blueValueLabel.drawsBackground = false
        blueValueLabel.stringValue = String(format: "%.2f", blue)
        contentView.addSubview(blueValueLabel)
        
        blueSlider = NSSlider(frame: NSRect(x: 70, y: 50, width: 160, height: 20))
        blueSlider.minValue = 0.0
        blueSlider.maxValue = 1.0
        blueSlider.floatValue = Float(blue)
        blueSlider.target = self
        blueSlider.action = #selector(sliderChanged)
        blueSlider.tag = 2 // Blue
        contentView.addSubview(blueSlider)
        
        // OK button
        let okButton = NSButton(frame: NSRect(x: 200, y: 10, width: 80, height: 30))
        okButton.title = "OK"
        okButton.bezelStyle = .rounded
        okButton.target = self
        okButton.action = #selector(okButtonClicked)
        contentView.addSubview(okButton)
        
        // Cancel button
        let cancelButton = NSButton(frame: NSRect(x: 110, y: 10, width: 80, height: 30))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)
        contentView.addSubview(cancelButton)
    }
    
    @objc private func sliderChanged(_ sender: NSSlider) {
        // Update the color based on slider values
        let red = CGFloat(redSlider.floatValue)
        let green = CGFloat(greenSlider.floatValue)
        let blue = CGFloat(blueSlider.floatValue)
        
        // Update value labels
        if sender.tag == 0 {
            redValueLabel.stringValue = String(format: "%.2f", red)
        } else if sender.tag == 1 {
            greenValueLabel.stringValue = String(format: "%.2f", green)
        } else if sender.tag == 2 {
            blueValueLabel.stringValue = String(format: "%.2f", blue)
        }
        
        // Update the color preview
        currentColor = NSColor(red: red, green: green, blue: blue, alpha: 1.0)
        colorPreview.layer?.backgroundColor = currentColor.cgColor
    }
    
    @objc private func okButtonClicked() {
        // Call the completion handler with the selected color
        onColorSelected(currentColor)
        
        // Close the window
        closeWindow()
    }
    
    @objc private func cancelButtonClicked() {
        // Just close the window without calling the completion handler
        closeWindow()
    }
    
    private func closeWindow() {
        // If shown as a sheet, end the sheet
        if let window = self.window, let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            // If shown as a modal, stop the modal session
            NSApp.stopModal()
        }
        
        // Close the window
        window?.close()
    }
}

// MARK: - NSWindowDelegate for CustomColorPickerWindow
extension CustomColorPickerWindow: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Clean up any resources if needed
        print("CustomColorPickerWindow window will close")
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        print("CustomColorPickerWindow window did become key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        print("CustomColorPickerWindow window did resign key")
    }
}

// Extension to help compare colors
extension NSColor {
    func isClose(to color: NSColor, tolerance: CGFloat = 0.1) -> Bool {
        guard let rgb1 = self.usingColorSpace(.sRGB),
              let rgb2 = color.usingColorSpace(.sRGB) else {
            return false
        }
        
        let redDiff = abs(rgb1.redComponent - rgb2.redComponent)
        let greenDiff = abs(rgb1.greenComponent - rgb2.greenComponent)
        let blueDiff = abs(rgb1.blueComponent - rgb2.blueComponent)
        
        return redDiff <= tolerance && greenDiff <= tolerance && blueDiff <= tolerance
    }
}

class PreferencesWindowController: NSWindowController {
    private var appearanceTab: NSView!
    private var sizeTab: NSView!
    private var behaviorTab: NSView!
    private var tabView: NSTabView!
    
    private var useSystemAppearanceCheckbox: NSButton!
    private var darkModeCheckbox: NSButton!
    private var customizeAppearanceCheckbox: NSButton!
    private var backgroundColorPicker: TerminalStyleColorPicker!
    private var backgroundAlphaSlider: NSSlider!
    private var backgroundAlphaValueLabel: NSTextField?
    private var textColorPicker: TerminalStyleColorPicker!
    private var fullClipboardTransparencyCheckbox: NSButton!
    private var windowBackgroundColorPicker: TerminalStyleColorPicker!
    
    private var cardHeightSlider: NSSlider!
    private var cardSpacingSlider: NSSlider!
    private var windowWidthSlider: NSSlider!
    private var windowHeightSlider: NSSlider!
    private var maxHistoryItemsSlider: NSSlider!
    
    private var showNotificationsCheckbox: NSButton!
    private var autoPasteCheckbox: NSButton!
    private var launchAtStartupCheckbox: NSButton!
    
    // Hotkey UI elements
    private var hotkeyKeyPopup: NSPopUpButton!
    private var hotkeyCommandCheckbox: NSButton!
    private var hotkeyShiftCheckbox: NSButton!
    private var hotkeyOptionCheckbox: NSButton!
    private var hotkeyControlCheckbox: NSButton!
    
    // Current recording state
    private var isRecordingHotkey: Bool = false
    private var recordHotkeyButton: NSButton!
    private var hotkeyStatusLabel: NSTextField!
    
    init() {
        // Debug print to track initialization
        print("PreferencesWindowController init started")
        
        // Create window with increased width
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Position the window in the center of the screen
        if let screen = NSScreen.main {
            let x = (screen.frame.width - 700) / 2
            let y = (screen.frame.height - 500) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }
        
        window.title = "Clipboard Manager Preferences"
        window.isReleasedWhenClosed = false
        
        // Make the window appear on top of other windows but not modal
        window.level = .floating
        
        // Ensure the window is visible when created
        window.isOpaque = true
        window.hasShadow = true
        window.backgroundColor = NSColor.windowBackgroundColor
        
        // Ensure the window is movable
        window.isMovableByWindowBackground = false
        
        // Initialize with window first
        super.init(window: window)
        
        // Set delegate to handle window closing (moved after super.init)
        window.delegate = self
        
        // Set up UI after initialization
        setupUI()
        loadPreferences()
        
        // Debug print to verify window creation
        print("PreferencesWindowController initialized with window: \(window)")
    }
    
    override func showWindow(_ sender: Any?) {
        print("PreferencesWindowController.showWindow called")
        
        // Make sure the window exists
        guard let window = self.window else {
            print("ERROR: PreferencesWindowController has no window")
            return
        }
        
        // Force the app to be active first
        NSApp.activate(ignoringOtherApps: true)
        // Ensure we maintain accessory policy
        NSApp.setActivationPolicy(.accessory)
        
        // Make the window key and bring it to front
        super.showWindow(sender)
        window.makeKeyAndOrderFront(sender)
        
        // Additional steps to ensure visibility
        window.orderFrontRegardless()
        
        // Ensure window is visible by checking after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !window.isVisible {
                print("Window still not visible after showWindow, forcing again")
                window.orderFrontRegardless()
                NSApp.activate(ignoringOtherApps: true)
                // Ensure we maintain accessory policy
                NSApp.setActivationPolicy(.accessory)
            }
        }
        
        print("Window should now be visible: \(window), isVisible: \(window.isVisible), isKeyWindow: \(window.isKeyWindow)")
    }
    
    // Helper method to scroll all tab views to the top
    private func scrollTabsToTop() {
        // Ensure we have tab view items
        guard tabView.tabViewItems.count > 0 else { return }
        
        // Scroll each tab's scroll view to the top
        for i in 0..<tabView.tabViewItems.count {
            if let scrollView = tabView.tabViewItems[i].view as? NSScrollView {
                // Scroll to the top (y = 0 is the bottom, so we need to scroll to the max height)
                if let documentView = scrollView.documentView {
                    let clipViewBounds = scrollView.contentView.bounds
                    let documentFrame = documentView.frame
                    
                    // Calculate the point to scroll to (top of the document)
                    let topPoint = NSPoint(
                        x: clipViewBounds.origin.x,
                        y: documentFrame.size.height - clipViewBounds.size.height
                    )
                    
                    // Scroll to the top
                    documentView.scroll(topPoint)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                }
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
    }
    
    private func setupUI() {
        guard let window = self.window else { return }
        
        // Create main content view
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        
        // Create tab view with more width to prevent tab overlap
        tabView = NSTabView(frame: NSRect(x: 20, y: 60, width: contentView.bounds.width - 40, height: contentView.bounds.height - 100))
        tabView.autoresizingMask = [.width, .height]
        
        // Add the tab view to the content view first
        contentView.addSubview(tabView)
        
        // Create tabs in the correct order
        setupAppearanceTab()
        setupSizeTab()
        setupBehaviorTab()
        
        // Manually adjust tab positions to prevent overlap
        if tabView.tabViewItems.count >= 3 {
            // This will be executed after the window is shown
            DispatchQueue.main.async {
                // Get the tab view's control
                if let control = self.tabView.subviews.first(where: { $0 is NSSegmentedControl }) as? NSSegmentedControl {
                    // Increase the width of each segment to prevent overlap
                    control.segmentDistribution = .fillEqually
                    control.setWidth(120, forSegment: 0) // Appearance
                    control.setWidth(120, forSegment: 1) // Size
                    control.setWidth(120, forSegment: 2) // Behavior
                }
            }
        }
        
        // Add save and cancel buttons
        let saveButton = NSButton(frame: NSRect(x: contentView.bounds.width - 100, y: 20, width: 80, height: 24))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(savePreferences)
        saveButton.autoresizingMask = [.minXMargin, .maxYMargin]
        
        let cancelButton = NSButton(frame: NSRect(x: contentView.bounds.width - 190, y: 20, width: 80, height: 24))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelPreferences)
        cancelButton.autoresizingMask = [.minXMargin, .maxYMargin]
        
        contentView.addSubview(saveButton)
        contentView.addSubview(cancelButton)
    }
    
    private func setupAppearanceTab() {
        // Create a scroll view to contain all appearance settings
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        
        // Create a content view that's taller to accommodate all settings with more space
        appearanceTab = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width - 20, height: 950)) // Increased height even more
        
        // Set the document view of the scroll view
        scrollView.documentView = appearanceTab
        
        // Section title for Appearance settings
        let appearanceSectionLabel = NSTextField(labelWithString: "Clipboard Window Appearance")
        appearanceSectionLabel.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 40, width: 300, height: 24)
        appearanceSectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        appearanceSectionLabel.textColor = NSColor.labelColor
        appearanceTab.addSubview(appearanceSectionLabel)
        
        // Add explanation that these settings only apply to the clipboard window
        let appearanceExplanationLabel = NSTextField(labelWithString: "These settings only affect the clipboard history window. Other windows follow system appearance.")
        appearanceExplanationLabel.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 65, width: appearanceTab.bounds.width - 40, height: 20)
        appearanceExplanationLabel.font = NSFont.systemFont(ofSize: 11)
        appearanceExplanationLabel.textColor = NSColor.secondaryLabelColor
        appearanceExplanationLabel.isEditable = false
        appearanceExplanationLabel.isBordered = false
        appearanceExplanationLabel.drawsBackground = false
        appearanceTab.addSubview(appearanceExplanationLabel)
        
        // Move the three appearance options to the top
        // Use system appearance checkbox
        useSystemAppearanceCheckbox = NSButton(checkboxWithTitle: "Use system appearance", target: self, action: #selector(toggleAppearanceOption))
        useSystemAppearanceCheckbox.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 95, width: 200, height: 20)
        appearanceTab.addSubview(useSystemAppearanceCheckbox)
        
        // Dark mode checkbox
        darkModeCheckbox = NSButton(checkboxWithTitle: "Dark mode", target: self, action: #selector(toggleAppearanceOption))
        darkModeCheckbox.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 125, width: 200, height: 20)
        appearanceTab.addSubview(darkModeCheckbox)
        
        // Customize appearance checkbox
        customizeAppearanceCheckbox = NSButton(checkboxWithTitle: "Customize appearance", target: self, action: #selector(toggleAppearanceOption))
        customizeAppearanceCheckbox.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 155, width: 200, height: 20)
        appearanceTab.addSubview(customizeAppearanceCheckbox)
        
        // Card item color section - INCREASED SPACING
        let cardItemColorLabel = NSTextField(labelWithString: "Card item color:")
        cardItemColorLabel.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 215, width: 150, height: 20) // More space
        appearanceTab.addSubview(cardItemColorLabel)
        
        // Replace NSColorWell with TerminalStyleColorPicker - INCREASED SPACING
        backgroundColorPicker = TerminalStyleColorPicker(
            frame: NSRect(x: 180, y: appearanceTab.bounds.height - 310, width: 150, height: 90), // More space
            initialColor: NSColor.white,
            action: { [weak self] color in
                self?.applyChanges()
            }
        )
        appearanceTab.addSubview(backgroundColorPicker)
        
        // Add more space between sections - Card item transparency - INCREASED SPACING
        let backgroundAlphaLabel = NSTextField(labelWithString: "Card item transparency:")
        backgroundAlphaLabel.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 380, width: 150, height: 20) // More space
        appearanceTab.addSubview(backgroundAlphaLabel)
        
        // Add explanation label with more space - MOVED DOWN
        let explanationLabel = NSTextField(labelWithString: "Controls the transparency of clipboard card item backgrounds (text remains fully visible)")
        explanationLabel.frame = NSRect(x: 180, y: appearanceTab.bounds.height - 400, width: 350, height: 16) // More space
        explanationLabel.font = NSFont.systemFont(ofSize: 10)
        explanationLabel.textColor = NSColor.secondaryLabelColor
        explanationLabel.isEditable = false
        explanationLabel.isBordered = false
        explanationLabel.drawsBackground = false
        appearanceTab.addSubview(explanationLabel)
        
        // Create transparency value label - MOVED DOWN
        let transparencyValueLabel = NSTextField(frame: NSRect(x: 390, y: appearanceTab.bounds.height - 380, width: 50, height: 20))
        transparencyValueLabel.isEditable = false
        transparencyValueLabel.isBordered = false
        transparencyValueLabel.drawsBackground = false
        transparencyValueLabel.stringValue = "0.00"
        appearanceTab.addSubview(transparencyValueLabel)
        
        // Store a reference to the transparency value label
        backgroundAlphaValueLabel = transparencyValueLabel
        
        // Then create the slider with a custom action - MOVED DOWN
        backgroundAlphaSlider = NSSlider(frame: NSRect(x: 180, y: appearanceTab.bounds.height - 380, width: 200, height: 20))
        backgroundAlphaSlider.minValue = 0.0
        backgroundAlphaSlider.maxValue = 1.0
        backgroundAlphaSlider.target = self
        backgroundAlphaSlider.action = #selector(backgroundAlphaSliderChanged)
        backgroundAlphaSlider.tag = transparencyValueLabel.hash // Store the label's hash in the slider's tag
        appearanceTab.addSubview(backgroundAlphaSlider)
        
        // Add more space - Full clipboard transparency checkbox - INCREASED SPACING
        fullClipboardTransparencyCheckbox = NSButton(checkboxWithTitle: "Enable full clipboard transparency", target: self, action: #selector(applyChanges))
        fullClipboardTransparencyCheckbox.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 460, width: 300, height: 20) // More space
        appearanceTab.addSubview(fullClipboardTransparencyCheckbox)
        
        // Add explanation for full clipboard transparency with more space - INCREASED SPACING
        let fullTransparencyExplanationLabel = NSTextField(labelWithString: "Makes the entire clipboard window transparent, not just individual items")
        fullTransparencyExplanationLabel.frame = NSRect(x: 40, y: appearanceTab.bounds.height - 480, width: 350, height: 16) // More space
        fullTransparencyExplanationLabel.font = NSFont.systemFont(ofSize: 10)
        fullTransparencyExplanationLabel.textColor = NSColor.secondaryLabelColor
        fullTransparencyExplanationLabel.isEditable = false
        fullTransparencyExplanationLabel.isBordered = false
        fullTransparencyExplanationLabel.drawsBackground = false
        appearanceTab.addSubview(fullTransparencyExplanationLabel)
        
        // NEW: Clipboard window background color section with more space - INCREASED SPACING
        let windowBackgroundColorLabel = NSTextField(labelWithString: "Clipboard window background color:")
        windowBackgroundColorLabel.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 560, width: 200, height: 20) // More space
        appearanceTab.addSubview(windowBackgroundColorLabel)
        
        // Add a new color picker for window background - INCREASED SPACING
        windowBackgroundColorPicker = TerminalStyleColorPicker(
            frame: NSRect(x: 180, y: appearanceTab.bounds.height - 670, width: 150, height: 90), // More space
            initialColor: NSColor.windowBackgroundColor,
            action: { [weak self] color in
                self?.applyChanges()
            }
        )
        appearanceTab.addSubview(windowBackgroundColorPicker)
        
        // Text color section with more space - INCREASED SPACING
        let textColorLabel = NSTextField(labelWithString: "Text color:")
        textColorLabel.frame = NSRect(x: 20, y: appearanceTab.bounds.height - 740, width: 150, height: 20) // More space
        appearanceTab.addSubview(textColorLabel)
        
        // Replace NSColorWell with TerminalStyleColorPicker - INCREASED SPACING
        textColorPicker = TerminalStyleColorPicker(
            frame: NSRect(x: 180, y: appearanceTab.bounds.height - 850, width: 150, height: 90), // More space
            initialColor: NSColor.black,
            action: { [weak self] color in
                self?.applyChanges()
            }
        )
        appearanceTab.addSubview(textColorPicker)
        
        // Add a note about live preview
        let livePreviewLabel = NSTextField(labelWithString: "Changes are applied in real-time to the clipboard window")
        livePreviewLabel.frame = NSRect(x: 20, y: 20, width: appearanceTab.bounds.width - 40, height: 20)
        livePreviewLabel.font = NSFont.systemFont(ofSize: 12)
        livePreviewLabel.textColor = NSColor.secondaryLabelColor
        livePreviewLabel.isEditable = false
        livePreviewLabel.isBordered = false
        livePreviewLabel.drawsBackground = false
        livePreviewLabel.alignment = .center
        appearanceTab.addSubview(livePreviewLabel)
        
        // Set the scroll view as the tab view's content
        scrollView.documentView = appearanceTab
        
        // Scroll to the top initially
        if let documentView = scrollView.documentView {
            let clipViewBounds = scrollView.contentView.bounds
            let documentFrame = documentView.frame
            
            // Calculate the point to scroll to (top of the document)
            let topPoint = NSPoint(
                x: clipViewBounds.origin.x,
                y: documentFrame.size.height - clipViewBounds.size.height
            )
            
            // Scroll to the top
            documentView.scroll(topPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        
        // Make sure tabView is initialized and has at least one item
        if tabView.tabViewItems.count == 0 {
            let appearanceItem = NSTabViewItem(identifier: "appearance")
            appearanceItem.label = "Appearance"
            appearanceItem.view = scrollView
            tabView.addTabViewItem(appearanceItem)
        } else {
            // Set the scroll view as the first tab's view
            tabView.tabViewItems[0].view = scrollView
        }
    }
    
    private func setupSizeTab() {
        // Create a scroll view to contain all size settings
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.autoresizingMask = [.width, .height]
        
        // Create a content view that's taller to accommodate all settings
        sizeTab = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width - 20, height: 500))
        
        // Set the document view of the scroll view
        scrollView.documentView = sizeTab
        
        // Section title for Card settings
        let cardSectionLabel = NSTextField(labelWithString: "Card Settings")
        cardSectionLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 40, width: 200, height: 24)
        cardSectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        cardSectionLabel.textColor = NSColor.labelColor
        sizeTab.addSubview(cardSectionLabel)
        
        // Card height
        let cardHeightLabel = NSTextField(labelWithString: "Card height:")
        cardHeightLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 80, width: 150, height: 20)
        sizeTab.addSubview(cardHeightLabel)
        
        // Create value label first
        let cardHeightValueLabel = NSTextField(frame: NSRect(x: 390, y: sizeTab.bounds.height - 80, width: 50, height: 20))
        cardHeightValueLabel.isEditable = false
        cardHeightValueLabel.isBordered = false
        cardHeightValueLabel.drawsBackground = false
        cardHeightValueLabel.stringValue = "100"
        sizeTab.addSubview(cardHeightValueLabel)
        
        // Then create the slider with a custom action
        cardHeightSlider = NSSlider(frame: NSRect(x: 180, y: sizeTab.bounds.height - 80, width: 200, height: 20))
        cardHeightSlider.minValue = 50
        cardHeightSlider.maxValue = 200
        cardHeightSlider.target = self
        cardHeightSlider.action = #selector(cardHeightSliderChanged)
        cardHeightSlider.tag = cardHeightValueLabel.hash
        sizeTab.addSubview(cardHeightSlider)
        
        // Card spacing
        let cardSpacingLabel = NSTextField(labelWithString: "Card spacing:")
        cardSpacingLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 120, width: 150, height: 20)
        sizeTab.addSubview(cardSpacingLabel)
        
        // Create value label first
        let cardSpacingValueLabel = NSTextField(frame: NSRect(x: 390, y: sizeTab.bounds.height - 120, width: 50, height: 20))
        cardSpacingValueLabel.isEditable = false
        cardSpacingValueLabel.isBordered = false
        cardSpacingValueLabel.drawsBackground = false
        cardSpacingValueLabel.stringValue = "10"
        sizeTab.addSubview(cardSpacingValueLabel)
        
        // Then create the slider with a custom action
        cardSpacingSlider = NSSlider(frame: NSRect(x: 180, y: sizeTab.bounds.height - 120, width: 200, height: 20))
        cardSpacingSlider.minValue = 0
        cardSpacingSlider.maxValue = 30
        cardSpacingSlider.target = self
        cardSpacingSlider.action = #selector(cardSpacingSliderChanged)
        cardSpacingSlider.tag = cardSpacingValueLabel.hash
        sizeTab.addSubview(cardSpacingSlider)
        
        // Section title for Window settings
        let windowSectionLabel = NSTextField(labelWithString: "Window Settings")
        windowSectionLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 170, width: 200, height: 24)
        windowSectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        windowSectionLabel.textColor = NSColor.labelColor
        sizeTab.addSubview(windowSectionLabel)
        
        // Window width
        let windowWidthLabel = NSTextField(labelWithString: "Window width:")
        windowWidthLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 210, width: 150, height: 20)
        sizeTab.addSubview(windowWidthLabel)
        
        // Create value label first
        let windowWidthValueLabel = NSTextField(frame: NSRect(x: 390, y: sizeTab.bounds.height - 210, width: 50, height: 20))
        windowWidthValueLabel.isEditable = false
        windowWidthValueLabel.isBordered = false
        windowWidthValueLabel.drawsBackground = false
        windowWidthValueLabel.stringValue = "500"
        sizeTab.addSubview(windowWidthValueLabel)
        
        // Then create the slider with a custom action
        windowWidthSlider = NSSlider(frame: NSRect(x: 180, y: sizeTab.bounds.height - 210, width: 200, height: 20))
        windowWidthSlider.minValue = 300
        windowWidthSlider.maxValue = 800
        windowWidthSlider.target = self
        windowWidthSlider.action = #selector(windowWidthSliderChanged)
        windowWidthSlider.tag = windowWidthValueLabel.hash
        sizeTab.addSubview(windowWidthSlider)
        
        // Window height
        let windowHeightLabel = NSTextField(labelWithString: "Window height:")
        windowHeightLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 250, width: 150, height: 20)
        sizeTab.addSubview(windowHeightLabel)
        
        // Create value label first
        let windowHeightValueLabel = NSTextField(frame: NSRect(x: 390, y: sizeTab.bounds.height - 250, width: 50, height: 20))
        windowHeightValueLabel.isEditable = false
        windowHeightValueLabel.isBordered = false
        windowHeightValueLabel.drawsBackground = false
        windowHeightValueLabel.stringValue = "600"
        sizeTab.addSubview(windowHeightValueLabel)
        
        // Then create the slider with a custom action
        windowHeightSlider = NSSlider(frame: NSRect(x: 180, y: sizeTab.bounds.height - 250, width: 200, height: 20))
        windowHeightSlider.minValue = 300
        windowHeightSlider.maxValue = 800
        windowHeightSlider.target = self
        windowHeightSlider.action = #selector(windowHeightSliderChanged)
        windowHeightSlider.tag = windowHeightValueLabel.hash
        sizeTab.addSubview(windowHeightSlider)
        
        // Section title for History settings
        let historySectionLabel = NSTextField(labelWithString: "History Settings")
        historySectionLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 300, width: 200, height: 24)
        historySectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        historySectionLabel.textColor = NSColor.labelColor
        sizeTab.addSubview(historySectionLabel)
        
        // Max history items
        let maxHistoryItemsLabel = NSTextField(labelWithString: "Max history items:")
        maxHistoryItemsLabel.frame = NSRect(x: 20, y: sizeTab.bounds.height - 340, width: 150, height: 20)
        sizeTab.addSubview(maxHistoryItemsLabel)
        
        // Create value label first
        let maxHistoryItemsValueLabel = NSTextField(frame: NSRect(x: 390, y: sizeTab.bounds.height - 340, width: 50, height: 20))
        maxHistoryItemsValueLabel.isEditable = false
        maxHistoryItemsValueLabel.isBordered = false
        maxHistoryItemsValueLabel.drawsBackground = false
        maxHistoryItemsValueLabel.stringValue = "20"
        sizeTab.addSubview(maxHistoryItemsValueLabel)
        
        // Then create the slider with a custom action
        maxHistoryItemsSlider = NSSlider(frame: NSRect(x: 180, y: sizeTab.bounds.height - 340, width: 200, height: 20))
        maxHistoryItemsSlider.minValue = 5
        maxHistoryItemsSlider.maxValue = 100
        maxHistoryItemsSlider.intValue = 20 // Set default value to 20
        maxHistoryItemsSlider.target = self
        maxHistoryItemsSlider.action = #selector(maxHistoryItemsSliderChanged)
        maxHistoryItemsSlider.tag = maxHistoryItemsValueLabel.hash
        sizeTab.addSubview(maxHistoryItemsSlider)
        
        // Scroll to the top initially
        if let documentView = scrollView.documentView {
            let clipViewBounds = scrollView.contentView.bounds
            let documentFrame = documentView.frame
            
            // Calculate the point to scroll to (top of the document)
            let topPoint = NSPoint(
                x: clipViewBounds.origin.x,
                y: documentFrame.size.height - clipViewBounds.size.height
            )
            
            // Scroll to the top
            documentView.scroll(topPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        
        // Make sure tabView is initialized and has at least two items
        if tabView.tabViewItems.count < 2 {
            let sizeItem = NSTabViewItem(identifier: "size")
            sizeItem.label = "Size"
            sizeItem.view = scrollView
            tabView.addTabViewItem(sizeItem)
        } else if tabView.tabViewItems.count >= 2 {
            // Set the scroll view as the second tab's view
            tabView.tabViewItems[1].view = scrollView
        }
    }
    
    private func setupBehaviorTab() {
        // Create a scroll view to contain all behavior settings
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width, height: tabView.bounds.height))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        behaviorTab = NSView(frame: NSRect(x: 0, y: 0, width: tabView.bounds.width - 20, height: 600)) // Increased height for hotkey UI
        
        // Set the document view
        scrollView.documentView = behaviorTab
        
        // Section title for Window behavior
        let windowBehaviorSectionLabel = NSTextField(labelWithString: "Window Behavior")
        windowBehaviorSectionLabel.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 40, width: 200, height: 24)
        windowBehaviorSectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        windowBehaviorSectionLabel.textColor = NSColor.labelColor
        behaviorTab.addSubview(windowBehaviorSectionLabel)
        
        // Auto paste checkbox
        autoPasteCheckbox = NSButton(checkboxWithTitle: "Auto-paste after copying", target: self, action: #selector(applyChanges))
        autoPasteCheckbox.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 80, width: 250, height: 20)
        behaviorTab.addSubview(autoPasteCheckbox)
        
        // Auto paste explanation
        let autoPasteExplanation = NSTextField(labelWithString: "Automatically pastes the copied item after selection")
        autoPasteExplanation.frame = NSRect(x: 40, y: behaviorTab.bounds.height - 100, width: 350, height: 16)
        autoPasteExplanation.font = NSFont.systemFont(ofSize: 10)
        autoPasteExplanation.textColor = NSColor.secondaryLabelColor
        autoPasteExplanation.isEditable = false
        autoPasteExplanation.isBordered = false
        autoPasteExplanation.drawsBackground = false
        behaviorTab.addSubview(autoPasteExplanation)
        
        // Section title for Hotkey settings
        let hotkeySectionLabel = NSTextField(labelWithString: "Keyboard Shortcut")
        hotkeySectionLabel.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 190, width: 200, height: 24)
        hotkeySectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        hotkeySectionLabel.textColor = NSColor.labelColor
        behaviorTab.addSubview(hotkeySectionLabel)
        
        // Hotkey explanation
        let hotkeyExplanation = NSTextField(labelWithString: "Customize the keyboard shortcut to show the clipboard history")
        hotkeyExplanation.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 215, width: 350, height: 16)
        hotkeyExplanation.font = NSFont.systemFont(ofSize: 12)
        hotkeyExplanation.textColor = NSColor.secondaryLabelColor
        hotkeyExplanation.isEditable = false
        hotkeyExplanation.isBordered = false
        hotkeyExplanation.drawsBackground = false
        behaviorTab.addSubview(hotkeyExplanation)
        
        // Modifier checkboxes
        hotkeyCommandCheckbox = NSButton(checkboxWithTitle: "⌘ Command", target: self, action: #selector(applyChanges))
        hotkeyCommandCheckbox.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 245, width: 120, height: 20)
        behaviorTab.addSubview(hotkeyCommandCheckbox)
        
        hotkeyShiftCheckbox = NSButton(checkboxWithTitle: "⇧ Shift", target: self, action: #selector(applyChanges))
        hotkeyShiftCheckbox.frame = NSRect(x: 150, y: behaviorTab.bounds.height - 245, width: 100, height: 20)
        behaviorTab.addSubview(hotkeyShiftCheckbox)
        
        hotkeyOptionCheckbox = NSButton(checkboxWithTitle: "⌥ Option", target: self, action: #selector(applyChanges))
        hotkeyOptionCheckbox.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 275, width: 120, height: 20)
        behaviorTab.addSubview(hotkeyOptionCheckbox)
        
        hotkeyControlCheckbox = NSButton(checkboxWithTitle: "⌃ Control", target: self, action: #selector(applyChanges))
        hotkeyControlCheckbox.frame = NSRect(x: 150, y: behaviorTab.bounds.height - 275, width: 120, height: 20)
        behaviorTab.addSubview(hotkeyControlCheckbox)
        
        // Key popup
        let keyLabel = NSTextField(labelWithString: "Key:")
        keyLabel.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 305, width: 40, height: 20)
        keyLabel.isEditable = false
        keyLabel.isBordered = false
        keyLabel.drawsBackground = false
        behaviorTab.addSubview(keyLabel)
        
        hotkeyKeyPopup = NSPopUpButton(frame: NSRect(x: 70, y: behaviorTab.bounds.height - 305, width: 100, height: 20))
        
        // Add common keys to the popup
        let commonKeys = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", 
                          "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
                          "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
                          "Space", "Tab", "Return",
                          "Up Arrow", "Down Arrow", "Left Arrow", "Right Arrow",
                          "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
        
        hotkeyKeyPopup.addItems(withTitles: commonKeys)
        hotkeyKeyPopup.target = self
        hotkeyKeyPopup.action = #selector(applyChanges)
        behaviorTab.addSubview(hotkeyKeyPopup)
        
        // Hotkey warning
        let hotkeyWarning = NSTextField(labelWithString: "Note: Changes to keyboard shortcut will take effect after restarting the app")
        hotkeyWarning.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 335, width: 350, height: 16)
        hotkeyWarning.font = NSFont.systemFont(ofSize: 10)
        hotkeyWarning.textColor = NSColor.secondaryLabelColor
        hotkeyWarning.isEditable = false
        hotkeyWarning.isBordered = false
        hotkeyWarning.drawsBackground = false
        behaviorTab.addSubview(hotkeyWarning)
        
        // Section title for Notification settings
        let notificationsSectionLabel = NSTextField(labelWithString: "Notifications")
        notificationsSectionLabel.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 365, width: 200, height: 24)
        notificationsSectionLabel.font = NSFont.boldSystemFont(ofSize: 14)
        notificationsSectionLabel.textColor = NSColor.labelColor
        behaviorTab.addSubview(notificationsSectionLabel)
        
        // Show notifications checkbox
        showNotificationsCheckbox = NSButton(checkboxWithTitle: "Show notifications", target: self, action: #selector(applyChanges))
        showNotificationsCheckbox.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 395, width: 200, height: 20)
        behaviorTab.addSubview(showNotificationsCheckbox)
        
        // Show notifications explanation
        let showNotificationsExplanation = NSTextField(labelWithString: "Display notifications when items are copied to clipboard")
        showNotificationsExplanation.frame = NSRect(x: 40, y: behaviorTab.bounds.height - 415, width: 350, height: 16)
        showNotificationsExplanation.font = NSFont.systemFont(ofSize: 10)
        showNotificationsExplanation.textColor = NSColor.secondaryLabelColor
        showNotificationsExplanation.isEditable = false
        showNotificationsExplanation.isBordered = false
        showNotificationsExplanation.drawsBackground = false
        behaviorTab.addSubview(showNotificationsExplanation)
        
        // Launch at startup checkbox
        launchAtStartupCheckbox = NSButton(checkboxWithTitle: "Launch at system startup", target: self, action: #selector(applyChanges))
        launchAtStartupCheckbox.frame = NSRect(x: 20, y: behaviorTab.bounds.height - 130, width: 250, height: 20)
        behaviorTab.addSubview(launchAtStartupCheckbox)
        
        // Launch at startup explanation
        let launchAtStartupExplanation = NSTextField(labelWithString: "Automatically launch Clipboard Manager when you log in")
        launchAtStartupExplanation.frame = NSRect(x: 40, y: behaviorTab.bounds.height - 150, width: 350, height: 16)
        launchAtStartupExplanation.font = NSFont.systemFont(ofSize: 10)
        launchAtStartupExplanation.textColor = NSColor.secondaryLabelColor
        launchAtStartupExplanation.isEditable = false
        launchAtStartupExplanation.isBordered = false
        launchAtStartupExplanation.drawsBackground = false
        behaviorTab.addSubview(launchAtStartupExplanation)
        
        // Scroll to the top initially
        if let documentView = scrollView.documentView {
            let clipViewBounds = scrollView.contentView.bounds
            let documentFrame = documentView.frame
            
            // Calculate the point to scroll to (top of the document)
            let topPoint = NSPoint(
                x: clipViewBounds.origin.x,
                y: documentFrame.size.height - clipViewBounds.size.height
            )
            
            // Scroll to the top
            documentView.scroll(topPoint)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        
        // Make sure tabView is initialized and has at least three items
        if tabView.tabViewItems.count < 3 {
            let behaviorItem = NSTabViewItem(identifier: "behavior")
            behaviorItem.label = "Behavior"
            behaviorItem.view = scrollView
            tabView.addTabViewItem(behaviorItem)
        } else if tabView.tabViewItems.count >= 3 {
            // Set the scroll view as the third tab's view
            tabView.tabViewItems[2].view = scrollView
        }
    }
    
    private func loadPreferences() {
        let prefs = Preferences.shared
        
        // Make sure all UI elements are initialized
        guard useSystemAppearanceCheckbox != nil &&
              darkModeCheckbox != nil &&
              customizeAppearanceCheckbox != nil &&
              backgroundColorPicker != nil &&
              backgroundAlphaSlider != nil &&
              textColorPicker != nil &&
              fullClipboardTransparencyCheckbox != nil &&
              windowBackgroundColorPicker != nil &&
              cardHeightSlider != nil &&
              cardSpacingSlider != nil &&
              windowWidthSlider != nil &&
              windowHeightSlider != nil &&
              maxHistoryItemsSlider != nil &&
              showNotificationsCheckbox != nil &&
              autoPasteCheckbox != nil &&
              launchAtStartupCheckbox != nil &&
              hotkeyKeyPopup != nil &&
              hotkeyCommandCheckbox != nil &&
              hotkeyShiftCheckbox != nil &&
              hotkeyOptionCheckbox != nil &&
              hotkeyControlCheckbox != nil else {
            print("ERROR: UI elements not fully initialized in loadPreferences")
            return
        }
        
        // Appearance - set only one checkbox based on preferences
        if prefs.useSystemAppearance {
            useSystemAppearanceCheckbox.state = .on
            darkModeCheckbox.state = .off
            customizeAppearanceCheckbox.state = .off
        } else if prefs.darkMode {
            useSystemAppearanceCheckbox.state = .off
            darkModeCheckbox.state = .on
            customizeAppearanceCheckbox.state = .off
        } else if prefs.customizeAppearance {
            useSystemAppearanceCheckbox.state = .off
            darkModeCheckbox.state = .off
            customizeAppearanceCheckbox.state = .on
        } else {
            // Default to system appearance if nothing is set
            useSystemAppearanceCheckbox.state = .on
            darkModeCheckbox.state = .off
            customizeAppearanceCheckbox.state = .off
            prefs.useSystemAppearance = true
        }
        
        // Set initial visibility of customization controls based on customizeAppearance setting
        let isCustomizing = prefs.customizeAppearance
        backgroundColorPicker.isHidden = !isCustomizing
        backgroundAlphaSlider.isHidden = !isCustomizing
        backgroundAlphaValueLabel?.isHidden = !isCustomizing
        textColorPicker.isHidden = !isCustomizing
        windowBackgroundColorPicker.isHidden = !isCustomizing
        fullClipboardTransparencyCheckbox.isHidden = !isCustomizing
        
        // Also hide the labels when customization is off
        for subview in appearanceTab.subviews {
            if let textField = subview as? NSTextField, 
               textField.isEditable == false && 
               textField.isBordered == false &&
               textField != backgroundAlphaValueLabel {
                // Skip the live preview label at the bottom and the section title
                if textField.frame.origin.y > 50 && 
                   textField.frame.origin.y < appearanceTab.bounds.height - 50 {
                    textField.isHidden = !isCustomizing
                }
            }
        }
        
        if let color = NSColor.fromHex(prefs.cardBackgroundColor) {
            backgroundColorPicker.color = color
        }
        
        backgroundAlphaSlider.floatValue = prefs.cardBackgroundAlpha
        
        if let color = NSColor.fromHex(prefs.textColor) {
            textColorPicker.color = color
        }
        
        // Set window background color
        if let color = NSColor.fromHex(prefs.windowBackgroundColor) {
            windowBackgroundColorPicker.color = color
        }
        
        // Set state for full clipboard transparency
        fullClipboardTransparencyCheckbox.state = prefs.fullClipboardTransparency ? .on : .off
        
        // Size
        cardHeightSlider.intValue = Int32(prefs.cardHeight)
        cardSpacingSlider.intValue = Int32(prefs.cardSpacing)
        windowWidthSlider.intValue = Int32(prefs.windowWidth)
        windowHeightSlider.intValue = Int32(prefs.windowHeight)
        maxHistoryItemsSlider.intValue = Int32(prefs.maxHistoryItems)
        
        // Behavior
        showNotificationsCheckbox.state = prefs.showNotifications ? .on : .off
        autoPasteCheckbox.state = prefs.autoPaste ? .on : .off
        launchAtStartupCheckbox.state = prefs.launchAtStartup ? .on : .off
        
        // Hotkey
        hotkeyKeyPopup.selectItem(at: prefs.hotkeyKeyIndex)
        hotkeyCommandCheckbox.state = prefs.hotkeyCommand ? .on : .off
        hotkeyShiftCheckbox.state = prefs.hotkeyShift ? .on : .off
        hotkeyOptionCheckbox.state = prefs.hotkeyOption ? .on : .off
        hotkeyControlCheckbox.state = prefs.hotkeyControl ? .on : .off
        
        applyChanges()
    }
    
    @objc private func toggleAppearanceOption(_ sender: NSButton) {
        // Determine which checkbox was clicked
        if sender == useSystemAppearanceCheckbox && sender.state == .on {
            // If system appearance is checked, uncheck the others
            darkModeCheckbox.state = .off
            customizeAppearanceCheckbox.state = .off
        } else if sender == darkModeCheckbox && sender.state == .on {
            // If dark mode is checked, uncheck the others
            useSystemAppearanceCheckbox.state = .off
            customizeAppearanceCheckbox.state = .off
        } else if sender == customizeAppearanceCheckbox && sender.state == .on {
            // If customize appearance is checked, uncheck the others
            useSystemAppearanceCheckbox.state = .off
            darkModeCheckbox.state = .off
        }
        
        // Handle visibility of customization controls
        let isCustomizing = customizeAppearanceCheckbox.state == .on
        
        // Toggle visibility of customization controls
        backgroundColorPicker.isHidden = !isCustomizing
        backgroundAlphaSlider.isHidden = !isCustomizing
        backgroundAlphaValueLabel?.isHidden = !isCustomizing
        textColorPicker.isHidden = !isCustomizing
        windowBackgroundColorPicker.isHidden = !isCustomizing
        fullClipboardTransparencyCheckbox.isHidden = !isCustomizing
        
        // Also hide the labels when customization is off
        for subview in appearanceTab.subviews {
            if let textField = subview as? NSTextField, 
               textField.isEditable == false && 
               textField.isBordered == false &&
               textField != backgroundAlphaValueLabel {
                // Skip the live preview label at the bottom and the section title
                if textField.frame.origin.y > 50 && 
                   textField.frame.origin.y < appearanceTab.bounds.height - 50 {
                    textField.isHidden = !isCustomizing
                }
            }
        }
        
        applyChanges()
    }
    
    @objc private func applyChanges() {
        // Save the current preferences temporarily
        let prefs = Preferences.shared
        
        // Update preferences with current values based on which option is selected
        prefs.useSystemAppearance = useSystemAppearanceCheckbox.state == .on
        prefs.darkMode = darkModeCheckbox.state == .on
        prefs.customizeAppearance = customizeAppearanceCheckbox.state == .on
        
        // Only apply these settings if customization is enabled
        if prefs.customizeAppearance {
            prefs.cardBackgroundColor = backgroundColorPicker.color.toHex()
            prefs.cardBackgroundAlpha = backgroundAlphaSlider.floatValue
            prefs.textColor = textColorPicker.color.toHex()
            prefs.fullClipboardTransparency = fullClipboardTransparencyCheckbox.state == .on
            prefs.windowBackgroundColor = windowBackgroundColorPicker.color.toHex()
        }
        
        // Update size preferences
        prefs.cardHeight = Int(cardHeightSlider.intValue)
        prefs.cardSpacing = Int(cardSpacingSlider.intValue)
        prefs.windowWidth = Int(windowWidthSlider.intValue)
        prefs.windowHeight = Int(windowHeightSlider.intValue)
        prefs.maxHistoryItems = Int(maxHistoryItemsSlider.intValue)
        
        // Update behavior preferences
        prefs.showNotifications = showNotificationsCheckbox.state == .on
        prefs.autoPaste = autoPasteCheckbox.state == .on
        prefs.launchAtStartup = launchAtStartupCheckbox.state == .on
        
        // Update hotkey preferences
        prefs.hotkeyKeyIndex = hotkeyKeyPopup.indexOfSelectedItem
        prefs.hotkeyCommand = hotkeyCommandCheckbox.state == .on
        prefs.hotkeyShift = hotkeyShiftCheckbox.state == .on
        prefs.hotkeyOption = hotkeyOptionCheckbox.state == .on
        prefs.hotkeyControl = hotkeyControlCheckbox.state == .on
        
        // Save preferences to disk
        prefs.savePreferences()
        
        // The preferences window should always use system appearance
        // This is handled by the AppDelegate's applyAppearanceSettings method
        
        // Notify that preferences have changed to update the clipboard window in real-time
        NotificationCenter.default.post(name: NSNotification.Name("PreferencesChanged"), object: nil)
        
        // Update all value labels
        updateValueLabels()
    }
    
    // Helper method to update all value labels
    private func updateValueLabels() {
        // Find all value labels in the size tab and update them
        if let scrollView = tabView.tabViewItems[1].view as? NSScrollView,
           let sizeTabView = scrollView.documentView {
            for subview in sizeTabView.subviews {
                if let textField = subview as? NSTextField, 
                   textField.frame.origin.x > 380 && textField.frame.size.width == 50 {
                    
                    // Determine which slider this label corresponds to
                    let y = textField.frame.origin.y
                    
                    if abs(y - (sizeTabView.bounds.height - 80)) < 5 {
                        // Card height value
                        textField.stringValue = "\(Int(cardHeightSlider.intValue))"
                    } else if abs(y - (sizeTabView.bounds.height - 120)) < 5 {
                        // Card spacing value
                        textField.stringValue = "\(Int(cardSpacingSlider.intValue))"
                    } else if abs(y - (sizeTabView.bounds.height - 210)) < 5 {
                        // Window width value
                        textField.stringValue = "\(Int(windowWidthSlider.intValue))"
                    } else if abs(y - (sizeTabView.bounds.height - 250)) < 5 {
                        // Window height value
                        textField.stringValue = "\(Int(windowHeightSlider.intValue))"
                    } else if abs(y - (sizeTabView.bounds.height - 340)) < 5 {
                        // Max history items value
                        textField.stringValue = "\(Int(maxHistoryItemsSlider.intValue))"
                    }
                }
            }
        }
        
        // Update transparency value in Appearance tab
        if let scrollView = tabView.tabViewItems[0].view as? NSScrollView,
           let appearanceTabView = scrollView.documentView {
            for subview in appearanceTabView.subviews {
                if let textField = subview as? NSTextField,
                   textField.frame.origin.x > 380 && textField.frame.size.width == 50 &&
                   abs(textField.frame.origin.y - (appearanceTabView.bounds.height - 210)) < 5 {
                    // Background transparency value
                    textField.stringValue = String(format: "%.2f", backgroundAlphaSlider.floatValue)
                }
            }
        }
    }
    
    @objc private func savePreferences() {
        let prefs = Preferences.shared
        
        // Appearance - set based on which checkbox is selected
        prefs.useSystemAppearance = useSystemAppearanceCheckbox.state == .on
        prefs.darkMode = darkModeCheckbox.state == .on
        prefs.customizeAppearance = customizeAppearanceCheckbox.state == .on
        
        // Only save customization settings if customization is enabled
        if prefs.customizeAppearance {
            prefs.cardBackgroundColor = backgroundColorPicker.color.toHex()
            prefs.cardBackgroundAlpha = backgroundAlphaSlider.floatValue
            prefs.textColor = textColorPicker.color.toHex()
            prefs.fullClipboardTransparency = fullClipboardTransparencyCheckbox.state == .on
            prefs.windowBackgroundColor = windowBackgroundColorPicker.color.toHex()
        }
        
        // Size
        prefs.cardHeight = Int(cardHeightSlider.intValue)
        prefs.cardSpacing = Int(cardSpacingSlider.intValue)
        prefs.windowWidth = Int(windowWidthSlider.intValue)
        prefs.windowHeight = Int(windowHeightSlider.intValue)
        prefs.maxHistoryItems = Int(maxHistoryItemsSlider.intValue)
        
        // Behavior
        prefs.showNotifications = showNotificationsCheckbox.state == .on
        prefs.autoPaste = autoPasteCheckbox.state == .on
        prefs.launchAtStartup = launchAtStartupCheckbox.state == .on
        
        // Hotkey
        prefs.hotkeyKeyIndex = hotkeyKeyPopup.indexOfSelectedItem
        prefs.hotkeyCommand = hotkeyCommandCheckbox.state == .on
        prefs.hotkeyShift = hotkeyShiftCheckbox.state == .on
        prefs.hotkeyOption = hotkeyOptionCheckbox.state == .on
        prefs.hotkeyControl = hotkeyControlCheckbox.state == .on
        
        // Save preferences
        prefs.savePreferences()
        
        // Notify that preferences have changed
        NotificationCenter.default.post(name: NSNotification.Name("PreferencesChanged"), object: nil)
        
        window?.close()
    }
    
    @objc private func cancelPreferences() {
        window?.close()
    }
    
    // Add slider change handlers
    @objc private func backgroundAlphaSliderChanged(_ sender: NSSlider) {
        // Find the label by its hash stored in the slider's tag
        for subview in appearanceTab.subviews {
            if let textField = subview as? NSTextField, textField.hash == sender.tag {
                textField.stringValue = String(format: "%.2f", sender.floatValue)
                break
            }
        }
        
        // Apply changes immediately
        applyChanges()
    }
    
    @objc private func cardHeightSliderChanged(_ sender: NSSlider) {
        // Find the label by its hash stored in the slider's tag
        for subview in sizeTab.subviews {
            if let textField = subview as? NSTextField, textField.hash == sender.tag {
                textField.stringValue = "\(Int(sender.intValue))"
                break
            }
        }
        
        // Apply changes immediately
        applyChanges()
    }
    
    @objc private func cardSpacingSliderChanged(_ sender: NSSlider) {
        // Find the label by its hash stored in the slider's tag
        for subview in sizeTab.subviews {
            if let textField = subview as? NSTextField, textField.hash == sender.tag {
                textField.stringValue = "\(Int(sender.intValue))"
                break
            }
        }
        
        // Apply changes immediately
        applyChanges()
    }
    
    @objc private func windowWidthSliderChanged(_ sender: NSSlider) {
        // Find the label by its hash stored in the slider's tag
        for subview in sizeTab.subviews {
            if let textField = subview as? NSTextField, textField.hash == sender.tag {
                textField.stringValue = "\(Int(sender.intValue))"
                break
            }
        }
        
        // Apply changes immediately
        applyChanges()
    }
    
    @objc private func windowHeightSliderChanged(_ sender: NSSlider) {
        // Find the label by its hash stored in the slider's tag
        for subview in sizeTab.subviews {
            if let textField = subview as? NSTextField, textField.hash == sender.tag {
                textField.stringValue = "\(Int(sender.intValue))"
                break
            }
        }
        
        // Apply changes immediately
        applyChanges()
    }
    
    @objc private func maxHistoryItemsSliderChanged(_ sender: NSSlider) {
        // Find the label by its hash stored in the slider's tag
        for subview in sizeTab.subviews {
            if let textField = subview as? NSTextField, textField.hash == sender.tag {
                textField.stringValue = "\(Int(sender.intValue))"
                break
            }
        }
        
        // Apply changes immediately
        applyChanges()
    }
}

// MARK: - NSWindowDelegate
extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Clean up any resources if needed
        print("PreferencesWindowController window will close")
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        print("PreferencesWindowController window did become key")
    }
    
    func windowDidResignKey(_ notification: Notification) {
        print("PreferencesWindowController window did resign key")
    }
} 