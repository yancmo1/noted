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

echo "Xcode Cloud archive validation passed: Noted.app contains Noted Watch Spike.app."
