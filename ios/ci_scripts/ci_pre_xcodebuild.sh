#!/bin/sh
# Xcode Cloud: stamp the build number before xcodebuild runs, so every upload
# to App Store Connect has a higher CFBundleVersion than the last one.
#
# The build number is the project's CURRENT_PROJECT_VERSION plus Xcode Cloud's
# $CI_BUILD_NUMBER. Xcode Cloud counts from 1 while the hand-uploaded builds
# already reached 6 (V1.1), so the committed number is a floor: a cloud build
# is always above it, and always above the cloud build before it. Raising the
# committed number later is fine; lowering it is not.
#
# The marketing version (MARKETING_VERSION, "1.1") stays hand-edited in the
# project. Only this throwaway clone is changed; nothing is committed back.
#
# The project has no VERSIONING_SYSTEM and a generated Info.plist, so agvtool
# has nothing to edit; the build setting is rewritten directly.

set -eu

[ -n "${CI_BUILD_NUMBER:-}" ] || { echo "ci_pre_xcodebuild: no CI_BUILD_NUMBER, leaving the build number alone"; exit 0; }

PBXPROJ="$CI_PRIMARY_REPOSITORY_PATH/ios/CocoScout.xcodeproj/project.pbxproj"

FLOOR=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);.*/\1/p' "$PBXPROJ" | sort -n | tail -1)
[ -n "$FLOOR" ] || { echo "ci_pre_xcodebuild: no CURRENT_PROJECT_VERSION in $PBXPROJ"; exit 1; }

BUILD=$((FLOOR + CI_BUILD_NUMBER))

echo "ci_pre_xcodebuild: build number $BUILD (project $FLOOR + Xcode Cloud build $CI_BUILD_NUMBER)"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = $BUILD;/g" "$PBXPROJ"
grep -n "CURRENT_PROJECT_VERSION" "$PBXPROJ"
