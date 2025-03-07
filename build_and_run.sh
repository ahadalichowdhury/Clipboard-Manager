#!/bin/bash

# Exit on error
set -e

echo "=== Building Clipboard Manager ==="

# Clean build directory
echo "Cleaning build directory..."
xcodebuild clean -scheme "Clipboard Manager" -configuration Debug

# Build the app
echo "Building app..."
xcodebuild build -scheme "Clipboard Manager" -configuration Debug

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Clipboard Manager.app" -type d -path "*/Build/Products/Debug/*" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

echo "App built at: $APP_PATH"

# Remove quarantine attribute if present
echo "Removing quarantine attribute..."
xattr -cr "$APP_PATH"

# Check code signing
echo "Checking code signing..."
codesign -vv -d "$APP_PATH"

# Check entitlements
echo "Checking entitlements..."
codesign -d --entitlements :- "$APP_PATH"

# Kill existing instances
echo "Killing any existing instances..."
killall "Clipboard Manager" 2>/dev/null || true

# Wait a moment
sleep 1

# Run the app
echo "Running app..."
open "$APP_PATH"

echo "=== Done ==="
echo "If you're still having accessibility permission issues:"
echo "1. Open System Settings > Privacy & Security > Accessibility"
echo "2. Make sure Clipboard Manager is in the list and checked"
echo "3. If it's already there, try removing it and adding it again"
echo "4. Restart your Mac if the issue persists" 