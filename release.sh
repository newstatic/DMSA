#!/bin/bash
#
# DMSA Release Script
# Usage: ./release.sh [version]
# Example: ./release.sh 4.9
#
# Steps:
#   1. Build Release DMSAApp + DMSAService
#   2. Code sign
#   3. Package into DMG
#   4. Create git tag
#   5. Push tag and create GitHub Release with DMG
#

set -euo pipefail

# ─── Config ──────────────────────────────────────────────────────────
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
XCODE_PROJECT="$PROJECT_ROOT/DMSAApp/DMSAApp.xcodeproj"
SCHEME="DMSAApp"
BUILD_DIR="$PROJECT_ROOT/build"
APP_NAME="DMSA"
BUNDLE_ID="com.ttttt.dmsa"
SERVICE_TARGET="com.ttttt.dmsa.service"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}" # Set env var or leave empty for ad-hoc

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ─── Version ─────────────────────────────────────────────────────────
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    # Read from pbxproj
    VERSION=$(grep -m1 'MARKETING_VERSION' "$XCODE_PROJECT/project.pbxproj" | sed 's/.*= *//;s/ *;.*//')
    if [ -z "$VERSION" ]; then
        err "Cannot detect version. Usage: $0 <version>"
    fi
    warn "No version specified, using MARKETING_VERSION: $VERSION"
fi

TAG="v$VERSION"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo ""
echo "  App:     $APP_NAME"
echo "  Version: $VERSION"
echo "  Tag:     $TAG"
echo "  DMG:     $DMG_NAME"
echo ""

# Check for existing tag
if git tag -l "$TAG" | grep -q "$TAG"; then
    err "Tag $TAG already exists. Bump version or delete the tag first."
fi

# ─── Clean ───────────────────────────────────────────────────────────
step "Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
log "Clean"

# ─── Build ───────────────────────────────────────────────────────────
step "Building Release"

xcodebuild \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    DSTROOT="$BUILD_DIR/dst" \
    SYMROOT="$BUILD_DIR/sym" \
    OBJROOT="$BUILD_DIR/obj" \
    clean build \
    2>&1 | tail -5

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    err "Build failed"
fi
log "Build succeeded"

# ─── Locate Products ────────────────────────────────────────────────
step "Locating build products"

APP_PATH=$(find "$BUILD_DIR" -name "${APP_NAME}.app" -type d | head -1)
SERVICE_PATH=$(find "$BUILD_DIR" -name "${SERVICE_TARGET}" -type f | head -1)

if [ -z "$APP_PATH" ]; then
    err "Cannot find ${APP_NAME}.app in $BUILD_DIR"
fi
log "App: $APP_PATH"

if [ -n "$SERVICE_PATH" ]; then
    log "Service: $SERVICE_PATH"
else
    warn "Service binary not found separately (may be embedded in app)"
fi

# ─── Package DMG ─────────────────────────────────────────────────────
step "Creating DMG"

DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app
cp -R "$APP_PATH" "$DMG_STAGING/"

# Copy service if separate
if [ -n "$SERVICE_PATH" ]; then
    mkdir -p "$DMG_STAGING/Service"
    cp "$SERVICE_PATH" "$DMG_STAGING/Service/"
fi

# Add symlink to Applications
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    2>&1 | tail -2

if [ ! -f "$DMG_PATH" ]; then
    err "DMG creation failed"
fi

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
log "DMG created: $DMG_PATH ($DMG_SIZE)"

# ─── Git Tag ─────────────────────────────────────────────────────────
step "Creating git tag"

git -C "$PROJECT_ROOT" tag -a "$TAG" -m "Release $VERSION"
log "Tag $TAG created"

git -C "$PROJECT_ROOT" push origin "$TAG"
log "Tag pushed to origin"

# ─── GitHub Release ──────────────────────────────────────────────────
step "Creating GitHub Release"

RELEASE_NOTES="## DMSA $VERSION

### Changes
- Fixed file ownership: files created via VFS now have correct user permissions
- Fixed indexing: auto-repairs file ownership during scan
- VFS getattr returns correct user uid/gid for all files

### Install
1. Download \`$DMG_NAME\`
2. Open DMG, drag DMSA.app to Applications
3. Copy Service/com.ttttt.dmsa.service to /Library/PrivilegedHelperTools/ (requires sudo)
4. Requires macFUSE 5.1.3+"

gh release create "$TAG" \
    "$DMG_PATH" \
    --repo "newstatic/DMSA" \
    --title "DMSA $VERSION" \
    --notes "$RELEASE_NOTES" \
    2>&1

if [ $? -ne 0 ]; then
    err "GitHub release creation failed"
fi

log "GitHub Release created"

# ─── Done ────────────────────────────────────────────────────────────
step "Release Complete"
echo ""
echo "  Tag:     $TAG"
echo "  DMG:     $DMG_PATH ($DMG_SIZE)"
echo "  GitHub:  https://github.com/newstatic/DMSA/releases/tag/$TAG"
echo ""
log "All done!"
