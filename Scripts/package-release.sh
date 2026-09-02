#!/bin/bash

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
PROJECT_DIR="$ROOT_DIR/ModernAppExtension"
if [[ -z "${DERIVED_DATA:-}" ]]; then
  DERIVED_DATA=$(mktemp -d "${TMPDIR:-/tmp}/GLTFQuickLookRelease.XXXXXX")
fi
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
VERSION="${VERSION:-1.1.0-beta.1}"
BUNDLE_VERSION="${BUNDLE_VERSION:-${VERSION%%-*}}"
ARCH="${ARCH:-arm64}"
ARTIFACT_NAME="GLTFQuickLook-${VERSION}-macos-${ARCH}"
TEMP_ARCHIVE="$DIST_DIR/.${ARTIFACT_NAME}.$$.zip"
TEMP_CHECKSUM="$DIST_DIR/.${ARTIFACT_NAME}.$$.zip.sha256"

command -v xcodegen >/dev/null || {
  echo "error: xcodegen is required (brew install xcodegen)" >&2
  exit 1
}

"$ROOT_DIR/Scripts/check-release-hygiene.sh"

mkdir -p "$DERIVED_DATA" "$DIST_DIR"

xcodegen generate --spec "$PROJECT_DIR/project.yml"

xcodebuild \
  -project "$PROJECT_DIR/GLTFQuickLook.xcodeproj" \
  -scheme GLTFQuickLook \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/GLTFQuickLook.app"
test -d "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

for bundle in \
  "$APP_PATH" \
  "$APP_PATH/Contents/PlugIns/GLTFPreview.appex" \
  "$APP_PATH/Contents/PlugIns/GLTFThumbnail.appex"; do
  actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$bundle/Contents/Info.plist")
  if [[ "$actual_version" != "$BUNDLE_VERSION" ]]; then
    echo "error: $bundle has version $actual_version, expected $BUNDLE_VERSION" >&2
    exit 1
  fi
done

for extension in \
  "$APP_PATH/Contents/PlugIns/GLTFPreview.appex" \
  "$APP_PATH/Contents/PlugIns/GLTFThumbnail.appex"; do
  entitlements=$(codesign -d --entitlements :- "$extension" 2>/dev/null)
  grep -q 'com.apple.security.app-sandbox' <<< "$entitlements"
  if grep -q 'com.apple.security.get-task-allow' <<< "$entitlements"; then
    echo "error: debug entitlement found in $extension" >&2
    exit 1
  fi
done

while IFS= read -r -d '' binary; do
  if strings "$binary" | grep -Eq '(/Users/|/Volumes/)'; then
    echo "error: build-machine path found in $binary" >&2
    exit 1
  fi
done < <(find "$APP_PATH" -type f -perm -111 -print0)

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl \
  "$APP_PATH" "$TEMP_ARCHIVE"

if unzip -Z1 "$TEMP_ARCHIVE" | grep -Eq '(^|/)(\.DS_Store|__MACOSX)(/|$)'; then
  echo "error: archive contains Finder metadata" >&2
  exit 1
fi

checksum=$(shasum -a 256 "$TEMP_ARCHIVE" | awk '{print $1}')
printf '%s  %s\n' "$checksum" "$ARTIFACT_NAME.zip" > "$TEMP_CHECKSUM"
mv -f "$TEMP_ARCHIVE" "$DIST_DIR/$ARTIFACT_NAME.zip"
mv -f "$TEMP_CHECKSUM" "$DIST_DIR/$ARTIFACT_NAME.zip.sha256"

echo "Created:"
echo "  $DIST_DIR/$ARTIFACT_NAME.zip"
echo "  $DIST_DIR/$ARTIFACT_NAME.zip.sha256"
