#!/bin/sh
# Xcode Cloud: stamp the build number with $CI_BUILD_NUMBER before xcodebuild
# runs, so the archive carries the number Xcode Cloud uploads it under.
#
# Xcode Cloud sets CFBundleVersion to its own build counter when it uploads to
# App Store Connect, whatever the project says (its first upload was 1.1 (3),
# though hand uploads had reached 6). Build numbers only need to be unique per
# version, and the counter only rises. Stamping the same number here keeps
# the app's user agent ("CocoScout/1.2 (7; nav 2)") in step with App Store
# Connect. The server reads only the nav generation, never the build.
#
# The marketing version (MARKETING_VERSION) stays hand-edited in the project.
# Only this throwaway clone is changed; nothing is committed back. The project
# has no VERSIONING_SYSTEM and a generated Info.plist, so agvtool has nothing
# to edit; the build setting is rewritten directly.

set -eu

[ -n "${CI_BUILD_NUMBER:-}" ] || { echo "ci_pre_xcodebuild: no CI_BUILD_NUMBER, leaving the build number alone"; exit 0; }

PBXPROJ="$CI_PRIMARY_REPOSITORY_PATH/ios/CocoScout.xcodeproj/project.pbxproj"

echo "ci_pre_xcodebuild: build number $CI_BUILD_NUMBER"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" "$PBXPROJ"
grep -n "CURRENT_PROJECT_VERSION" "$PBXPROJ"
