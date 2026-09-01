#!/bin/bash
# Fetches the CLIProxyAPI backend binary from https://github.com/router-for-me/CLIProxyAPI
# into src/Sources/Resources/cli-proxy-api-plus.
#
# Usage:
#   ./scripts/update-backend.sh            # fetch the pinned version (used by builds)
#   ./scripts/update-backend.sh latest     # fetch the latest release
#   ./scripts/update-backend.sh v7.2.147   # fetch a specific tag
#
# The binary is NOT committed to the repo (GitHub warns past 50 MB); it is
# fetched automatically by create-app-bundle.sh on first build.

set -euo pipefail

# Version this fork was last tested against. Bump when updating deliberately.
PINNED_VERSION="v7.2.146"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$PROJECT_DIR/src/Sources/Resources/cli-proxy-api-plus"
REQUEST="${1:-$PINNED_VERSION}"

REPO="router-for-me/CLIProxyAPI"

# Release assets use Go-style platform naming.
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64)  PLATFORM="darwin_aarch64" ;;
    Darwin/*)      PLATFORM="darwin_amd64" ;;
    Linux/arm64)   PLATFORM="linux_aarch64" ;;
    Linux/*)       PLATFORM="linux_amd64" ;;
    *)             PLATFORM="" ;;
esac

# Prefer authenticated gh (avoids API rate limits); fall back to curl.
gh_api() {
    if command -v gh >/dev/null 2>&1; then
        gh api "$1"
    else
        curl -fsSL "https://api.github.com/$1"
    fi
}

if [ "$REQUEST" = "latest" ]; then
    echo "Resolving latest release from $REPO..."
    TAG=$(RELEASE_JSON="$(gh_api "repos/$REPO/releases/latest")" python3 <<'PY'
import json, os
print(json.loads(os.environ["RELEASE_JSON"])["tag_name"])
PY
)
else
    TAG="$REQUEST"
fi
echo "Fetching release $TAG from $REPO..."

ASSET_URL=$(RELEASE_JSON="$(gh_api "repos/$REPO/releases/tags/$TAG")" PLATFORM="$PLATFORM" python3 <<'PY'
import json, os, sys
release = json.loads(os.environ["RELEASE_JSON"])
platform = os.environ["PLATFORM"]
assets = release.get("assets", [])
# Exact platform asset first (e.g. CLIProxyAPI_7.2.146_darwin_aarch64.tar.gz),
# then any archive for the same OS/arch family.
exact = [a for a in assets if platform and platform in a["name"]]
arch_names = {
    "darwin_aarch64": ["darwin_aarch64", "darwin_arm64"],
    "darwin_amd64": ["darwin_amd64", "darwin_x86_64"],
    "linux_aarch64": ["linux_aarch64", "linux_arm64"],
    "linux_amd64": ["linux_amd64", "linux_x86_64"],
}
family = platform.split("_")[0] if platform else ""
loose = [a for a in assets if a["name"].endswith((".tar.gz", ".tgz", ".zip")) and any(k in a["name"] for k in arch_names.get(platform, [family]))]
pool = exact or loose
if not pool:
    names = [a["name"] for a in assets]
    sys.exit("No asset found for platform %s. Available: %s" % (platform, names))
print(pool[0]["browser_download_url"])
PY
)

echo "Downloading: $ASSET_URL"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
ARCHIVE="$TMP_DIR/backend-archive"
curl -fSL "$ASSET_URL" -o "$ARCHIVE"

echo "Extracting..."
case "$ASSET_URL" in
    *.tar.gz|*.tgz) tar -xzf "$ARCHIVE" -C "$TMP_DIR" ;;
    *.zip)          unzip -o -q "$ARCHIVE" -d "$TMP_DIR" ;;
    *)              echo "Unknown archive format: $ASSET_URL" >&2; exit 1 ;;
esac

BINARY=$(find "$TMP_DIR" -type f -name "cli-proxy-api*" -perm +111 2>/dev/null | head -1)
[ -z "$BINARY" ] && BINARY=$(find "$TMP_DIR" -type f -name "cli-proxy-api*" | head -1)
if [ -z "$BINARY" ]; then
    echo "Could not find the cli-proxy-api binary in the archive" >&2
    exit 1
fi

cp "$BINARY" "$DEST"
chmod +x "$DEST"
xattr -cr "$DEST" 2>/dev/null || true

echo "Backend installed: $TAG"
"$DEST" --version 2>/dev/null | head -1 || true
