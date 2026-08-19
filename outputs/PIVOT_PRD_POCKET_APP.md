# Pocket App Pivot PRD — Memory Garden Recording-First MVP

**Document:** `PIVOT_PRD_POCKET_APP.md`  
**Target repository:** `/Users/yancyshepherd/Desktop/AUTONOMOUS_AGENT`  
**Target agents:** Codex, Luna, or an equivalent autonomous coding agent  
**Mode:** Autonomous, low-interruption, incremental pivot  
**Status:** Execute continuously  
**Date:** 2026-07-23

## 1. Bootstrap instruction

Read this entire document, then inspect the repository before changing it.
This is a pivot of a working MVP, not permission to throw it away and start
again.

Execute all phases continuously. Do not return with a plan, wait for approval,
or ask routine implementation questions. Make reasonable decisions, record
important decisions in `docs/DECISIONS.md`, repair your own failures, and keep
going until the definition of done and quality gates pass.

Only stop for a genuine external blocker such as credentials, unavailable
infrastructure, a paid-service authorization, or a destructive action whose
scope cannot be inferred. When an external dependency is unavailable, isolate
it behind a provider interface and complete every path that can work locally.

The final report must say how to run/open the application, what works, which
quality gates passed, and only the real remaining limitations. Do not report
ordinary implementation failures as blockers.

## 2. Product decision

Memory Garden is pivoting from a general capture-oriented personal memory MVP
to an **app-first alternative to HeyPocket’s physical AI recorder**.

The phone/browser is the recorder. Memory Garden is the searchable, source-
backed memory that the recording becomes.

The hero loop is:

```text
open app → clearly acknowledge recording/consent state → tap Record
→ talk or capture a conversation → tap Stop
→ recording is safely saved immediately → transcript/AI processing runs
→ summary, memories, decisions, actions, and open loops appear
→ ask questions later and jump back to the exact recording moment
```

The product is not a hardware clone and does not require a dedicated device.
The architecture must leave room for a future native iPhone capture client or
optional Bluetooth/dedicated hardware, but neither is part of this pivot.

The original product principle remains intact:

> The user captures information. The system organizes it.

The pivot changes the default capture experience and the prioritization of work:
audio recording is now the fastest and most visible path; notes, URLs, and
files remain valuable supporting inputs.

## 3. Current repository audit — preserve this work

The inspected repository is:

```text
/Users/yancyshepherd/Desktop/AUTONOMOUS_AGENT
```

It is a compact TypeScript MVP named Memory Garden. It already contains:

- React 19 + Vite responsive web UI in `apps/web`.
- Fastify API in `apps/api/src/server.ts`.
- A JSON-backed repository in `apps/api/src/db.ts`, using atomic writes under
  `storage/memory-garden.json`.
- Persistent-ish processing jobs and a separate worker entry point in
  `apps/api/src/worker.ts`.
- A common source model for notes, voice, files, URLs, and images.
- Source preservation before interpretation, with statuses
  `pending`, `processing`, `ready`, `partial`, and `failed`.
- Capture routes for notes, URLs, files, and voice uploads.
- Browser `MediaRecorder` support that records audio and uploads a WebM file.
- Deterministic mock analysis for notes and text, including memories,
  entities, decisions, and open loops.
- Keyword retrieval over memory content, summaries, and source titles.
- An Ask endpoint with source-linked citations.
- Today with open loops, recent sources, and simple resurfacing.
- A Memories browser with type filters and superseded/outdated indications.
- A source detail drawer showing original material, derived memories, loops,
  retry, rename, and delete.
- Authenticated file access, local password login, cookie sessions, upload
  limits, safe file names, Docker Compose, seed data, JSON export, and status
  settings.
- Documentation in `README.md`, `docs/ARCHITECTURE.md`,
  `docs/DECISIONS.md`, and `docs/KNOWN_LIMITATIONS.md`.

Do not replace the stack, rename the product unnecessarily, migrate to a new
database, add native apps, or build a multi-user platform during this pivot.
Extend the existing contracts in place. A future PostgreSQL/pgvector or native
client can be added later through the existing boundaries.

### 3.1 Existing baseline validation

At inspection time:

- `npm test` passed: 3 files, 5 tests.
- `npm run lint` completed with 0 errors and 1 warning for the unused `sources`
  state in `apps/web/src/main.tsx`.
- The test runner initially hit a sandbox-only temporary-cache permission
  error; rerunning with the required project-directory permission passed.
- No browser E2E suite is present.
- The existing `dist` and TypeScript build-info files show that a build has
  been attempted, but the pivot agent must rerun the current and final build
  gates and repair any failures.

### 3.2 Important current limitations and defects to repair while pivoting

These are findings from the actual implementation, not speculative feature
requests:

1. `POST /api/capture/voice` stores audio but `processor.ts` immediately marks
   a voice source `partial` when it has no text. There is no transcription
   provider implementation.
2. The real AI provider class currently falls back to the mock provider; it
   does not make a real compatible-provider call. Preserve the boundary, but
   do not claim real transcription or real AI is implemented.
3. The UI has a basic voice tab, but recording is hidden alongside note/link/
   file tabs. There is no recording hero, elapsed timer, pause/resume, post-stop
   review, playback, microphone state, consent indicator, or processing
   progress.
4. Voice source detail shows “No text extracted from this source” and has no
   audio player, transcript, transcript segments, or seek-to-evidence behavior.
5. `Analysis.summary` is generated but not persisted to the source or exposed
   in source detail.
6. Time-offset provenance does not exist. Ask citations contain a source and
   memory but no transcript segment, quote span, or audio offset.
7. Today does not poll processing status. Its header date is hard-coded and its
   open-loop “Captured” label uses the current time rather than the loop/source
   timestamp.
8. Ask is keyword retrieval plus a very small deterministic answerer; it does
   not yet retrieve transcript evidence or preserve exact evidence spans.
9. `replaceChunks` is called with `chunkText(text).join("")`, which discards the
   intended chunk boundaries. Fix it while adding transcript segment-aware
   chunking.
10. URL failure handling can set `partial` and then continue to `ready`; make
    partial processing state truthful.
11. Source deletion removes JSON-derived records but does not remove the
    stored uploaded file from disk. Fix the deletion cascade.
12. `apps/web/src/main.tsx` uses `@ts-nocheck`; remove it or reduce it to a
    temporary, explicitly documented boundary and make the final typecheck
    meaningful.
13. Tests are unit-only. `store.test.ts` is a placeholder and does not test
    persistence, capture, processing, search, Ask, provenance, or deletion.
14. The current authenticated file route is reused as a download path. Keep
    it authenticated and add safe media playback semantics without exposing
    uploads publicly.

Fix these as part of the relevant pivot phase. Do not create a separate
“cleanup project” that lets the recording feature ship around known broken
contracts.

## 4. Scope and non-goals

### 4.1 Build now

- Recording-first responsive web experience that works on a modern mobile
  browser and desktop browser.
- One-tap or two-tap recording from Today and Capture.
- Visible recording state, timer, microphone permission state, stop, and safe
  save behavior.
- Recording session metadata and original audio retention.
- Consent/privacy acknowledgement and clear “recording active” indicators.
- Transcription provider abstraction with deterministic/mock operation and a
  real OpenAI-compatible configuration path when credentials are supplied.
- Transcript storage with time-aligned segments when available.
- Post-recording summary, memories, decisions, entities, actions/open loops,
  and processing statuses.
- Source detail with audio playback, transcript, transcript search, and
  evidence links that seek to offsets where offsets exist.
- Ask/search grounded in notes, files, URLs, and recordings together.
- Source-backed citations that distinguish recording evidence from derived
  memories and identify the relevant time range.
- Today focused on current recordings, open loops, recent memories, and useful
  resurfacing.
- Backward-compatible typed note, URL, file, source deletion, retry, export,
  supersession, and mock-mode behavior.
- API/data boundaries suitable for a later native iPhone recorder without
  building the native client now.

### 4.2 Do not build now

- Native iOS or Android app.
- Apple Watch app.
- Dedicated hardware, Bluetooth firmware, wake-word service, or always-on
  background recording.
- Gmail, calendar, Slack, contacts, browser extension, or share-sheet
  integrations.
- Automatic recording without an explicit user action.
- Team accounts, sharing, public links, collaboration, billing, or SaaS
  administration.
- A graph visualization, complicated task manager, calendar, or full notes
  editor.
- Perfect speaker diarization, perfect contradiction detection, or legal
  compliance claims.
- A mandatory PostgreSQL/pgvector migration. Keep the portable local store
  for this pivot unless an actual project constraint requires otherwise.

## 5. Product principles for the pivot

1. **Recording is the hero.** A user should understand how to start recording
   within seconds of opening the app.
2. **Never lose the original audio.** AI failure, transcription failure, or a
   malformed response cannot delete the recording.
3. **Be explicit about recording.** No silent capture. Show a live indicator,
   elapsed time, stop control, and privacy/consent reminder.
4. **Interpretation is derived.** Store audio and transcript separately from
   summary, memories, entities, and loops.
5. **Every claim should lead back to evidence.** A citation must identify a
   source; for recordings, it should identify a timestamp when possible.
6. **The user should not maintain an information architecture.** Projects,
   topics, and entities continue to be generated automatically.
7. **Mobile-first does not mean native now.** Make the responsive web capture
   path excellent and keep the API transport-agnostic.
8. **Graceful degradation beats fake completeness.** If transcription is not
   configured, show the saved recording as partial and offer retry or manual
   transcript entry. Do not fabricate a transcript from audio.
9. **Time matters.** Newer recordings and decisions can supersede older
   memories without deleting history.
10. **Low ongoing cost matters.** Keep mock mode deterministic and bound
    transcription/AI work to explicit processing jobs.

## 6. Target user journeys

### Journey A — fast personal thought

1. User opens the app on a phone.
2. Today shows a prominent Record control and a small consent/privacy note.
3. User taps Record, grants microphone permission if needed, and sees a live
   recording state with timer and stop control.
4. User stops. The audio is saved immediately as a recording source.
5. The app shows the recording duration, processing status, and eventual
   transcript/summary/derived memories.

### Journey B — conversation/meeting capture

1. User chooses the conversation/meeting recording mode or acknowledges that
   other people may be present.
2. The UI keeps a visible recording indicator and does not imply that consent
   laws are handled automatically.
3. After stopping, the recording detail shows audio playback, transcript
   segments, summary, decisions, action items, and open loops.
4. A user can edit the title, correct the transcript or a derived memory, and
   retry processing.

### Journey C — later recall

1. User asks, “What did Bill say about the training program?”
2. Retrieval considers transcript text, memory content, source title, capture
   time, and existing notes/files.
3. The answer is cautious and grounded.
4. Citations list the recording and time range. Selecting one opens the source
   drawer and seeks the player to the cited segment.

### Journey D — failure without data loss

1. User records while transcription is unavailable.
2. The audio remains playable and clearly marked `partial`.
3. User can add/edit a transcript or configure a provider and retry.
4. Once transcript text exists, the normal analysis pipeline can continue.

## 7. Preserve-versus-change map

| Existing area | Decision | Required action |
|---|---|---|
| React/Vite web app | Preserve | Keep the tooling and responsive CSS; refactor components as needed. |
| Fastify API | Preserve | Extend routes and keep authenticated REST as the stable boundary. |
| JSON repository | Preserve for this pivot | Add backward-compatible arrays/fields and a versioned migration/normalizer. |
| `Source` model | Preserve and extend | Keep existing IDs and fields; add recording/transcript metadata without breaking notes/files/URLs. |
| `Memory`, `Entity`, `Relationship`, `OpenLoop` | Preserve | Add evidence references and recording-aware metadata. |
| Job/worker pattern | Preserve and strengthen | Add transcription/analyze stages, retries, idempotency, and truthful statuses. |
| Mock AI | Preserve and expand | Keep deterministic note behavior; add transcript analysis and fixture-driven recording tests. |
| Keyword search | Preserve as fallback | Search transcript and use a provider-independent retrieval interface; embeddings remain optional. |
| Today / Ask / Memories / Settings | Preserve | Reprioritize the UI around recording and expose new status/evidence fields. |
| Source drawer | Preserve and expand | Add audio, transcript, summary, segments, consent metadata, and seekable citations. |
| Docker Compose | Preserve | Keep API/worker/web and persistent volume behavior; document any new env vars. |
| Existing capture routes | Preserve | Keep note, URL, file, and voice endpoints working; make voice route session-aware. |
| Native client/hardware | Architect for only | Use clean upload/session APIs, but do not implement either client. |

## 8. Recording-first UI requirements

### 8.1 Today home

On mobile, the first screen must visibly prioritize recording. Include:

- A primary Record button or record card above secondary capture choices.
- A short explanatory label such as “Capture what’s happening. We’ll turn it
  into searchable memory.”
- Current recording state if a session is active.
- Recent recordings with duration, date, processing state, and source icon.
- Open loops and recent/resurfaced memories below the recording area.

On desktop, retain the calm left navigation but make Record the most visually
prominent capture action. The existing design language—sage, coral, lavender,
restrained cards, readable typography—may remain; do not redesign for its own
sake.

### 8.2 Recording control

Implement a reusable recording controller, not recording logic duplicated in
multiple pages. It must:

- Request microphone access only after a deliberate user action.
- Show `idle`, `requesting`, `recording`, `paused`, `stopping`, `saved`, and
  `error` states.
- Show elapsed time while recording.
- Show a clearly identifiable stop control.
- Stop tracks and release the microphone on stop, cancel, component unmount,
  and error.
- Handle browsers without `MediaRecorder` or microphone access with a clear
  fallback message.
- Prefer a broadly supported audio format, detect the actual MIME type, and
  send the actual type to the API. Do not blindly label every blob WebM.
- Protect against accidental navigation while recording where browser support
  allows.
- Avoid automatic recording on page load.

Pause/resume is desirable for the web MVP if it can be implemented safely. If
browser support is inconsistent, hide the control rather than pretending it
works. A stop-and-start flow must still work everywhere supported.

### 8.3 Consent and privacy indicators

Before starting, show a concise reminder:

> Recording captures microphone audio. Make sure everyone present knows and
> agrees where required. You control when recording starts and stops.

Require an explicit acknowledgement for conversation/meeting mode. A private
thought mode may use a less prominent reminder, but the active recording
indicator is always required.

Store the user’s acknowledgement and mode as metadata for auditability; do not
present this as legal compliance. Use neutral copy and do not give jurisdiction-
specific legal advice.

While recording:

- Show a red/coral recording indicator, timer, and Stop button.
- Keep the indication visible on small screens.
- Show a browser-level microphone permission failure distinctly from an API
  upload failure.
- Never hide an active recording behind a navigation transition.

### 8.4 Stop and post-recording review

Stopping must prioritize data safety:

1. Finalize the local blob.
2. Upload/save the original audio immediately.
3. Create the source/session record even if transcription/AI is unavailable.
4. Show duration, title (default “Recording — date/time”), source type,
   consent mode, and processing status.
5. Offer playback and a clear retry path.

Allow the user to rename the recording after save. Do not require a title
before recording. Provide a safe cancel/delete path for a recording that has
not yet been uploaded.

### 8.5 Mobile navigation

Keep Capture reachable from the mobile header. If the existing mobile menu is
non-functional, repair it or replace it with a compact bottom/slide navigation.
Do not leave a visible menu button that does nothing.

## 9. Data model and migration strategy

Keep the existing entities and add the smallest explicit recording layer that
supports future native capture.

### 9.1 Extend `Source`

Keep all existing source fields and add optional fields similar to:

```ts
interface Source {
  // existing fields remain
  summary?: string;
  transcriptText?: string;
  transcriptStatus?: "not_applicable" | "pending" | "processing" | "ready" | "partial" | "failed";
  durationMs?: number;
  audioMimeType?: string;
  consentMode?: "private_thought" | "conversation" | "meeting";
  consentAcknowledged?: boolean;
  recordingSessionId?: string;
  processingVersion?: number;
}
```

Do not move the original audio into `transcriptText` or `originalText`. Keep
the file path private and preserve the existing `filePath` behavior.

### 9.2 Add `RecordingSession`

Add a first-class record or a repository-equivalent structure:

```ts
interface RecordingSession {
  id: string;
  sourceId: string;
  status: "capturing" | "uploaded" | "processing" | "ready" | "partial" | "failed" | "cancelled";
  startedAt: string;
  endedAt?: string;
  durationMs?: number;
  mimeType?: string;
  client: "web" | "native" | "hardware";
  consentMode: "private_thought" | "conversation" | "meeting";
  consentAcknowledged: boolean;
  metadata: Record<string, unknown>;
}
```

The current web client is `web`. `native` and `hardware` are reserved values
for future clients and must not cause the current UI to appear unfinished.

### 9.3 Add `TranscriptSegment`

Use a segment structure that does not assume speaker diarization is available:

```ts
interface TranscriptSegment {
  id: string;
  sourceId: string;
  segmentIndex: number;
  startMs?: number;
  endMs?: number;
  text: string;
  speaker?: string;
  confidence?: number;
  createdAt: string;
}
```

If a provider returns no timestamps, store one or more segments with undefined
offsets and make the UI say that seeking is unavailable. Do not invent times.

### 9.4 Evidence references

Add optional evidence metadata to memories, open loops, and Ask citations. A
simple MVP shape is sufficient:

```ts
interface EvidenceRef {
  sourceId: string;
  segmentId?: string;
  startMs?: number;
  endMs?: number;
  quote?: string;
}
```

Every recording-derived memory should have at least `sourceId`; when the
transcript provider has segments, attach the most relevant segment(s). Keep
the raw source and transcript independently inspectable.

### 9.5 JSON migration

The repository currently loads a JSON document and spreads it over a default
state. Replace that implicit behavior with an explicit, backward-compatible
normalizer:

- Add a storage schema version.
- Treat missing arrays (`recordingSessions`, `transcriptSegments`) as empty.
- Add defaults for new optional source fields.
- Preserve existing IDs and data.
- Never silently discard unknown fields during a migration.
- Write migrated state atomically.
- Add tests starting from a pre-pivot fixture.

Do not require the user to delete `storage/memory-garden.json`. Existing notes,
URLs, files, memories, entities, loops, and relationships must remain usable.

## 10. Processing pipeline

Use a common pipeline, with audio-specific stages:

```text
capture/upload
  ↓
persist Source + RecordingSession
  ↓
create/recover ProcessingJob
  ↓
audio validation and metadata
  ↓
transcription provider (recordings only)
  ↓
persist transcript + aligned segments
  ↓
normalize text
  ↓
chunk text with real boundaries and overlap
  ↓
AI analysis: summary, memories, entities, decisions, actions, loops
  ↓
persist evidence references and relationships
  ↓
mark ready/partial/failed and expose progress
```

### 10.1 Idempotency and retries

- A retry must not duplicate memories, loops, entities, or relationships.
- Track a processing version/content hash or clear/reconcile derived records
  for the current source before recreating them.
- Preserve the audio and previous transcript when a later attempt fails.
- Limit automatic retries in the worker; manual retry remains available.
- Do not process the same pending job concurrently in API and worker without a
  guard appropriate to the current store.

### 10.2 Status semantics

Use these meanings consistently:

- `pending`: source saved; work has not started.
- `processing`: transcription or analysis is active.
- `ready`: transcript/analysis available for the source type.
- `partial`: source is safe and usable, but a stage is unavailable or incomplete
  (for example audio saved but transcription provider missing).
- `failed`: a stage failed after retries; source and whatever derived data
  already exists remain available.

Expose a short human-readable processing stage/error to the UI. Do not show a
generic spinner forever.

## 11. Provider abstractions

Keep the current `AIProvider` boundary and add a real transcription boundary:

```ts
interface TranscriptionResult {
  text: string;
  segments: Array<{
    startMs?: number;
    endMs?: number;
    text: string;
    speaker?: string;
    confidence?: number;
  }>;
  language?: string;
}

interface TranscriptionProvider {
  transcribe(input: {
    filePath: string;
    mimeType?: string;
    sourceId: string;
  }): Promise<TranscriptionResult>;
}
```

Provider rules:

- Mock mode must require no credentials and remain deterministic.
- The mock transcription path may use an explicit fixture/sidecar transcript
  in tests; it must not pretend to derive words from arbitrary audio bytes.
- A real OpenAI-compatible transcription implementation may be used when
  `AI_BASE_URL`, `AI_API_KEY`, and `TRANSCRIPTION_MODEL` are configured.
- Validate provider output before persistence.
- Do not log audio contents, API keys, or full private transcripts.
- If no transcription provider is configured, retain audio and mark partial;
  offer manual transcript entry or later retry.

Extend `AIProvider.analyzeSource` so it receives the normalized transcript and
can return evidence mapping, or add a separate analysis method. Keep the
existing deterministic note behavior working.

## 12. API contract

Keep all existing routes unless a compatibility wrapper is necessary. Add or
extend routes as follows.

### Existing routes that must continue to work

```text
POST /api/capture/note
POST /api/capture/url
POST /api/capture/file
POST /api/capture/voice
GET  /api/sources
GET  /api/sources/:id
POST /api/sources/:id/reprocess
PATCH /api/sources/:id
DELETE /api/sources/:id
GET  /api/memories
PATCH /api/memories/:id
GET  /api/entities
GET  /api/open-loops
PATCH /api/open-loops/:id
GET  /api/search
POST /api/ask
GET  /api/today
GET  /api/settings/status
GET  /api/export
GET  /files/:id
```

### Recording request

Keep `POST /api/capture/voice` as the web-compatible upload endpoint. Extend
its multipart contract to accept:

```text
audio/file: the recorded blob
title: optional string
durationMs: optional number
startedAt: optional ISO timestamp
endedAt: optional ISO timestamp
consentMode: private_thought | conversation | meeting
consentAcknowledged: true/false
client: web (default)
```

It must persist the source/session and return promptly with the source plus
session/status identifiers. It must not wait for transcription or AI analysis.

If adding a dedicated route, use a clean resource shape such as:

```text
POST /api/recordings
GET  /api/recordings/:id
GET  /api/recordings/:id/transcript
PATCH /api/recordings/:id/transcript
POST /api/recordings/:id/reprocess
```

The existing voice route may be the compatibility wrapper around these
resources. Choose one implementation and document it; do not create duplicate
business logic.

### Source detail response

Extend `GET /api/sources/:id` to include, when applicable:

```json
{
  "source": {},
  "recordingSession": {},
  "transcript": {"text": "...", "segments": []},
  "memories": [],
  "entities": [],
  "openLoops": []
}
```

### Ask citations

Preserve existing citation fields and add optional fields:

```json
{
  "memoryId": "...",
  "sourceId": "...",
  "sourceTitle": "...",
  "sourceType": "voice",
  "capturedAt": "...",
  "content": "...",
  "superseded": false,
  "segmentId": "...",
  "startMs": 12500,
  "endMs": 18900,
  "quote": "..."
}
```

Do not require offsets when the provider does not supply them.

### Settings

Expose whether transcription is configured, which mode is active, storage
type, and app version. Never return secrets.

## 13. Search and grounded recall

Keep local keyword retrieval as a reliable baseline and expand it to include:

- source title
- original/extracted text
- transcript text
- transcript segment text
- memory content and summary
- entity names
- open-loop descriptions

Search results must retain source and evidence identity. If semantic embeddings
are later configured, put them behind a provider-independent interface and use
hybrid ranking; do not make the pivot dependent on an unavailable vector
database.

Improve Ask behavior enough for the recording use case:

- Retrieve a bounded set of relevant memories/segments.
- Include source type, capture date, and evidence offsets in context.
- Prefer current decisions over superseded ones while showing history.
- Answer “I don’t have enough evidence” when retrieval is empty or weak.
- Never imply that an audio segment was heard if only a manual transcript is
  available; label the evidence as transcript-derived.
- Return citations for voice recordings and make them open the source detail.

The deterministic provider should handle the acceptance questions using the
same retrieval context as real providers. Do not hard-code a single product
answer only to pass a test.

## 14. Source detail and provenance UX

Expand the existing drawer rather than replacing it.

For a voice source show:

1. Title, capture date/time, duration, source type, and processing badge.
2. Consent mode and a compact privacy note.
3. Authenticated audio player with playback controls.
4. Transcript text, preferably rendered as timestamped segments.
5. A segment search/highlight control if inexpensive.
6. Summary.
7. Interpreted memories, decisions, facts, ideas, and confidence.
8. Open loops with resolve/dismiss.
9. Entities and source relationships if available.
10. Retry/manual transcript controls for partial/failed processing.
11. Rename and safe delete.

When a user selects a citation with `startMs`/`endMs`, open the drawer and
seek the audio player to `startMs`. Visually highlight the cited segment when
possible. If no offset exists, open the source and scroll/highlight the quoted
transcript text without pretending it can seek.

Original audio remains private and authenticated. Add range support only if
needed for the player; do not make `/storage` or uploads publicly served.

## 15. Today and open loops

Retain Today’s current cards but make them recording-aware:

- A current-day recording card with duration and processing stage.
- Recent recordings and recent memories in chronological order.
- Open loops showing the actual source/derived timestamp.
- “From recording” labels where useful.
- Resurfaced memories may remain deterministic and simple.
- A truthful current date, not a hard-coded date.
- Poll or refresh pending/processing cards so the user sees progress without a
  full manual reload.

Open loops must remain resolvable/dismissible. Do not turn every utterance into
a task; preserve the existing conservative extraction behavior and add tests
for false-positive resistance.

## 16. Privacy, security, and lifecycle

Keep the current self-hosted single-user posture, but repair obvious gaps:

- Keep auth on all source, transcript, audio, memory, Ask, and export routes.
- Do not expose upload directories through static hosting.
- Validate upload size, MIME type, and safe file names.
- Store consent metadata without claiming legal compliance.
- Do not log raw audio or full sensitive text unnecessarily.
- Avoid returning API keys or secrets in settings.
- Ensure deletion removes source, session, transcript segments, chunks,
  memories, relationships, loops, and the audio file where present.
- Handle missing files gracefully rather than crashing source detail.
- Preserve JSON export with recording metadata and transcript data. Include
  evidence references; do not embed binary audio in the JSON export.
- Document that users must back up both the JSON store and upload directory.

Do not add automatic recording or hidden background behavior.

## 17. Implementation order — execute without pauses

### Phase 0 — inspect and baseline

- Read the repository, this PRD, existing docs, and package scripts.
- Run current tests/lint/typecheck/build as safely possible.
- Record actual failures and preserve working changes.
- Do not overwrite user data or delete `storage`.

### Phase 1 — data contracts and migration

- Extend types and JSON state with versioning, recording sessions, transcript
  segments, source summary/transcript/status fields, and evidence refs.
- Add normalization/migration tests from a pre-pivot state.
- Preserve existing seed and existing capture flows.

### Phase 2 — recording persistence

- Refactor browser recording into a reusable controller.
- Implement safe save, metadata, consent acknowledgement, duration, actual
  MIME handling, and authenticated audio access.
- Keep `/api/capture/voice` backward compatible.
- Add recording/session API tests.

### Phase 3 — transcription and analysis

- Add provider interfaces and configured-provider implementation boundary.
- Add deterministic fixture/mock transcription for tests and local UI review.
- Persist transcript and aligned segments.
- Run analysis from transcript, persist summary/evidence, and make jobs
  idempotent/retryable.
- Repair chunking and partial-state semantics.

### Phase 4 — recording-led UI

- Make Today and Capture recording-first on mobile and desktop.
- Add timer, states, consent/privacy indicator, playback, post-stop status,
  polling, and useful errors.
- Expand source detail with audio/transcript/summary/segment evidence.
- Repair the mobile menu and remove dead controls.

### Phase 5 — grounded recall and temporal behavior

- Search transcript/segments and return evidence-rich citations.
- Improve Ask for voice questions and current-versus-superseded decisions.
- Make citation clicks seek to timestamps where available.
- Keep typed note, URL, and file retrieval working.

### Phase 6 — hardening and compatibility

- Fix deletion of physical audio files and all derived records.
- Add validation, auth coverage, error boundaries, missing-file handling,
  migration/export coverage, and no-provider behavior.
- Remove or justify `@ts-nocheck` and fix lint warnings.
- Update README, architecture, decisions, and known limitations.

### Phase 7 — validation and delivery

- Run unit, integration, and browser E2E tests in mock mode.
- Run `npm run lint`, `npm run typecheck`, `npm test`, and `npm run build`.
- Test Docker Compose from a clean data volume without deleting the user’s
  existing project data; use a separate temporary test data directory/volume.
- Exercise the acceptance tests below.
- Repair failures and rerun the affected gates.

## 18. Acceptance tests

Use mock mode for deterministic CI. Use real transcription/AI only when
credentials are present; absence of credentials must not block the rest.

### A. Existing note-memory flow remains intact

1. Start the app and log in.
2. Capture the original Atlas note from `AUTONOMOUS_BUILD_PRD.md`.
3. Wait for processing.
4. Confirm a decision, entity, and open loop are created.
5. Search for “Atlas database”.
6. Ask what database was chosen.
7. Open the citation and original source.
8. Resolve the loop and delete the source.
9. Confirm derived records disappear and existing unrelated sources remain.

### B. Mobile recording happy path

1. Open the app at a narrow mobile viewport.
2. Confirm Record is the primary action on Today.
3. Tap Record and grant microphone permission in a browser test harness.
4. Confirm the consent/privacy reminder and active recording indicator.
5. Confirm the timer advances.
6. Stop the recording.
7. Confirm the source and recording session are saved without waiting for AI.
8. Confirm duration, MIME type, capture time, and processing status appear.
9. Open source detail and play the authenticated original audio.

### C. Transcript and post-recording analysis

Use a deterministic transcript fixture such as:

```text
Bill said the training cohort will start next month. I decided to send the
updated schedule on Friday. I still need to ask Bill for the final attendee
list.
```

Expected:

- transcript is visible and preserved;
- timestamped segments are stored when the fixture supplies them;
- summary is stored and displayed;
- a decision is extracted;
- an action/open loop about the attendee list is extracted;
- Bill/training cohort entities or equivalent useful references are present;
- derived records link to the recording source.

### D. Grounded recall with timestamp provenance

1. Ask: “What did Bill say about the training cohort?”
2. The answer references the transcript-derived evidence.
3. At least one citation is a voice source.
4. Citation includes `sourceId`, and includes segment/offset fields when
   available.
5. Selecting the citation opens the recording drawer and seeks to the cited
   offset; if no offset exists, it opens the transcript and shows the quote.
6. Ask does not answer from an unrelated note when the relevant recording is
   available.

### E. No-transcription resilience

1. Disable transcription configuration.
2. Record/upload a valid audio file.
3. Confirm the source/audio is retained and marked `partial` with a useful
   explanation.
4. Confirm the user can play/delete the audio.
5. Add or edit a transcript manually, or configure the provider in a test
   environment.
6. Retry processing.
7. Confirm analysis can proceed from the transcript without re-uploading audio.

### F. Consent/privacy state

1. Start a conversation/meeting recording.
2. Confirm acknowledgement is required and stored.
3. Confirm recording state is visible while active.
4. Confirm stopping releases the browser microphone tracks.
5. Confirm the source detail does not claim that legal requirements were
   automatically satisfied.

### G. Supersession across recording and note

1. Capture a note saying Atlas will use SQLite.
2. Process a newer recording/transcript saying Atlas will use PostgreSQL
   instead.
3. Keep both sources accessible.
4. Mark the older decision outdated/superseded where overlap is reliable.
5. Ask the current database question.
6. Prefer PostgreSQL while exposing the older evidence/history.

### H. Backward-compatible files and URLs

1. Capture a URL and a text file.
2. Confirm source retention and existing partial URL behavior.
3. Confirm source detail and deletion still work.
4. Confirm the pivot did not require recording for non-audio captures.

### I. Migration and export

1. Start with a fixture representing the old JSON state.
2. Load it through the new repository.
3. Confirm old sources/memories/loops/entities are unchanged and readable.
4. Export the new state.
5. Confirm recording metadata/transcript/evidence are present without binary
   audio embedded in the JSON.

## 19. Required tests

Add real tests rather than placeholder assertions.

### Unit tests

- recording state transitions and elapsed-duration handling;
- MIME selection/fallback logic;
- consent metadata validation;
- JSON migration/defaults;
- transcription output normalization and malformed-output handling;
- transcript segment persistence and evidence mapping;
- analysis idempotency/retry behavior;
- open-loop extraction and status changes;
- chunking that preserves boundaries/overlap;
- search ranking over transcript and memory content;
- supersession behavior;
- deletion cascade including physical audio path handling.

### Integration tests

Exercise the Fastify API and repository in an isolated temporary data
directory:

- login/authenticated request;
- multipart voice upload;
- source/session creation before processing completes;
- processing with mock transcript and mock AI;
- source detail with transcript/segments/evidence;
- Ask with voice citation;
- manual transcript update and reprocess;
- partial processing when transcription is unavailable;
- note/URL/file compatibility;
- delete source and all derived data/files;
- export.

### Browser E2E

Add Playwright or the lightest reliable browser test setup compatible with the
repository. Use mock `getUserMedia`/`MediaRecorder` behavior so CI does not
need physical microphone hardware. Cover the mobile happy path, source detail,
Ask citation, loop resolution, and login.

If adding Playwright creates disproportionate setup cost, implement the same
journey in a deterministic browser-capable test and document the choice. Do
not leave E2E as an untested claim.

## 20. Quality gates

The agent must not declare completion until all applicable gates pass:

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

Also:

- browser E2E passes in mock mode;
- Docker Compose builds and starts from a clean temporary volume;
- API health responds;
- login works;
- a recording can be saved and later inspected;
- no new lint/type errors are hidden by `@ts-nocheck`;
- README commands match the actual project;
- the final known-limitations document distinguishes “not configured” from
  “not implemented”.

If an external provider is not configured, the relevant provider integration
may remain unverified, but the mock path, provider boundary, partial state,
manual transcript/retry path, and all non-provider tests must pass.

## 21. Documentation updates required

Update existing docs in place; do not create a second competing architecture
description.

### `README.md`

Explain:

- Memory Garden is now recording-first;
- local startup and Docker startup;
- default password behavior and security warning;
- how to record from mobile/desktop;
- mock mode and provider configuration;
- what happens when transcription is unavailable;
- backup of JSON plus uploads;
- test/lint/typecheck/build commands;
- future native client/hardware is not part of this MVP.

### `docs/ARCHITECTURE.md`

Document:

- source/session/transcript/segment/memory/evidence relationships;
- browser capture and future-client API boundary;
- job stages and statuses;
- storage/privacy boundary;
- retrieval and timestamp provenance;
- why the portable JSON repository remains for this pivot.

### `docs/DECISIONS.md`

Add concise ADR-style entries for:

- recording-first pivot;
- preserving JSON repository and API;
- separate audio/transcript/derived data;
- provider/mocking strategy;
- consent metadata and explicit recording indicators;
- timestamp provenance behavior when provider offsets are unavailable.

### `docs/KNOWN_LIMITATIONS.md`

Be candid about:

- browser background/lock-screen recording limits;
- provider availability and cost;
- mock transcription fixtures versus real transcription;
- absent native app/hardware;
- speaker diarization or timestamp gaps;
- single-user auth/session limitations;
- JSON storage scale and backup requirements.

## 22. Future-client compatibility rules

The pivot must not depend on the browser as the only possible producer of
recordings.

Keep these concepts transport-agnostic:

- `client` metadata (`web`, future `native`, future `hardware`);
- upload/session creation separate from transcription/analysis;
- explicit started/ended timestamps and duration;
- actual MIME type and source file ownership;
- consent mode/acknowledgement metadata;
- a stable source/session ID returned immediately after upload;
- polling/status retrieval that a native client can use;
- authenticated source/audio/transcript APIs.

Do not add a native codebase or hardware protocol now.

## 23. Autonomous decision policy

When something is unspecified:

1. Preserve user data and existing working behavior.
2. Reuse the current repository, API, and UI patterns.
3. Prefer a small, testable abstraction over a framework migration.
4. Prefer deterministic/local behavior when credentials are unavailable.
5. Keep original audio and source material separate from AI interpretation.
6. Use explicit status and error states over hidden retries/spinners.
7. Make the smallest reversible decision and document significant choices.
8. Do not spend tokens debating visual minutiae or future integrations.
9. Continue until the acceptance tests and gates pass.

## 24. Definition of done

The pivot is complete when all of the following are true:

- The existing Memory Garden app still starts and authenticates.
- Typed notes, URLs, files, search, Ask, Today, Memories, source detail,
  retry, export, supersession, and deletion continue to work.
- Recording is the most prominent capture action on mobile and desktop.
- A user can explicitly start/stop a browser recording with visible timer and
  microphone/consent state.
- The original audio is saved immediately and remains authenticated/playable.
- Recording sessions have durable metadata and statuses.
- Transcription has a provider boundary, mock/fixture path, configured real
  path, manual/partial fallback, and retry behavior.
- Transcript text and segments are stored separately from audio.
- Summary, memories, entities, decisions, actions, and open loops can be
  derived from transcript text.
- Recording-derived data links to its source and evidence; offsets are used
  when provided and never fabricated.
- Source detail shows audio, transcript, summary, derived records, status,
  consent mode, and useful recovery actions.
- Ask/search considers recording transcripts and returns grounded citations;
  recording citations can seek to a timestamp when available.
- Today shows recording status/recent recordings and correct open-loop/source
  timestamps.
- Migration preserves the pre-pivot JSON state.
- Deletion cleans derived data and stored audio.
- No provider/API credentials are committed or exposed.
- Unit, integration, and browser journey coverage exists for the core paths.
- `npm run lint`, `npm run typecheck`, `npm test`, and `npm run build` pass.
- Docker Compose starts from a clean temporary volume.
- Documentation and known limitations are current.
- The final agent response contains only operational handoff information.

When complete, report the running/open URL, setup credentials or environment
steps actually required, major working capabilities, validation results, and
genuine limitations. Do not report a phase plan as the result.

