# Noted

Noted is a recording-first personal memory system. Press record, talk naturally, and keep the original audio alongside a searchable transcript, useful memories, open loops, and source-backed answers. Notes, links, and files remain available as secondary capture paths.

The native iOS client lives in [`apps/ios`](apps/ios/README.md). It is a local-first capture and playback client for this same API, not a second backend. The iPhone preserves recordings on-device, queues uploads, and opens timestamped transcript and evidence citations in native playback.

## Run locally

```bash
cp .env.example .env
npm install
npm run dev
```

Open http://localhost:5173. The default local password is `memory`.

For demo data: `npm run seed`.

For long-recording chunking during local development, install `ffmpeg` and `ffprobe` (for example, `brew install ffmpeg` on macOS). The Docker API image includes them.

The sample configuration documents the private-network `ai-lab` transcription provider and a Groq-compatible reasoning provider. The API also supports the Mac-local Whisper provider and local Ollama reasoning. When no transcription provider is configured, audio remains safely available as `partial` until you add a transcript manually or configure one. Set `LLM_MODE=mock` for deterministic local tests. Legacy `AI_*` variables remain supported.

### Local-first transcription tracer

The Mac already has a local Whisper.cpp `large-v3-turbo` wrapper with Apple Metal acceleration. Run the same API with local transcription and deterministic local analysis using:

```bash
npm run dev:api:local-whisper
```

This keeps the existing Groq/ai-lab provider path unchanged for `npm run dev:api`. The iOS Debug configuration already targets the Mac API over its Tailscale address; after starting this command, record or upload from the Debug app and the API will persist the transcript returned by the Mac-local Whisper process. Timing and failure records are emitted through the API logger, and per-recording Whisper artifacts are kept under `LOCAL_WHISPER_OUTPUT_DIR`.

### Local reasoning with Ollama

Ollama can handle analysis on the Mac without sending the transcript to Groq. The first verified local model is `qwen3:8b`; it is used together with the Mac-local Whisper provider by:

```bash
npm run dev:api:local-qwen
```

This command keeps the complete recording path local: Whisper transcribes the audio, then Qwen produces the structured meeting analysis. Long transcripts are analyzed in bounded, timestamp-preserving windows and merged locally; the command also disables hidden reasoning and bounds each Qwen request to two minutes. The existing `dev:api:local` command remains available for the older `gpt-oss:20b` Ollama setup when that model is installed.

The Mac transcriber’s “Send transcript to Noted” sheet includes a “Use Local Mac” shortcut for `http://127.0.0.1:3333`. The existing Groq settings remain available through the normal `npm run dev:api` command.

### Hosted web using the Mac-local processor

The local API listens on all interfaces and is reachable over the Mac’s Tailscale address. For an HTTPS browser connection, expose only the API to your tailnet:

```bash
tailscale serve --bg --yes http://127.0.0.1:3333
```

Set `VITE_API_BASE_URL` to the HTTPS URL Tailscale prints when building the web app. The browser will then save recordings to the Mac API, where `npm run dev:api:local-qwen` runs local Whisper followed by Qwen. The API uses cross-origin credentials only for the HTTPS Tailscale route; it does not expose Ollama directly. Do not use Tailscale Funnel for this private workflow.

If the hosted Cloudflare route receives a recording instead, it now preserves the source and audio before Groq processing. A provider-size failure leaves the recording available for retry or local processing rather than deleting it.

To keep the MacBook local stack available after login or restart, install the user-level services once:

```bash
./scripts/macos/install-local-services.sh
```

This supervises Ollama on `127.0.0.1:11434` and the local Noted API on port `3333`; the iOS Debug configuration reaches that API through the MacBook’s Tailscale address. Whisper remains an on-demand local command used by Noted Transcriber for each job, so it does not need a permanent listener or network exposure.

## Cloudflare deployment target

The `cloudflare/` directory contains the separate Worker + D1 + R2 + Queues deployment target. It does not alter the local JSON/filesystem server or its recordings. Follow [`cloudflare/README.md`](cloudflare/README.md) only after creating the Cloudflare resources and verifying the migration/import plan; the iOS client keeps a local-server upload fallback during this transition.

The private hosted installation is available at `https://noted.shepswork.com`.

## Docker

```bash
cp .env.example .env
docker compose up -d --build
```

Open http://localhost:8080. Uploaded files and the JSON store live in the `memory_data` volume. The compose stack contains one API writer and the Nginx web service; processing jobs are scheduled inside the API so the JSON repository cannot split into competing in-memory writers.

## Useful commands

```bash
npm run typecheck
npm run lint
npm test
npm run build
```

## API

Public: `GET /api/health`, `GET /api/auth/status`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/settings/status`.

Authenticated capture: `POST /api/capture/note`, `/url`, `/file`, `/voice`.

Authenticated retrieval: `GET /api/today`, `/sources`, `/sources/:id`, `/recordings/:id`, `/recordings/:id/transcript`, `/memories`, `/entities`, `/open-loops`, `/search?q=...`, `POST /api/ask`, and `GET /api/export`.

Authenticated correction: `PATCH /api/sources/:id`, `PATCH /api/recordings/:id/transcript`, `POST /api/sources/:id/reprocess`, `PATCH /api/memories/:id`, `PATCH /api/open-loops/:id`, and `DELETE /api/sources/:id`.

Native voice uploads may include `clientRecordingId` and `client=native`; retries are idempotent and return the existing Source instead of creating a duplicate.

The native client stores a draft manifest and audio in iOS Application Support before recording starts. It can open Meetings and Record while offline, then retries queued uploads when the app becomes active or connectivity returns.

## Data and backups

The default data directory is `./storage`. Back up `storage/memory-garden.json` and `storage/uploads/` together. JSON export is available from Settings or `GET /api/export`.

Read `PRODUCT.md`, `docs/CURRENT_PRODUCT.md`, `docs/ARCHITECTURE.md`, `docs/WORKFLOWS.md`, `docs/ROADMAP.md`, `docs/DECISIONS.md`, and `docs/KNOWN_LIMITATIONS.md` for current product and implementation details. Earlier Memory Garden and Pocket PRDs are retained under `docs/archive/` as historical reference only.
