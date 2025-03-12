#!/bin/bash

# Exit on any error
set -e

echo "=== Fixing Clipboard Manager Build ==="

# Step 1: Clean derived data
echo "Cleaning derived data..."
rm -rf ~/Library/Developer/Xcode/DerivedData/ClipboardManager-*

# Step 2: Update Swift Package Manager dependencies
echo "Updating Swift Package Manager dependencies..."
swift package update

# Step 3: Build the app in Debug mode first to test
echo "Building app in Debug mode using Swift Package Manager..."
swift build

# Step 4: If that works, try building with xcodebuild
echo "Building app with xcodebuild..."
xcodebuild -project ClipboardManager.xcodeproj -scheme "Clipboard Manager" -configuration Debug clean build

echo "=== Build fixed successfully ==="
echo "Now you can run build_dmg.sh to create the DMG file" 