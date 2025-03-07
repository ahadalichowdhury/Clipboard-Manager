#!/bin/bash

# This script helps run Clipboard Manager with the necessary permissions

# Get the directory where this script is located
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Path to the app
APP_PATH="$DIR/Clipboard Manager.app"

echo "Starting Clipboard Manager..."
echo "App path: $APP_PATH"

# Remove quarantine attribute if present
xattr -d com.apple.quarantine "$APP_PATH" 2>/dev/null || true

# Kill any existing instances
pkill -f "Clipboard Manager" 2>/dev/null || true

# Open the app
open "$APP_PATH"

echo ""
echo "Clipboard Manager has been started."
echo "IMPORTANT: Make sure to grant accessibility permissions in System Settings > Privacy & Security > Accessibility"
echo "1. Find 'Clipboard Manager' in the list"
echo "2. Check the box next to it"
echo "3. If already checked, uncheck and recheck it"
echo "4. Restart the app after granting permissions"
echo "" 