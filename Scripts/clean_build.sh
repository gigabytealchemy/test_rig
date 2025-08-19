#!/bin/bash

# clean_build.sh - Remove Swift build artifacts from ALRPackages
# Usage: ./Scripts/clean_build.sh

echo "Cleaning ALRPackages build directory..."

# Change to the ALRPackages directory
cd "$(dirname "$0")/../Packages/ALRPackages" || exit 1

# Remove the .build directory if it exists
if [ -d ".build" ]; then
    rm -rf .build
    echo "✓ Removed .build directory"
else
    echo "✓ .build directory not found (already clean)"
fi

# Optional: Also clean other Swift artifacts
if [ -d ".swiftpm" ]; then
    rm -rf .swiftpm
    echo "✓ Removed .swiftpm directory"
fi

if [ -f "Package.resolved" ]; then
    rm -f Package.resolved
    echo "✓ Removed Package.resolved"
fi

echo "Clean complete!"
echo ""
echo "To rebuild, run:"
echo "  cd Packages/ALRPackages && swift build"