# Noted architecture

Noted is a recording-first, single-user TypeScript application with a React/Vite frontend and Fastify API. Every capture is persisted before interpretation. Voice captures preserve the original audio, recording metadata, transcript segments, and derived memories as separate layers so a missing provider never destroys the source.

## Runtime pieces

- `apps/web`: responsive React UI. It talks to the REST API and never owns source data.
- `apps/ios`: SwiftUI native capture client. It owns local audio durability, Keychain auth, upload retry state, playback, and mobile browsing; it does not contain AI provider credentials or processing logic.
- `apps/api/src/app.ts` and `apps/api/src/server.ts`: authenticated REST API factory and small process entry point for login, recording/capture, transcript correction, browsing, search, Ask, source detail, retry, export, and deletion.
- `apps/api/src/jobs.ts` and `apps/api/src/processor.ts`: one-writer persisted scheduler and processing pipeline. Jobs recover stale leases, retry with bounded attempts, preserve transcripts on analysis failure, and write evidence-linked memories plus the optional meeting brief.
- `apps/api/src/db.ts`: storage repository. The default backend is an atomic JSON document in `storage/memory-garden.json`, with `storage/uploads/` for private audio and files. The narrow repository interface is ready for a PostgreSQL/Drizzle adapter later.

## Voice data model

The lifecycle is deliberately explicit:

`RecordingSession` → `Source` audio → `TranscriptSegment[]` → derived memories/entities/open loops.

The source owns processing status and the session owns recording status. Transcript segments carry stable IDs and millisecond offsets. Derived records carry `EvidenceRef` values pointing back to segment IDs, offsets, and short quotes, which lets the UI seek the audio and show why a memory or answer exists.

Conversation and meeting modes require an explicit consent acknowledgement in the web UI and API. The browser recorder releases microphone tracks after stop, pause, or failure. The API serves uploaded audio only through the authenticated `/files/:sourceId` route and supports byte ranges for seeking.

Native uploads include a durable client recording UUID in multipart form data. The API stores it in source metadata and returns the existing Source when the same UUID is retried, preventing duplicate backend records.
- `storage/uploads`: private uploaded files; they are only served through an authenticated source route.

The Noted iOS client stores relative audio filenames and a versioned manifest in the existing Application Support/MemoryGarden location, with an atomic primary index and last-known-good backup. Keeping that location preserves recordings across the product rename. Launch reconciliation keeps missing metadata visible and imports UUID-named orphan audio as recovered recordings.

Meeting-mode Sources optionally carry `meetingBrief` with summary, key points, decisions, action items, follow-ups, unresolved questions, confidence, claim state, and transcript evidence. Legacy Memories/Open Loops remain as a compatibility projection for the web client.

## Retrieval and provenance

The MVP uses hybrid-style local keyword scoring over transcript text, memory content, summaries, and source titles. Each result carries its `sourceId`; Ask returns citations with segment offsets and quotes that open the source drawer and can seek the audio. Segment timestamps are the initial citation contract. Word timestamps are persisted on each transcript segment for future transcript-following and word-level search, but are not yet used by the UI.

The reasoning and transcription provider configurations are independent. `LLM_*` controls analysis and Ask; `TRANSCRIPTION_*` controls speech-to-text. The default transcription endpoint is Groq’s OpenAI-compatible API with `whisper-large-v3-turbo`, but the pipeline only depends on the `TranscriptionProvider` interface, so a local Whisper implementation can replace it later.

Long recordings are measured against `TRANSCRIPTION_MAX_MB` and `TRANSCRIPTION_CHUNK_SECONDS`. When either limit is exceeded, the API uses ffprobe to determine duration, ffmpeg to create bounded WebM chunks, transcribes each chunk, offsets segment and word timestamps to the original recording timeline, then merges the results. Temporary chunks are deleted after processing. Each merged segment retains `chunkIndex` and `chunkStartMs` provenance.

## Temporal behavior

Decision memories from newer captures can mark older same-project decisions with `supersededBy`. Older sources are retained and shown as potentially outdated, so history remains inspectable.

Reprocessing clears only derived records for the source, then rebuilds them from the preserved transcript/audio. A manually corrected transcript is therefore the durable input for the next pass. Processing runs in the API process; `apps/api/src/worker.ts` is a deprecated guard and is not part of Compose.

## Security boundary

The initial account is a single local password configured by `AUTH_PASSWORD`. A secure, HttpOnly session cookie gates all non-public routes. This is designed for a self-hosted personal deployment; a production internet-facing deployment should place it behind TLS and a stronger identity layer.
