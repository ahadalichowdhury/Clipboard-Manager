#!/bin/bash

# Exit on error
set -e

echo "=== Running Clipboard Manager with Permissions ==="

# Build the app first to ensure we have a fresh build
echo "Building the app..."
xcodebuild -scheme "Clipboard Manager" -configuration Debug build

# Find the built app (excluding Index.noindex paths)
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Clipboard Manager.app" -type d -path "*/Build/Products/Debug/*" | grep -v "Index.noindex" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

echo "App found at: $APP_PATH"

# Remove quarantine attribute if present
echo "Removing quarantine attribute..."
xattr -cr "$APP_PATH"

# Kill existing instances
echo "Killing any existing instances..."
killall "Clipboard Manager" 2>/dev/null || true

# Wait a moment
sleep 1

# Open System Settings to Accessibility permissions
echo "Opening System Settings to Accessibility permissions..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

# Wait a moment for System Settings to open
sleep 2

# Run the app
echo "Running app..."
open "$APP_PATH"

echo "=== Done ==="
echo "Please make sure to grant accessibility permissions to Clipboard Manager in System Settings"
echo "1. Find 'Clipboard Manager' in the list"
echo "2. Check the box next to it"
echo "3. If it's already checked, try unchecking and checking it again"
echo "4. Restart the app after granting permissions" 