#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${TMPDIR:-/tmp}/momiji-derived-data"
PACKAGE_CACHE="${TMPDIR:-/tmp}/momiji-package-cache"
SOURCE_PACKAGES="${TMPDIR:-/tmp}/momiji-source-packages"

cd "$PROJECT_ROOT"

env \
  CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/momiji-clang-cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/momiji-swiftpm-cache" \
  swift test --disable-sandbox

xcodebuild \
  -project Momiji.xcodeproj \
  -scheme Momiji \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES" \
  -packageCachePath "$PACKAGE_CACHE" \
  -disablePackageRepositoryCache \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
