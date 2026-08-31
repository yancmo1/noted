# Noted Apple Watch Integration Note

This note records the Phase 1 integration boundary so the feasibility spike does not accidentally become a broad iPhone recorder rewrite.

## Current integration points

- `apps/ios/project.yml` defines the `Noted Watch Spike` watchOS target and embeds it in the `Noted` iOS application.
- `apps/ios/WatchConnectivity/WatchCaptureProtocol.swift` is compiled by both targets. It owns the versioned file manifest, marker payload, checksum helpers, transfer state, and durable acknowledgement payload.
- `apps/ios/WatchRecorder/WatchConnectivityCoordinator.swift` owns Watch-side `WCSession` activation, durable file/user-info queuing, acknowledgement parsing, and native transfer completion callbacks.
- `apps/ios/WatchRecorder/WatchSpikeRecorder.swift` owns the Watch spike lifecycle, local metadata, local audio retention, markers, interruption evidence, and transfer retry/reconciliation through the connectivity coordinator.
- `apps/ios/Noted/Services/WatchTransferReceiver.swift` owns the iPhone-side receipt boundary. `WatchTransferStore` copies the temporary `WCSession` file into Noted-owned Application Support storage, validates size/checksum, persists the manifest, and supports idempotent retry.
- `apps/ios/Noted/App/NotedApp.swift` activates the iPhone receiver during application initialization.

## Deliberate Phase 1 boundary

The spike does not yet attach a Watch source to the production `LocalRecordingStore`, existing server upload flow, or a shared `MeetingCapture` model. Those changes depend on physical evidence for file recoverability, audio profile, transfer reliability, and remote-start feasibility.

The existing iPhone `AudioRecorder` remains the production iPhone recorder. No Watch-specific behavior is routed through its current UI or upload state in this phase.

## Phase 2 handoff inputs

After the physical spikes, the next implementation should use explicit `meetingID`, `sourceID`, and sequence values to attach Watch audio to the existing Noted library. It should preserve independent Watch and iPhone sources and keep both in `Ready` state until existing processing preferences take over.

The current spike receiver directory is intentionally a durable staging area, not a second user-facing Watch library. Its contents are the migration input for that ingestion work.
