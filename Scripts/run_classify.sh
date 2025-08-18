#!/bin/bash

# Change to the project directory
cd /Users/martin/Projects/TestRig

# Run the swift script with the proper module and library paths
swift \
    -I Packages/ALRPackages/.build/debug/Modules \
    -L Packages/ALRPackages/.build/debug \
    -lAnalyzers -lCoreTypes \
    -Xlinker -rpath -Xlinker @executable_path/../Packages/ALRPackages/.build/debug \
    Scripts/classify_csv.swift