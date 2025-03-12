#!/bin/bash

# Exit on any error
set -e

echo "=== Building Clipboard Manager DMG ==="

# Step 1: Compile main.c separately
echo "Compiling main.c..."
clang -c Clipboard\ Manager/main.c -o main.o

# Step 2: Build the app in Release mode
echo "Building app in Release mode..."
xcodebuild -project ClipboardManager.xcodeproj -scheme "Clipboard Manager" -configuration Release clean build OTHER_LDFLAGS="main.o"

# Step 3: Prepare the DMG contents
echo "Preparing DMG contents..."
mkdir -p build/dmg
rm -rf build/dmg/*

# Find the latest build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Clipboard_Manager-*/Build/Products/Release -name "Clipboard Manager.app" -type d | head -n 1)
if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

# Copy the app to the DMG folder
cp -R "$APP_PATH" build/dmg/

# Copy the helper script and README
cp run_with_permissions.command build/dmg/
chmod +x build/dmg/run_with_permissions.command
cp README.txt build/dmg/

# Step 4: Create the DMG file
echo "Creating DMG file..."
hdiutil create -volname "Clipboard Manager" -srcfolder build/dmg -ov -format UDZO build/ClipboardManager.dmg

echo "=== DMG created successfully at build/ClipboardManager.dmg ===" 