#!/bin/zsh
set -euo pipefail

repo_path="/Users/yancyshepherd/Library/CloudStorage/GoogleDrive-yancmo@gmail.com/My Drive/00 - Coding Projects/noted"
ollama_health_url="http://127.0.0.1:11434/api/version"
node_path="/opt/homebrew/bin/node"

if [[ ! -x "$node_path" ]]; then
  echo "Node.js was not found at $node_path" >&2
  exit 69
fi

for _ in {1..60}; do
  if /usr/bin/curl -fsS --max-time 3 "$ollama_health_url" >/dev/null 2>&1; then
    cd "$repo_path"
    exec env \
      TRANSCRIPTION_PROVIDER=local-whisper \
      TRANSCRIPTION_MODE=real \
      LLM_MODE=real \
      LLM_BASE_URL=http://127.0.0.1:11434/v1 \
      LLM_API_KEY=ollama \
      LLM_MODEL=qwen3:8b \
      LLM_REASONING_EFFORT=none \
      LLM_ANALYSIS_CHUNK_CHARS=2400 \
      LLM_ANALYSIS_TIMEOUT_MS=120000 \
      "$node_path" --env-file-if-exists=.env --import tsx apps/api/src/server.ts
  fi
  /bin/sleep 2
done

echo "Ollama did not become ready within 120 seconds; local Noted API was not started." >&2
exit 75
