#!/bin/bash
# Update BuildInfo.swift with current build time and git info
# Add this script as a "Run Script" build phase in Xcode (before Compile Sources)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_INFO_FILE="$SCRIPT_DIR/DMSAService/BuildInfo.swift"

# Get current timestamp
BUILD_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# Get git commit hash (short)
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

# Determine configuration
if [ "$CONFIGURATION" = "Debug" ]; then
    CONFIG="Debug"
else
    CONFIG="Release"
fi

# Generate BuildInfo.swift
cat > "$BUILD_INFO_FILE" << EOF
import Foundation

/// Build information - auto-generated during build
/// To update: Run \`swift build\` or build in Xcode (build script will update this file)
enum BuildInfo {
    /// Build timestamp (format: yyyy-MM-dd HH:mm:ss)
    /// This value is updated by the build script
    static let buildTime: String = "$BUILD_TIME"

    /// Git commit hash (short)
    static let gitCommit: String = "$GIT_COMMIT"

    /// Build configuration
    #if DEBUG
    static let configuration: String = "Debug"
    #else
    static let configuration: String = "Release"
    #endif
}
EOF

echo "Updated BuildInfo.swift: $BUILD_TIME ($GIT_COMMIT)"
