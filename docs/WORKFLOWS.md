# Noted workflows

This document describes the current end-to-end workflows. It is a reference for implementation and troubleshooting, not a feature backlog.

## Web capture

The React client sends notes, URLs, files, and voice recordings to the authenticated Fastify API. The API stores the source before it starts transcription or analysis. Source detail shows processing status, audio, transcript segments, derived memories, open loops, and retry actions.

Voice sources keep their original audio behind the authenticated `/files/:id` route. Transcript segments carry millisecond offsets. The client uses those offsets to seek playback from transcript and evidence controls.

## iOS capture

The iOS app writes a local recording manifest before microphone capture starts. It keeps audio in Application Support, preserves it after upload, and reconciles interrupted or orphaned files on launch.

Uploads use the local recording UUID as `clientRecordingId`. The client checks the API for that ID before retrying an ambiguous upload. The API returns the existing source instead of creating a duplicate.

The iOS app can capture without a network connection. It queues local work and retries when the app becomes active or connectivity returns.

## macOS transcription

Noted Transcriber imports or receives an audio or video file. The local Whisper wrapper extracts the transcript and timestamped segments. The user reviews the transcript before sending it.

The Mac sends transcript text and segments to `/api/recordings/local-transcript`. It does not need to expose a public listener, and the local-first flow does not send the original recording to Cloudflare.

## API processing

The API creates a persisted processing job after capture. The scheduler claims one job at a time, recovers stale leases, retries bounded failures, and writes processing results through the single API writer.

Transcription and reasoning are separate stages. A usable transcript remains available when analysis fails. The source becomes `partial` when processing completes with a recoverable gap.

The processor stores transcript segments separately from derived records. It maps model evidence hints to stored segment IDs and offsets before saving claims.

## Local providers

`npm run dev:api` uses the repository's `.env` configuration. `npm run dev:api:local-whisper` selects the Mac-local Whisper provider and deterministic analysis. `npm run dev:api:local-qwen` selects Mac-local Whisper and Qwen through Ollama.

The sample `.env.example` documents the provider variables. Never copy secret values into documentation or commit `.env`.

## Cloudflare processing

The Cloudflare Worker stores metadata in D1, original audio in private R2, and processing work in Queues. The local API remains the local development path.

The Mac transcript handoff can send reviewed text and timestamped segments to the hosted route. The Worker stores no R2 object for that text-only handoff and queues the existing analysis flow.

Cloudflare Workers cannot run the local `ffprobe` and `ffmpeg` subprocess flow. Large-recording chunking therefore needs a separate design before the hosted path replaces the local path for those recordings.

## Action items and calendar

The analysis provider returns action items with confidence, claim state, optional inferred owner and due date, and evidence hints. The API resolves evidence against stored transcript segments and projects action items into the existing task Memory and Open Loop records.

The API extracts calendar candidates from transcript dates and times. Candidates include evidence and a confirmation flag. The iOS client asks for Calendar access and creates an event only after the user confirms the candidate and chooses a writable calendar.
