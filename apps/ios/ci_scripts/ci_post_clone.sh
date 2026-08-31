#!/bin/zsh
set -euo pipefail

repository_path="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "${0:A:h}/../../.." && pwd)}"
ios_path="$repository_path/apps/ios"
project_path="$ios_path/Noted.xcodeproj"

if [[ ! -d "$project_path" ]]; then
  echo "error: checked-in Noted.xcodeproj was not found at $project_path" >&2
  exit 1
fi

if [[ ! -f "$ios_path/Noted.xcodeproj/xcshareddata/xcschemes/Noted.xcscheme" ]]; then
  echo "error: shared Noted scheme is missing" >&2
  exit 1
fi

if [[ ! -f "$ios_path/Noted.xcodeproj/xcshareddata/xcschemes/Noted Watch Spike.xcscheme" ]]; then
  echo "error: shared Noted Watch Spike scheme is missing" >&2
  exit 1
fi

project_list="$(mktemp)"
trap 'rm -f "$project_list"' EXIT
xcodebuild -project "$project_path" -list > "$project_list"

if ! grep -Eq '[[:space:]]Noted$' "$project_list"; then
  echo "error: Noted target or scheme is missing from the checked-in project" >&2
  exit 1
fi

if ! grep -Eq '[[:space:]]Noted Watch Spike$' "$project_list"; then
  echo "error: Noted Watch Spike target or scheme is missing from the checked-in project" >&2
  exit 1
fi

echo "Xcode Cloud post-clone validation passed for the checked-in iOS + Watch project."
