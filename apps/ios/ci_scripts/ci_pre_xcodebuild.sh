#!/bin/zsh
set -euo pipefail

if [[ "${CI_XCODE_CLOUD:-FALSE}" != "TRUE" ]]; then
  echo "Xcode Cloud pre-build guard skipped outside Xcode Cloud."
  exit 0
fi

xcode_version="$(xcodebuild -version)"
xcode_developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
echo "$xcode_version"
echo "Developer directory: $xcode_developer_dir"

if [[ "$xcode_version $xcode_developer_dir" == *beta* || "$xcode_version $xcode_developer_dir" == *Beta* || "$xcode_version $xcode_developer_dir" == *BETA* ]]; then
  echo "error: this workflow requires a stable, non-beta Xcode runner; select the latest non-beta Xcode version in Xcode Cloud." >&2
  exit 1
fi

action="${CI_XCODEBUILD_ACTION:-unknown}"
scheme="${CI_XCODE_SCHEME:-unknown}"
build_number="${CI_BUILD_NUMBER:-unknown}"
echo "Xcode Cloud action=$action scheme=$scheme buildNumber=$build_number"

if [[ "$action" == "archive" && "$scheme" != "unknown" && "$scheme" != "Noted" ]]; then
  echo "error: TestFlight archives must use the Noted scheme so the Watch app is embedded in the iOS app." >&2
  exit 1
fi
