#!/bin/bash
set -e

echo "Building ClipBoard..."
mkdir -p ClipBoard.app/Contents/MacOS
mkdir -p ClipBoard.app/Contents/Resources

swiftc main.swift \
    -o ClipBoard.app/Contents/MacOS/ClipBoard \
    -framework Cocoa \
    -framework Carbon \
    -O

echo "Done! App size: $(du -sh ClipBoard.app | cut -f1)"
echo ""
echo "To run:  open ClipBoard.app"
echo "To install: cp -r ClipBoard.app /Applications/"
