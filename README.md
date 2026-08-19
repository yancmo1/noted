# Memory Garden

Memory Garden is a recording-first personal memory system. Press record, talk naturally, and keep the original audio alongside a searchable transcript, useful memories, open loops, and source-backed answers. Notes, links, and files remain available as secondary capture paths.

The native iOS client lives in [`apps/ios`](</Users/yancyshepherd/Desktop/AUTONOMOUS_AGENT/apps/ios/README.md>). It is a local-first capture and playback client for this same API—not a second backend. The iPhone preserves recordings on-device, queues uploads, and opens timestamped transcript/evidence citations in native playback.

## Run locally

```bash
cp .env.example .env
npm install
npm run dev
```

Open http://localhost:5173. The default local password is `memory`.

For a demo garden: `npm run seed`.

For long-recording chunking during local development, install `ffmpeg` and `ffprobe` (for example, `brew install ffmpeg` on macOS). The Docker API image includes them.

The default reasoning mode is deterministic mock AI, so no LLM key is required. A browser recording is always saved first. Transcription is configured independently: Groq is the default provider abstraction and uses `whisper-large-v3-turbo` when `TRANSCRIPTION_MODE=real` and `TRANSCRIPTION_API_KEY` is set. When no transcription provider is configured, audio remains safely available as `partial` until you add a transcript manually or configure one. Set `LLM_MODE`, `LLM_BASE_URL`, `LLM_API_KEY`, and `LLM_MODEL` for reasoning, and `TRANSCRIPTION_BASE_URL`, `TRANSCRIPTION_API_KEY`, `TRANSCRIPTION_MODEL`, `TRANSCRIPTION_MAX_MB`, or `TRANSCRIPTION_CHUNK_SECONDS` for speech-to-text. Legacy `AI_*` variables remain supported.

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

See `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`, and `docs/KNOWN_LIMITATIONS.md` for implementation details and tradeoffs. The pivot requirements are captured in `outputs/PIVOT_PRD_POCKET_APP.md`.
