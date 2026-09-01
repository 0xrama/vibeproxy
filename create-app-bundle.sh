#!/bin/bash

set -e

echo "📦 Creating .app bundle..."

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$PROJECT_DIR/src"
APP_NAME="VibeProxy"
BUILD_DIR="$SRC_DIR/.build/release"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"

# Build the Swift executable first
echo -e "${BLUE}Building Swift executable (release)...${NC}"
cd "$SRC_DIR"
if [ -n "$TARGET_ARCH" ]; then
    echo "Building for architecture: $TARGET_ARCH"
    swift build -c release --arch "$TARGET_ARCH"
else
    swift build -c release
fi
cd "$PROJECT_DIR"
echo -e "${GREEN}✅ Build complete${NC}"

# The backend binary is fetched at build time (not committed to the repo)
if [ ! -f "$SRC_DIR/Sources/Resources/cli-proxy-api-plus" ]; then
    echo -e "${BLUE}Backend binary missing — fetching pinned CLIProxyAPI release (see scripts/update-backend.sh)…${NC}"
    "$PROJECT_DIR/scripts/update-backend.sh"
fi

# Create .app structure
echo -e "${BLUE}Creating .app bundle structure...${NC}"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
echo -e "${BLUE}Copying executable...${NC}"
cp "$BUILD_DIR/CLIProxyMenuBar" "$APP_DIR/Contents/MacOS/"
chmod +x "$APP_DIR/Contents/MacOS/CLIProxyMenuBar"

# Copy resources (copy contents, not the folder itself)
echo -e "${BLUE}Copying resources...${NC}"
echo "Resources to copy:"
ls -lh "$SRC_DIR/Sources/Resources/"

if [ -d "$SRC_DIR/Sources/Resources" ]; then
    for item in "$SRC_DIR/Sources/Resources/"*; do
        if [ -e "$item" ]; then
            if [[ "$item" != *.swift ]]; then
                cp -r "$item" "$APP_DIR/Contents/Resources/"
            fi
        fi
    done
fi

echo "Checking bundled resources:"
ls -lh "$APP_DIR/Contents/Resources/"

if [ ! -f "$APP_DIR/Contents/Resources/cli-proxy-api-plus" ]; then
    echo -e "${YELLOW}⚠️ WARNING: cli-proxy-api-plus binary not found in bundle!${NC}"
    find "$SRC_DIR/Sources/Resources" -name "cli-proxy-api-plus" -ls
    exit 1
fi
echo -e "${GREEN}✅ cli-proxy-api-plus bundled: $(ls -lh "$APP_DIR/Contents/Resources/cli-proxy-api-plus" | awk '{print $5}')${NC}"

# Copy Info.plist and inject version
echo -e "${BLUE}Copying Info.plist...${NC}"
cp "$SRC_DIR/Info.plist" "$APP_DIR/Contents/"

VERSION="${APP_VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
    VERSION="${VERSION#v}"
fi

BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo "1")

echo -e "${BLUE}Setting version to: ${VERSION} (build ${BUILD_NUMBER})${NC}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$APP_DIR/Contents/Info.plist"

# Create PkgInfo
echo -e "${BLUE}Creating PkgInfo...${NC}"
echo -n "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Sign the app with Developer ID if available, otherwise ad-hoc
echo -e "${BLUE}Signing app...${NC}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$CODESIGN_IDENTITY" ]; then
    CODESIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
fi

if [ -n "$CODESIGN_IDENTITY" ]; then
    echo -e "${GREEN}Signing with: $CODESIGN_IDENTITY${NC}"

    xattr -cr "$APP_DIR"
    codesign --remove-signature "$APP_DIR/Contents/MacOS/CLIProxyMenuBar" 2>/dev/null || true

    # Sign the cli-proxy-api-plus binary (required for notarization)
    if [ -f "$APP_DIR/Contents/Resources/cli-proxy-api-plus" ]; then
        echo -e "${BLUE}Signing cli-proxy-api-plus binary...${NC}"
        if [ -f "$PROJECT_DIR/entitlements.plist" ]; then
            codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
                --entitlements "$PROJECT_DIR/entitlements.plist" \
                "$APP_DIR/Contents/Resources/cli-proxy-api-plus"
        else
            codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp \
                "$APP_DIR/Contents/Resources/cli-proxy-api-plus"
        fi
        echo -e "${GREEN}✅ cli-proxy-api-plus signed${NC}"
    fi

    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$APP_DIR/Contents/MacOS/CLIProxyMenuBar"
    codesign --force --sign "$CODESIGN_IDENTITY" --options runtime --timestamp "$APP_DIR"

    echo -e "${GREEN}✅ Code signed successfully${NC}"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR" && echo -e "${GREEN}✅ Signature verified${NC}"
else
    echo -e "${YELLOW}⚠️ No Developer ID found, using ad-hoc signature${NC}"
    codesign --force --deep --sign - "$APP_DIR"
fi

echo -e "${GREEN}✅ App bundle created successfully!${NC}"
echo ""
echo -e "${GREEN}Location: $APP_DIR${NC}"
echo ""
echo "To install:"
echo "  1. Drag '$APP_NAME.app' to /Applications"
echo "  2. Double-click to launch"
echo ""
echo "To allow opening (if macOS blocks it):"
echo "  Right-click > Open, then click 'Open' in the dialog"
