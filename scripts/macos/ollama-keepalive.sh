#!/bin/zsh
set -euo pipefail

# Ollama's desktop app may already own this listener. In that case, keep this
# supervisor idle. If the app is not running after login or restart, start the
# command-line service so the local Noted API can still use Ollama.
health_url="http://127.0.0.1:11434/api/version"
ollama_binary=""
for candidate in /usr/local/bin/ollama /opt/homebrew/bin/ollama; do
  if [[ -x "$candidate" ]]; then
    ollama_binary="$candidate"
    break
  fi
done

if [[ -z "$ollama_binary" ]]; then
  echo "Ollama was not found in /usr/local/bin or /opt/homebrew/bin" >&2
  exit 69
fi

while true; do
  if /usr/bin/curl -fsS --max-time 3 "$health_url" >/dev/null 2>&1; then
    /bin/sleep 30
    continue
  fi

  exec "$ollama_binary" serve
done
