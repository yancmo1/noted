# Decisions

## ADR-000 — recording-first pivot

The primary action is recording, not filing. A browser-based recorder gives the product the lowest-friction path toward a HeyPocket-like experience while keeping the web app portable. Notes, links, and files remain as explicit secondary capture paths.

## ADR-001 — deterministic mock provider by default

The app must remain useful without paid AI credentials. The mock provider extracts useful MVP patterns deterministically and shares the same interface as the real-provider boundary. Voice audio is never treated as transcribed merely because mock mode is enabled; without a transcript fixture or configured provider, the source stays `partial` and can be corrected manually.

## ADR-002 — capture before interpretation

Source creation is independent of AI processing. A provider failure changes processing state but never removes the original capture.

## ADR-003 — portable JSON persistence for MVP

Native database bindings were avoided because the target Node 26 environment has no compatible prebuilt SQLite binary. The repository writes an atomic JSON file and exposes a narrow interface so a Postgres/pgvector adapter can replace it without changing the API or UI.

## ADR-004 — local retrieval first

The MVP uses deterministic token scoring instead of pretending to provide embeddings when no embedding provider is configured. The retrieval interface remains provider-independent.

## ADR-005 — evidence is first-class

Every derived memory and open loop may carry segment ID, time offsets, and a short quote. Ask citations use the same shape. This keeps the system honest: users can inspect the original transcript and jump to the relevant audio instead of trusting an opaque summary.

## ADR-006 — consent is a capture constraint

Private thought is the default recording mode. Conversation and meeting modes require an acknowledgement before recording starts. The acknowledgement is stored with the recording session for future auditability; it is a product safeguard, not a legal compliance claim.

## ADR-007 — independent speech and reasoning providers

Speech-to-text and reasoning have different cost, latency, privacy, and model requirements. They therefore use separate `TRANSCRIPTION_*` and `LLM_*` configuration and provider instances. The Groq transcription default does not force Groq to handle Ask or memory interpretation.

## ADR-008 — chunk before provider upload

A recording must not be sent as one opaque request when it may exceed provider limits. The API chunks long or oversized audio with ffmpeg, offsets every returned segment and word to the original timeline, merges text in order, and deletes temporary chunks. This keeps provider-specific limits out of the domain model and leaves room for a local provider implementation.
