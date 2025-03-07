# Clipboard Manager

A powerful clipboard history manager for macOS that enhances your productivity by keeping track of everything you copy.

![Clipboard Manager Screenshot](screenshots/clipboard_manager.png)

## Features

- **Clipboard History**: Maintains a history of your clipboard items
- **Customizable Hotkeys**: Set your own keyboard shortcuts to show clipboard history (default: Command+Shift+V)
- **Dark Mode Support**: Seamlessly integrates with macOS dark mode
- **Customizable Appearance**: Change colors, transparency, and theme
- **Size Customization**: Adjust card height, window dimensions, and spacing
- **Auto-Paste Functionality**: Automatically paste after copying (optional)
- **Notifications**: Get notified of clipboard changes

## Installation

1. Download the latest release from the [Releases](https://github.com/ahadalichowdhury/Clipboard-Manager/releases) page
2. Mount the DMG file and drag "Clipboard Manager.app" to your Applications folder
3. Double-click on "run_with_permissions.command" to start the app with proper permissions
4. Grant accessibility permissions when prompted (required for clipboard monitoring)

## Requirements

- macOS 14.6 or later
- Apple Silicon or Intel Mac

## Usage

### Accessing Clipboard History

Press the default hotkey (Command+Shift+V) or your custom hotkey to show the clipboard history window.

### Preferences

Access preferences by:

- Clicking on the menu bar icon and selecting "Preferences"
- Using the keyboard shortcut Command+, (comma)

Customize:

- **Appearance**: Colors, transparency, and theme
- **Size**: Card height, window dimensions, and spacing
- **Behavior**: Auto-paste, notifications, and keyboard shortcuts

### Accessibility Permissions

Clipboard Manager requires accessibility permissions to:

- Monitor clipboard changes
- Paste content automatically (if enabled)
- Respond to keyboard shortcuts

To grant permissions:

1. Go to System Settings > Privacy & Security > Accessibility
2. Find "Clipboard Manager" in the list and enable it
3. If already enabled, toggle it off and on again
4. Restart the app after granting permissions

## Building from Source

### Prerequisites

- Xcode 15.0 or later
- macOS 14.6 or later

### Steps

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/clipboard-manager.git
   cd clipboard-manager
   ```

2. Open the Xcode project:

   ```bash
   open "Clipboard Manager.xcodeproj"
   ```

3. Build the project in Xcode (⌘+B) or use the build script:
   ```bash
   ./build_dmg.sh
   ```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [HotKey](https://github.com/soffes/HotKey) - Used for global keyboard shortcut handling
