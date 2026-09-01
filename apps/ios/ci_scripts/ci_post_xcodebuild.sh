#!/bin/zsh
set -euo pipefail

if [[ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]]; then
  echo "Xcode Cloud post-build archive check skipped outside Xcode Cloud."
  exit 0
fi

if [[ "${CI_XCODEBUILD_ACTION:-unknown}" != "archive" || "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]]; then
  exit 0
fi

archive_path="${CI_ARCHIVE_PATH:-}"
if [[ -z "$archive_path" ]]; then
  echo "Xcode Cloud archive completed; CI_ARCHIVE_PATH was not provided, so embedded Watch validation was deferred to the archive artifact."
  exit 0
fi

ios_app="$archive_path/Products/Applications/Noted.app"
watch_app="$ios_app/Watch/Noted Watch Spike.app"

if [[ ! -d "$ios_app" ]]; then
  echo "error: Cloud archive does not contain Noted.app at $ios_app" >&2
  exit 1
fi

if [[ ! -d "$watch_app" ]]; then
  echo "error: Cloud archive does not contain the embedded Noted Watch Spike.app" >&2
  exit 1
fi

ios_marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ios_app/Info.plist")
watch_marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$watch_app/Info.plist")
ios_build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ios_app/Info.plist")
watch_build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$watch_app/Info.plist")

if [[ "$ios_marketing_version" != "$watch_marketing_version" ]]; then
  echo "error: iOS marketing version $ios_marketing_version does not match embedded Watch marketing version $watch_marketing_version." >&2
  exit 1
fi

if [[ "$ios_build_number" != "$watch_build_number" ]]; then
  echo "error: iOS build $ios_build_number does not match embedded Watch build $watch_build_number." >&2
  exit 1
fi

echo "Xcode Cloud archive validation passed: Noted.app contains Noted Watch Spike.app."
echo "Xcode Cloud archive validation passed: iPhone and Watch marketing/build versions match ($ios_marketing_version/$ios_build_number)."
