#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
ARCHIVE_PATH="$DIST_DIR/Momiji.xcarchive"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/momiji-release.XXXXXX")"
DERIVED_DATA="${TMPDIR:-/tmp}/momiji-release-derived"
PACKAGE_CACHE="${TMPDIR:-/tmp}/momiji-release-package-cache"
SOURCE_PACKAGES="${TMPDIR:-/tmp}/momiji-release-source-packages"
MOMIJI_BUNDLE_PREFIX="${MOMIJI_BUNDLE_PREFIX:-app.momiji}"
MOMIJI_RELEASE_MODE="${MOMIJI_RELEASE_MODE:-developer-id}"

case "$MOMIJI_RELEASE_MODE" in
  developer-id)
    : "${MOMIJI_TEAM_ID:?Set MOMIJI_TEAM_ID to your Developer ID team identifier}"
    : "${MOMIJI_NOTARY_PROFILE:?Set MOMIJI_NOTARY_PROFILE to an xcrun notarytool Keychain profile}"
    SIGNING_ARGUMENTS=(
      DEVELOPMENT_TEAM="$MOMIJI_TEAM_ID"
      CODE_SIGN_STYLE=Manual
      CODE_SIGN_IDENTITY="Developer ID Application"
    )
    ;;
  adhoc)
    SIGNING_ARGUMENTS=(CODE_SIGNING_ALLOWED=NO)
    ;;
  *)
    echo "Unsupported MOMIJI_RELEASE_MODE: $MOMIJI_RELEASE_MODE" >&2
    echo "Use developer-id or adhoc." >&2
    exit 2
    ;;
esac

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$DIST_DIR"
rm -rf "$ARCHIVE_PATH"

xcodebuild archive \
  -project "$PROJECT_ROOT/Momiji.xcodeproj" \
  -scheme Momiji \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -packageCachePath "$PACKAGE_CACHE" \
  -disablePackageRepositoryCache \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  MOMIJI_BUNDLE_PREFIX="$MOMIJI_BUNDLE_PREFIX" \
  "${SIGNING_ARGUMENTS[@]}"

APP_PATH="$ARCHIVE_PATH/Products/Applications/Momiji.app"
test -d "$APP_PATH"
HELPER_PATH="$APP_PATH/Contents/Library/LoginItems/MomijiHelper.app"
test -d "$HELPER_PATH"

for executable in \
  "$APP_PATH/Contents/MacOS/Momiji" \
  "$HELPER_PATH/Contents/MacOS/MomijiHelper"; do
  architectures="$(lipo -archs "$executable")"
  if [[ "$architectures" != "x86_64 arm64" && "$architectures" != "arm64 x86_64" ]]; then
    echo "Expected a Universal binary, got '$architectures': $executable" >&2
    exit 1
  fi
done

if [[ "$MOMIJI_RELEASE_MODE" == "adhoc" ]]; then
  codesign --force --sign - --options runtime --timestamp=none "$HELPER_PATH"
  codesign --force --sign - --options runtime --timestamp=none "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ARTIFACT_BASENAME="Momiji-$VERSION-macOS-Universal"
DMG_PATH="$DIST_DIR/$ARTIFACT_BASENAME.dmg"
ZIP_PATH="$DIST_DIR/$ARTIFACT_BASENAME.zip"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"

rm -f "$DMG_PATH" "$ZIP_PATH" "$CHECKSUM_PATH"

ditto "$APP_PATH" "$STAGING_DIR/Momiji.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname Momiji -srcfolder "$STAGING_DIR" -format UDZO -ov "$DMG_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "$MOMIJI_RELEASE_MODE" == "developer-id" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$MOMIJI_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
else
  echo "Warning: created an ad-hoc signed, unnotarized release package." >&2
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")"
) > "$CHECKSUM_PATH"

echo "Created:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $CHECKSUM_PATH"
