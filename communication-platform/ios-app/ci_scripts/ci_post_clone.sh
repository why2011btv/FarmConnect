#!/bin/sh
#
# Sets CFBundleVersion for the App Store build.
#
# Info.plist maps CFBundleVersion to $(CURRENT_PROJECT_VERSION), so this build setting is what
# reaches App Store Connect. App Store Connect rejects any build whose number is not strictly
# higher than every build already uploaded for this version -- that rejection surfaces as
# "Preparing build for App Store Connect failed".
#
# The number is therefore the MAXIMUM of two sources:
#
#   * the value checked into project.yml -- authoritative, bumped by hand per release, and the
#     only thing that applies if this script does not run for any reason.
#   * CI_BUILD_NUMBER -- the Xcode Cloud run counter, which only ever increases.
#
# Taking the max matters: run counters and the checked-in value drift independently, and letting
# either one alone win would eventually lower the number and fail the upload again.

set -eu

PROJECT="$CI_PRIMARY_REPOSITORY_PATH/communication-platform/ios-app/FarmConnect.xcodeproj/project.pbxproj"

if [ ! -f "$PROJECT" ]; then
  echo "error: project not found at $PROJECT" >&2
  exit 1
fi

CURRENT=$(sed -n -E 's/.*CURRENT_PROJECT_VERSION = ([0-9]+);.*/\1/p' "$PROJECT" | head -1)
: "${CURRENT:=0}"
CI="${CI_BUILD_NUMBER:-0}"

# Guard against a non-numeric CI_BUILD_NUMBER rather than trusting it blindly.
case "$CI" in
  ''|*[!0-9]*) CI=0 ;;
esac

if [ "$CI" -gt "$CURRENT" ]; then
  NEXT="$CI"
else
  NEXT="$CURRENT"
fi

echo "checked-in build number: $CURRENT / CI_BUILD_NUMBER: $CI -> using $NEXT"

sed -i '' -E "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $NEXT;/g" "$PROJECT"
grep -n "CURRENT_PROJECT_VERSION" "$PROJECT"
