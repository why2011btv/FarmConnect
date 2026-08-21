#!/bin/sh
#
# Stamps the Xcode Cloud run number into the project as CFBundleVersion.
#
# Info.plist sets CFBundleVersion to $(CURRENT_PROJECT_VERSION), so that build setting is what
# reaches App Store Connect. Setting it to "$(CI_BUILD_NUMBER)" directly in the project does NOT
# work: build settings only expand variables Xcode knows about, and CI_BUILD_NUMBER is an
# environment variable exported to these scripts, not a build setting. Left that way, the literal
# text "$(CI_BUILD_NUMBER)" ends up as the version and "Prepare Build for App Store Connect"
# fails. Rewriting the project here happens before the build, so xcodebuild sees a real number.
#
# Run numbers only ever increase, which is exactly the property App Store Connect requires of
# CFBundleVersion.

set -eu

PROJECT="$CI_PRIMARY_REPOSITORY_PATH/communication-platform/ios-app/FarmConnect.xcodeproj/project.pbxproj"

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  echo "CI_BUILD_NUMBER is not set; leaving the checked-in build number alone."
  exit 0
fi

if [ ! -f "$PROJECT" ]; then
  echo "error: project not found at $PROJECT" >&2
  exit 1
fi

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/g" "$PROJECT"

echo "Set CURRENT_PROJECT_VERSION to $CI_BUILD_NUMBER:"
grep -n "CURRENT_PROJECT_VERSION" "$PROJECT"
