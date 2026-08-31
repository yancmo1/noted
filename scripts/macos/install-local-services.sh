#!/bin/zsh
set -euo pipefail

repo_path="/Users/yancyshepherd/Projects/noted"
launch_agents_path="/Users/yancyshepherd/Library/LaunchAgents"
log_path="/Users/yancyshepherd/Library/Logs/Noted"
user_id="$(/usr/bin/id -u)"

/bin/mkdir -p "$launch_agents_path" "$log_path"

for label in com.shepswork.noted.ollama com.shepswork.noted.local-api; do
  source_path="$repo_path/scripts/macos/launchd/$label.plist"
  destination_path="$launch_agents_path/$label.plist"

  if [[ ! -f "$source_path" ]]; then
    echo "Missing launch agent template: $source_path" >&2
    exit 1
  fi

  /bin/cp "$source_path" "$destination_path"
  /bin/launchctl bootout "gui/$user_id/$label" >/dev/null 2>&1 || true
  /bin/launchctl bootstrap "gui/$user_id" "$destination_path"
  /bin/launchctl kickstart -k "gui/$user_id/$label"
done

echo "Noted local services installed for user $user_id."
echo "Ollama: http://127.0.0.1:11434"
echo "Noted API: http://0.0.0.0:3333"
