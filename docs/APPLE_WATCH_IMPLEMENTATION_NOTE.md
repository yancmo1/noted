# Noted Apple Watch Integration Note

This note records the Phase 1 integration boundary so the feasibility spike does not accidentally become a broad iPhone recorder rewrite.

## Current integration points

- `apps/ios/project.yml` defines the `Noted Watch Spike` watchOS target and embeds it in the `Noted` iOS application.
- `apps/ios/WatchConnectivity/WatchCaptureProtocol.swift` is compiled by both targets. It owns the versioned file manifest, marker payload, checksum helpers, transfer state, and durable acknowledgement payload.
- `apps/ios/WatchRecorder/WatchConnectivityCoordinator.swift` owns Watch-side `WCSession` activation, durable file/user-info queuing, acknowledgement parsing, and native transfer completion callbacks.
- `apps/ios/WatchRecorder/WatchSpikeRecorder.swift` owns the Watch spike lifecycle, local metadata, local audio retention, markers, interruption evidence, and transfer retry/reconciliation through the connectivity coordinator.
- `apps/ios/WatchComplication/NotedWatchComplication.swift` is the watchOS WidgetKit extension. It reads the shared Watch app-group snapshot and deep-links to `noted-watch://capture`.
- `apps/ios/WatchConnectivity/WatchComplicationState.swift` is the shared complication state store. The Watch recorder publishes ready, recording, transfer-pending, and attention states; WidgetKit reads the last durable snapshot in its independent process.
- `apps/ios/Noted/Services/WatchTransferReceiver.swift` owns the iPhone-side receipt boundary. `WatchTransferStore` copies the temporary `WCSession` file into Noted-owned Application Support storage, validates size/checksum, persists the manifest, supports idempotent retry, and exposes validated receipts for the existing local-recordings library.
- `WatchStartCaptureRequest` and `WatchStopCaptureRequest` in `WatchCaptureProtocol.swift` are immediate, reachable-only coordination messages. Their command IDs are persisted with Watch records so retries acknowledge the same source instead of creating another one.
- The Record screen can create an iPhone-first dual capture. The iPhone source starts and is saved locally first; a reachable Watch joins the same `meetingID` as an independent source. Watch start failures leave the iPhone source valid and visible. Watch stop requests preserve the existing Watch confirmation prompt and return a completion acknowledgement after local finalization.
- `apps/ios/Noted/App/NotedApp.swift` activates the iPhone receiver during application initialization.

## Deliberate Phase 1 boundary

The spike now imports a validated Watch receipt into the production `LocalRecordingStore` as a local, unsent recording. The first complication slice is also wired: a complication tap opens a dedicated Watch ready screen, and the visible Start button begins the local Watch recording. This is a foreground fallback; the complication does not claim to start microphone capture directly from the widget process.

The coordinated iPhone-first path now attaches the Watch source to the same meeting while keeping the two files independent. Direct Watch-first coordination, automatic server upload changes, and direct App Intent capture remain outside this slice. The complication and dual-device command path still require physical-device validation before they can be treated as supported remote start behavior.

The existing iPhone `AudioRecorder` remains the production iPhone recorder, with an optional meeting ID supplied by the coordination layer. The Record UI reports Watch start, stop-confirmation, unresolved, and completed states without merging the source files.

## Phase 2 handoff inputs

After the physical spikes, the next implementation should complete Watch-first coordination and decide how a meeting-level view should expose two independently playable sources. It should preserve explicit `meetingID`, `sourceID`, and sequence values and keep both sources in `Ready` state until existing processing preferences take over.

The current spike receiver directory remains a durable staging area, not a second user-facing Watch library. Validated entries are copied into the existing iPhone recordings directory and deduplicated by source ID; the staging copy remains available for acknowledgement reconciliation.
