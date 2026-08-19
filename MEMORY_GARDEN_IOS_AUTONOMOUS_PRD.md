# Memory Garden iOS — Autonomous Native Client Build PRD

**Document:** `MEMORY_GARDEN_IOS_AUTONOMOUS_PRD.md`  
**Build mode:** Autonomous / minimal-interruption  
**Target agent:** Codex, Luna, or equivalent coding agent  
**Platform:** iOS / Xcode / SwiftUI  
**Date:** 2026-07-23  
**Status:** Approved for autonomous implementation

---

# 1. EXECUTIVE DIRECTIVE

Build the complete native iOS client for the existing Memory Garden application.

Memory Garden already has a functioning backend/web application capable of storing recordings, transcribing them, extracting memories/open loops/evidence, and making them searchable.

The iOS application is **not a rewrite of Memory Garden**. It is the native mobile capture and playback client for the existing platform.

Primary product goal:

> **Turn an iPhone into the capture device for a Pocket-style AI memory system.**

The user should be able to:

1. Open the iPhone app.
2. Tap one large Record button.
3. Record a conversation, meeting, thought, or extended period of audio.
4. Lock the phone or leave the app while recording.
5. Return and stop the recording.
6. Keep the original recording safely on-device until server upload succeeds.
7. Upload the recording to Memory Garden.
8. Allow the existing backend to transcribe and process it.
9. View transcript, summary, memories, open loops, and evidence.
10. Tap a timestamped citation and jump directly to that point in the audio.
11. Ask questions against the accumulated Memory Garden knowledge base.

The deliverable is a **complete Xcode project**, not snippets or pseudocode. The final result must be openable in Xcode and runnable on a physical iPhone.

---

# 2. AUTONOMOUS AGENT RULES

## Do not ask routine questions

Do not ask the user to choose file names, Xcode groups, view names, architecture details, SF Symbols, colors, retry constants, ordinary Apple-framework choices, test names, or naming conventions.

Make reasonable engineering decisions and continue.

## Inspect before modifying

Before implementation:

1. Inspect the existing Memory Garden repository.
2. Identify current backend/API structure.
3. Identify authentication.
4. Identify recording/source upload endpoints.
5. Identify transcript/evidence structures.
6. Identify Ask/search endpoints.
7. Reuse existing contracts wherever practical.

Do not invent a parallel API when capability already exists.

If the backend needs a small endpoint for iOS, add it cleanly and backward-compatibly.

## Continue until complete

Do not stop after scaffolding, recording, upload, playback, Ask, or tests. Continue until the acceptance criteria pass.

## Repair your own failures

Build failures, Swift concurrency issues, decoding errors, backend mismatches, upload failures, playback failures, and routine audio bugs are not user blockers. Fix them.

## Genuine blockers only

Stop only for something only the user can provide, such as Apple signing credentials, inaccessible infrastructure, a missing production URL not present anywhere, or external secrets.

Use configuration/dev defaults and continue wherever possible.

---

# 3. ARCHITECTURE

Preserve the existing working Memory Garden platform.

```text
                    ┌──────────────────────┐
                    │ Native iOS Client    │
                    │ SwiftUI              │
                    │                      │
                    │ Record / Playback    │
                    │ Ask / Today / Browse │
                    └──────────┬───────────┘
                               │ HTTPS
                               ▼
┌───────────────────────────────────────────────────────┐
│              Existing Memory Garden API              │
│ Sources / Upload / Jobs / Ask / Search / Memories   │
└──────────────────────┬────────────────────────────────┘
                       │
        ┌──────────────┼───────────────────┐
        ▼              ▼                   ▼
   PostgreSQL      File Storage      Processing Worker
                                           │
                               ┌───────────┼───────────┐
                               ▼           ▼           ▼
                            Groq STT       LLM     Embeddings
```

The web app remains supported. The native app becomes another first-class client.

The iPhone should handle:

- capture
- durable local persistence
- upload
- playback
- mobile browsing
- Ask UI

The backend should continue handling:

- transcription
- chunking
- LLM processing
- embeddings
- search/retrieval
- memory extraction
- open-loop extraction
- provenance

Never put AI provider secrets in the iOS app.

---

# 4. TECH STACK

Use:

- Xcode
- Swift
- SwiftUI
- AVFoundation
- URLSession
- Swift Concurrency
- Observation/Observable
- SwiftData or another lightweight durable local persistence mechanism
- Keychain
- XCTest
- XCUITest where practical

Prefer Apple frameworks. Avoid third-party dependencies unless clearly justified.

Use a modern deployment target such as iOS 17+ unless repository constraints require otherwise.

---

# 5. COMPLETE XCODE PROJECT

Create the project inside the existing repository, preferably:

```text
/apps/ios/
```

Deliver a valid project/workspace including:

- `MemoryGarden.xcodeproj` or valid `.xcworkspace`
- app target
- unit test target
- UI test target where practical
- asset catalog
- app icon placeholders/initial art
- required Info.plist entries
- microphone usage description
- background audio capability
- required entitlements
- configuration for development/production API URLs
- iOS README

Do not merely generate Swift source files and tell the user to create a project manually.

---

# 6. PRIMARY NAVIGATION

Use native mobile-first navigation.

Recommended tabs:

```text
Today
Record
Recordings
Ask
More
```

The Record action must remain extremely easy to access.

---

# 7. RECORD SCREEN

This is the hero screen.

Idle:

```text
Memory Garden

Capture what matters.

        ●
      RECORD
```

Recording:

```text
● Recording

01:42:18

[ Mark Moment ]

[ Pause ]   [ Stop ]
```

Required:

- elapsed time
- clear recording state
- pause
- resume
- stop
- Mark Moment/bookmark
- meaningful error/interruption state
- protection from obvious accidental stop where practical

Waveform is optional. Do not delay MVP for decorative visualization.

---

# 8. RECORDING ENGINE

Implement a dedicated audio service, e.g. `AudioRecorder`.

Responsibilities:

- request microphone permission
- configure `AVAudioSession`
- start
- pause
- resume
- stop
- preserve local file URL
- expose elapsed duration
- handle interruptions
- handle audio-route changes
- restore UI state correctly
- publish failures

Use compressed speech-appropriate audio, preferably M4A/AAC unless backend compatibility requires otherwise.

Do not use unnecessarily large raw PCM for long recordings.

Document codec/container/sample-rate/channels/bitrate.

---

# 9. BACKGROUND / LOCK-SCREEN RECORDING

This is mandatory.

Configure supported iOS background audio recording behavior.

Validate the intended flow:

1. User starts recording in foreground.
2. Locks iPhone.
3. Recording continues.
4. Unlocks.
5. App reflects same active session.
6. Stops.
7. File is valid.

Also handle:

- foreground → background → foreground
- screen-off behavior
- Bluetooth/headphone route changes
- `AVAudioSession.interruptionNotification`
- system/phone interruptions where testable

Never silently claim recording continued if iOS interrupted it.

Surface interruption state clearly.

---

# 10. NEVER LOSE THE RECORDING

This is the most important implementation rule.

**Recording must be local-first. Network connectivity must not be required for capture.**

Correct:

```text
Microphone
   ↓
Durable local recording
   ↓
Durable local metadata
   ↓
Stop
   ↓
Queue upload
   ↓
Upload to Memory Garden
   ↓
Server acknowledgement
   ↓
Processing
```

Incorrect:

```text
Microphone → direct live stream to Groq
```

If the user records for hours without network, the recording must still exist locally.

---

# 11. LOCAL RECORDING MODEL

Persist metadata such as:

```text
LocalRecording
- id
- localFileURL
- createdAt
- duration
- title
- state
- uploadAttempts
- serverSourceId
- byteSize
- bookmarks
- lastError
```

Suggested states:

```text
recording
paused
localOnly
queued
uploading
uploaded
processing
ready
partial
failed
```

Persist enough to survive:

- app termination after capture
- device restart where practical
- network loss
- upload failure

Pending uploads should be rediscovered on launch.

---

# 12. MARK MOMENT

While recording, support a `Mark Moment` action.

Store at minimum:

```text
recordingId
timestamp
createdAt
```

Bookmarks should remain associated with the recording and be visible on playback.

This gives the user an intentional signal:

> Something important happened here.

---

# 13. UPLOAD MANAGER

Implement a resilient `UploadManager`.

Required:

- queued uploads
- retry on failure
- bounded/exponential retry
- manual retry
- upload status/progress where available
- no deletion before server acknowledgement
- idempotency / duplicate prevention
- recovery after relaunch
- large-file-safe behavior

Use background-capable `URLSession` upload where practical.

Do not create duplicate backend Sources on retries.

Use a persistent client recording UUID as an idempotency key. Add backend support if necessary.

---

# 14. LOCAL RETENTION

Default safety behavior:

Keep local audio until:

1. upload is confirmed
2. server Source is accessible
3. recording is not in an error state

Do not aggressively auto-delete.

Storage cleanup/settings may be simple in MVP.

---

# 15. BACKEND INTEGRATION

Inspect actual backend endpoints and reuse them.

The app needs operations equivalent to:

```text
authenticate
upload recording
list recordings/sources
get recording detail
get processing state
get transcript/segments
get memories
get open loops
resolve/dismiss open loop
Ask
search
```

Match actual API contracts rather than inventing duplicates.

Small backward-compatible backend changes are authorized if needed.

Examples:

- idempotent upload
- protected audio endpoint
- bookmark payload
- native-friendly recording list
- timestamp segment payload
- processing-state endpoint

Keep the web app working.

---

# 16. API CLIENT

Build a typed API layer using `URLSession`, `Codable`, and `async/await`.

Centralize:

- base URL
- auth
- decoding
- error mapping
- uploads
- development logging

Do not log secrets or sensitive recording contents unnecessarily.

---

# 17. CONFIGURATION

Support at least:

```text
Development
Production
```

with configurable:

```text
API_BASE_URL
```

Use `.xcconfig` or another appropriate mechanism.

Do not commit production secrets.

---

# 18. AUTHENTICATION

Integrate with the existing Memory Garden auth model.

Use Keychain for tokens/password-equivalent secrets.

Required:

- login
- logout
- auth restoration
- expired-auth handling
- unauthorized-response handling

Do not invent a separate identity system unless the backend has none.

---

# 19. RECORDINGS LIST

Create a native list that includes local-only and server recordings where practical.

Example:

```text
Today

2:14 PM
Shop Conversation
38 min
✓ Ready

10:32 AM
Training Discussion
1 hr 14 min
✓ Ready

Yesterday

4:18 PM
Untitled Recording
27 min
⟳ Transcribing
```

Possible statuses:

```text
On Device
Queued
Uploading
Processing
Ready
Partial
Failed
```

Failed uploads must remain visible.

---

# 20. RECORDING DETAIL

Display:

- title
- date/time
- duration
- processing state
- native playback
- summary
- transcript
- memories
- open loops
- useful entities/topics
- bookmarks

The original audio is the authoritative source.

---

# 21. AUDIO PLAYBACK

Implement native playback using Apple frameworks.

Required:

- play
- pause
- seek
- current time
- duration
- scrubber
- jump to timestamp

Support local playback for local files and authenticated server playback/download for uploaded sources.

Do not load entire multi-hour audio files into memory.

---

# 22. TIMESTAMPED TRANSCRIPT

Consume timestamped transcript segments from the backend.

Model equivalent:

```text
TranscriptSegment
- id
- start
- end
- text
```

Example:

```text
00:00
We started by talking about...

02:14
Bill said the first cohort should...

04:31
We agreed the LMS should...
```

Tapping the timestamp must seek audio to that position.

---

# 23. EVIDENCE CITATIONS

AI-derived memories/open loops/answers should link to source evidence.

Example:

```text
Decision

The first lead-tech cohort should focus on experienced technicians.

Evidence
🎧 18:42
```

Tap `18:42`:

1. open the recording if needed
2. seek to 18:42
3. allow playback
4. show/highlight related transcript text where practical

This provenance behavior is a core differentiator.

---

# 24. ASK

Implement a native Ask interface using the existing backend RAG/Ask system.

Example:

```text
What did Bill say about the lead-tech program?
```

Render grounded answers plus tappable source citations.

Tapping a recording citation should open that recording and seek to the evidence timestamp.

Do not run the LLM directly from iPhone.

---

# 25. TODAY

Create a phone-appropriate Today screen.

Show at minimum:

## Open Loops

Allow resolve/dismiss where supported.

Each item should trace back to its recording/source/timestamp.

## Recent

Recently processed recordings/memories.

## Resurfaced

Use if backend already supports it.

Do not reproduce every web dashboard feature.

---

# 26. MORE / SETTINGS

Include:

- Account
- Server/API environment
- Upload queue
- Local storage
- Microphone permission
- App version/build
- diagnostics
- logout

Development builds may expose extra diagnostics.

Never display secret values.

---

# 27. PRIVACY / CONSENT UX

Recording must be obvious.

Provide a short first-run notice that the user is responsible for complying with applicable laws and workplace policies concerning recording.

Do not build geography-based legal logic into MVP.

Never disguise active recording.

---

# 28. INTERRUPTION HANDLING

Handle audio interruption and route change notifications.

If iOS pauses/stops the recording, tell the user.

Example:

```text
Recording interrupted by a phone call.
Tap Resume to continue.
```

Never fabricate continuity across gaps.

Persist interruption metadata where practical.

---

# 29. CRASH / TERMINATION RECOVERY

After a completed local recording exists:

- metadata survives termination
- audio survives
- relaunch discovers it
- pending upload resumes or is retryable

Do not claim unsupported continued recording after user force-quit.

Document platform limitations honestly.

---

# 30. OFFLINE UX

Offline capture must work.

Example:

```text
Recording saved on this iPhone.

Upload is waiting for a connection.
```

Restore network → retry/upload.

Network failure is recoverable and must never cause source loss.

---

# 31. PROCESSING STATUS

After upload, show meaningful backend progress such as:

```text
Uploaded
↓
Transcribing
↓
Analyzing
↓
Ready
```

Use actual backend states.

Polling is acceptable for MVP.

---

# 32. LONG RECORDINGS

Design for:

- 5 minutes
- 30 minutes
- 2 hours
- 4+ hours

Requirements:

- compressed audio
- durable local files
- large-file-safe upload
- progress/status
- retry
- efficient playback
- no entire-file-in-memory assumptions

The backend owns transcription chunking/merging.

---

# 33. PERMISSIONS

Handle microphone permission states:

```text
notDetermined
granted
denied
```

If denied, explain why access is needed and provide a route to iOS Settings.

Browsing/Ask should still work without microphone permission.

---

# 34. FIRST RUN

Keep onboarding short.

Suggested:

```text
Welcome to Memory Garden

Your iPhone can capture conversations and thoughts
and turn them into searchable memories.

[ Continue ]
```

Then request microphone permission when appropriate.

Do not create a long marketing tour.

---

# 35. DESIGN LANGUAGE

Native, calm, clean.

Prefer:

- system typography
- SF Symbols
- clear hierarchy
- generous spacing
- dark mode
- large recording controls
- accessibility

Avoid:

- dense dashboards
- tiny controls
- excessive gradients
- generic neon "AI" visuals

---

# 36. ACCESSIBILITY

At minimum:

- VoiceOver labels
- Dynamic Type
- large touch targets
- accessible recording controls
- non-color-only statuses
- semantic labels for progress/errors

---

# 37. CLIENT ARCHITECTURE

Use a clean structure without overengineering.

Example:

```text
MemoryGarden/
├── App/
├── Models/
├── Services/
│   ├── API/
│   ├── Audio/
│   ├── Upload/
│   ├── Auth/
│   └── Persistence/
├── Features/
│   ├── Today/
│   ├── Record/
│   ├── Recordings/
│   ├── RecordingDetail/
│   ├── Ask/
│   └── Settings/
├── Components/
├── Resources/
└── Utilities/
```

MVVM or equivalent observable-state organization is fine.

Do not create unnecessary architecture ceremony.

---

# 38. SWIFT CONCURRENCY

Use:

- `async/await`
- actors where shared mutable state needs protection
- `@MainActor` for UI state

Avoid callback-heavy networking.

Fix meaningful Swift concurrency warnings.

---

# 39. LOCAL FILE STORAGE

Use an application-controlled durable directory appropriate for unuploaded user recordings.

Do not use temporary storage.

Prefer UUID filenames:

```text
recordings/<uuid>.m4a
```

Do not rely on user-entered titles for filenames.

---

# 40. MOCK / PREVIEW SUPPORT

Create protocol-based abstractions or equivalent mocks for:

- API
- recording detail
- transcript
- Ask responses
- Today data

Provide SwiftUI previews for major screens where practical.

Mocking supports UI development/tests; it must not hide real integration failures.

---

# 41. TESTING

## Unit tests

Cover:

- recording state transitions
- elapsed duration logic
- API decoding
- status decoding
- timestamp seek calculations
- upload retry state
- idempotency
- bookmark creation
- local persistence
- auth persistence abstraction

## API integration tests

Where practical:

```text
authenticate
upload recording
read processing status
read transcript
Ask
```

## UI tests

At minimum:

```text
launch
navigate to Record
view Recordings
open sample recording
open Ask
```

Microphone behavior need not be fully automated in CI.

---

# 42. PHYSICAL DEVICE VALIDATION

Simulator-only success is insufficient for the recording path.

Validate on a physical iPhone if the environment permits:

1. microphone permission
2. active recording
3. background recording
4. lock-screen recording
5. foreground return
6. stop
7. file integrity
8. upload
9. processing
10. playback
11. timestamp seeking

If no physical device is available, do not falsely claim validation. Provide the exact remaining device checklist.

---

# 43. PRIMARY ACCEPTANCE TEST — POCKET EXPERIENCE

The MVP passes when this works:

1. Open complete Xcode project.
2. Build to physical iPhone.
3. Login.
4. Tap Record.
5. Record at least 10 minutes.
6. Tap Mark Moment.
7. Lock phone for part of recording.
8. Unlock.
9. Confirm session remains coherent.
10. Stop.
11. Recording appears immediately in Recordings.
12. Original file exists locally.
13. Network loss does not delete it.
14. Upload/retry succeeds.
15. Backend receives exactly one Source.
16. Processing reaches transcript/analysis.
17. Transcript appears.
18. Summary/memories/open loops appear.
19. Tap transcript timestamp → audio seeks correctly.
20. Tap AI evidence timestamp → audio seeks correctly.
21. Ask a question about the recording.
22. Receive grounded answer.
23. Tap citation → open correct recording at correct timestamp.

---

# 44. OFFLINE ACCEPTANCE TEST

1. Disable network.
2. Launch app.
3. Record 10+ minutes.
4. Stop.
5. Verify local queued state.
6. Force-close after file has persisted.
7. Reopen.
8. Recording still exists.
9. Restore network.
10. Upload succeeds.
11. No duplicate Source is created.

---

# 45. INTERRUPTION ACCEPTANCE TEST

Where practical:

1. Begin recording.
2. Trigger an audio interruption or route change.
3. App receives the state change.
4. UI accurately reflects what happened.
5. Resulting file remains valid.
6. Resume is possible where supported.

---

# 46. LARGE RECORDING ACCEPTANCE TEST

Use a sufficiently large recording to exercise real upload behavior.

Verify:

- UI stays responsive
- file is not loaded entirely into memory
- upload status is visible
- retry works
- server receives full file
- local file remains until confirmation
- playback works after processing

---

# 47. QUALITY GATES

Before completion:

- Xcode project opens without repair prompts
- project builds
- unit tests pass
- relevant UI tests pass
- required microphone usage description exists
- background audio mode is configured
- no secrets committed
- Keychain is used for auth secrets
- configurable server URL exists
- offline capture works architecturally
- upload retry works
- web app remains functional after backend changes
- command-line `xcodebuild` validation is run where possible

---

# 48. DOCUMENTATION

Create:

```text
apps/ios/README.md
```

Include:

- required Xcode version
- open/build instructions
- backend URL setup
- signing
- capabilities
- microphone permission
- background audio
- local storage
- upload/retry behavior
- device testing
- known limitations

Update root README to mention the native client.

---

# 49. KNOWN IOS LIMITATIONS

Document honestly:

- force-quitting terminates active recording
- iOS can interrupt audio for phone/system events
- background rules limit non-audio work
- simulator cannot fully validate physical audio behavior
- background upload behavior depends on correct URLSession configuration

Do not attempt to bypass iOS lifecycle/security restrictions.

---

# 50. FUTURE FEATURES — ARCHITECT FOR, DO NOT REQUIRE

Potential next phases:

```text
Apple Watch companion
App Intents
Action Button
Control Center
Live Activities
widgets
Siri
Share extension
photo capture
document scan
Bluetooth accessories
dedicated hardware recorder
push notifications
offline transcript caching
local STT fallback
```

Do not let these derail the native MVP.

---

# 51. OPTIONAL POST-MVP QUICK WIN

Only after the core acceptance flow is complete and stable:

If inexpensive, add an App Intent / Shortcut entry point that makes the future flow possible:

```text
Action Button
↓
Memory Garden
↓
Record
```

Do not compromise recording reliability for this.

---

# 52. PRODUCT PRINCIPLES

## Phone as capture appliance

A user should be comfortable pulling out the iPhone, tapping once, setting it down, and trusting that Memory Garden will preserve the conversation.

## Server as intelligence

Keep transcription, LLM processing, embeddings, retrieval, and memory extraction on the backend.

## Never lose the recording

When tradeoffs arise, prioritize:

1. preserve audio
2. preserve metadata
3. prevent duplicate upload
4. make failures visible
5. retry safely
6. optimize convenience afterward

A failed upload is acceptable.

A lost recording is not.

---

# 53. DEFINITION OF DONE

The iOS project is done when:

- complete Xcode project exists
- opens directly in Xcode
- SwiftUI app launches
- login works
- API configuration works
- microphone permission works
- recording works
- pause/resume works
- Mark Moment works
- correct background audio configuration exists
- local audio is durable
- pending recordings survive relaunch
- upload queue works
- retry works
- duplicate upload is prevented
- server processing status displays
- Recordings list works
- Recording Detail works
- playback works
- transcript segments display
- transcript timestamps seek audio
- evidence timestamps seek audio
- Today/open loops work
- Ask works
- Ask citations open evidence
- Keychain stores auth secrets
- offline capture works
- network failure is recoverable
- tests pass
- existing web client remains functional
- documentation is complete

If physical-device validation cannot be performed, state that clearly and provide the remaining physical-device validation checklist.

---

# 54. FINAL AGENT EXECUTION INSTRUCTION

Read this PRD completely.

Inspect the existing Memory Garden repository before writing code.

Determine the actual backend contracts.

Create the complete native Xcode project inside the existing repository.

Do not provide a tutorial instead of implementation.

Do not stop after scaffolding.

Do not ask for approval between phases.

Make routine decisions yourself.

Where small backend changes are needed, implement them without breaking the existing web client.

Build the project.

Run tests.

Repair failures.

Validate native/server contracts.

The desired final report is:

> The Memory Garden iOS project is complete and ready to open in Xcode. Here is the project path, required server/signing configuration, validated capabilities, test results, and any genuine physical-device validation still remaining.

The objective is to transform the already-working Memory Garden platform into a practical Pocket-style product where **the iPhone itself is the capture hardware**.

**Proceed autonomously until the native iOS MVP is operational.**
