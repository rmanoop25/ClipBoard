#!/bin/bash
set -e

echo "Building ClipBoard..."
mkdir -p ClipBoard.app/Contents/MacOS
mkdir -p ClipBoard.app/Contents/Resources

# Generate app icon
if [ ! -f ClipBoard.app/Contents/Resources/AppIcon.icns ]; then
    echo "Generating app icon..."
    swiftc generate_icon.swift -o /tmp/clipboard_gen_icon -framework Cocoa
    /tmp/clipboard_gen_icon
    iconutil -c icns AppIcon.iconset -o ClipBoard.app/Contents/Resources/AppIcon.icns
    rm -rf AppIcon.iconset /tmp/clipboard_gen_icon
fi

# Compile
swiftc main.swift \
    -o ClipBoard.app/Contents/MacOS/ClipBoard \
    -framework Cocoa \
    -framework Carbon \
    -framework ServiceManagement \
    -O

echo "Done! App size: $(du -sh ClipBoard.app | cut -f1)"
echo ""
echo "To run:  open ClipBoard.app"
echo "To install: cp -r ClipBoard.app /Applications/"
