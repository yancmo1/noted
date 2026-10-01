# Current Noted product

This is the current product brief for Noted. `PRODUCT.md` remains the stable product contract. This document records the implementation scope that agents should assume today.

## Product

Noted is a private, recording-first memory system. The user captures a meeting, conversation, thought, note, link, or file. Noted preserves the source, produces a reviewable transcript when configured, and derives source-linked information from it.

Original audio stays available. AI output remains derived and traceable. A provider failure changes processing status; it does not erase the source.

## Current platforms

- The web client supports recording, notes, links, files, source browsing, search, Ask, playback, transcript review, memories, and open loops.
- The iOS client records locally, stores a durable manifest and audio in Application Support, retries uploads by client recording ID, plays recordings, seeks from transcript evidence, and supports Calendar and Apple Watch flows.
- The macOS Transcriber accepts common audio and video files, runs the local Whisper wrapper, supports transcript review, and sends reviewed transcript text and timestamped segments to Noted.
- The local API uses a Fastify server, an atomic JSON repository, private uploaded files, and a persisted one-writer processing scheduler.
- The Cloudflare deployment target uses a Worker, D1, private R2, and Queues. It is separate from the local JSON/filesystem implementation.

## Processing choices

Speech and reasoning use separate provider settings. The repository supports the private-network `ai-lab` transcription service, an OpenAI-compatible transcription endpoint, the Mac-local Whisper wrapper, and mock or configured reasoning providers. The local Qwen command runs Whisper and analysis on the Mac through Ollama.

Long recordings use `ffprobe` and `ffmpeg` chunking in the local API. Cloudflare Workers cannot run that subprocess flow, so the Cloudflare path has a separate large-recording limitation.

## Derived meeting information

Meeting processing can produce a summary, key points, decisions, action items, suggested follow-ups, unresolved questions, and calendar candidates. Claims include confidence, state, and transcript evidence when available.

Action items remain compatible with the existing Memories and Open Loops model. Calendar candidates stay suggestions until the user confirms an event in the iOS Calendar flow.

## Product boundaries

- Noted is currently a private, single-user installation.
- Raw audio is not silently sent to Cloudflare by the local-first Mac workflow.
- The Mac is not a public server.
- Speaker diarization is not implemented.
- Browser recording depends on the active page and browser permissions.
- Physical-device and hosted deployment claims require the dated validation evidence to be checked before they are treated as release gates.

When this document conflicts with the code, inspect the code and update the document after confirming the intended behavior.
