#!/bin/bash

# clean_and_rebuild.sh - Clean and optionally rebuild ALRPackages
# Usage: 
#   ./Scripts/clean_and_rebuild.sh          # Just clean
#   ./Scripts/clean_and_rebuild.sh --build  # Clean and rebuild
#   ./Scripts/clean_and_rebuild.sh --release # Clean and rebuild in release mode

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}ALRPackages Build Manager${NC}"
echo "========================="

# Change to the ALRPackages directory
SCRIPT_DIR="$(dirname "$0")"
PACKAGE_DIR="$SCRIPT_DIR/../Packages/ALRPackages"
cd "$PACKAGE_DIR" || exit 1

# Clean function
clean_build() {
    echo -e "\n${YELLOW}Cleaning build artifacts...${NC}"
    
    if [ -d ".build" ]; then
        rm -rf .build
        echo -e "${GREEN}✓${NC} Removed .build directory"
    else
        echo -e "${GREEN}✓${NC} .build directory not found (already clean)"
    fi
    
    if [ -d ".swiftpm" ]; then
        rm -rf .swiftpm
        echo -e "${GREEN}✓${NC} Removed .swiftpm directory"
    fi
    
    if [ -f "Package.resolved" ]; then
        rm -f Package.resolved
        echo -e "${GREEN}✓${NC} Removed Package.resolved"
    fi
    
    echo -e "${GREEN}Clean complete!${NC}"
}

# Build function
build_package() {
    local config="$1"
    echo -e "\n${YELLOW}Building package ($config)...${NC}"
    
    if [ "$config" = "release" ]; then
        swift build --configuration release
    else
        swift build
    fi
    
    echo -e "${GREEN}Build complete!${NC}"
}

# Main logic
clean_build

# Check for build flag
if [ "$1" = "--build" ]; then
    build_package "debug"
elif [ "$1" = "--release" ]; then
    build_package "release"
else
    echo -e "\n${YELLOW}Options:${NC}"
    echo "  --build    Clean and rebuild (debug)"
    echo "  --release  Clean and rebuild (release)"
    echo "  (no args)  Clean only"
fi

echo -e "\n${GREEN}Done!${NC}"