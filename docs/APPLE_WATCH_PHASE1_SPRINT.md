# Noted — Apple Watch Capture Phase 1 Sprint

Last updated: 2026-08-31

This is the living implementation todo for Phase 1 of the Apple Watch Recorder + Dual-Source Capture plan. Keep it updated as work moves from code preparation to physical-device evidence. Phase 1 is a feasibility gate; it is not complete based on Simulator behavior or a successful build alone.

## Sprint objective

Prove the smallest reliable Watch recording and Watch-to-iPhone handoff path on paired physical devices, and document whether Watch-initiated iPhone recording is permitted by current public APIs. Use the evidence to choose the Phase 2 storage and coordination architecture.

## Current status

- Repository audit: complete.
- Physical test inventory: complete.
- Watch target and spike harness: complete for simulator and generic physical-device builds; the current TestFlight build is installed on the paired iPhone and Watch, with physical recorder startup now under investigation.
- Simulator runtime smoke: Watch spike and embedded iPhone host both install and launch successfully on the watchOS/iOS 27 simulators.
- Structured spike evidence: implemented for timing, format, file size, checksum, marks, transfer state, battery snapshots, route snapshots, and interruption reason.
- Timing safeguard: active elapsed time and marker offsets use monotonic system uptime when available, avoiding wall-clock changes during a recording.
- Local capture safeguards: implemented low-storage/low-battery warnings, critical-storage finalization, empty-file transfer rejection, protocol-version validation, serialized receiver ingestion, repair of a corrupted durable copy on a verified retry, revalidation before acknowledgement reissue, explicit recorder lifecycle plus native-transfer failure versus durable-acknowledgement states, relaunch-time acknowledgement status reconciliation, a backup Watch record index, recovery of unindexed retained audio files, and a dedicated Watch connectivity coordinator.
- Watch history: implemented timestamped entries with retry and explicitly confirmed delete; deleting an unacknowledged item shows “This recording has not been copied to your iPhone.” and retains metadata/audio if persistence or cleanup fails.
- Watch audio background mode: declared in the spike target; real wrist-down/background behavior remains a physical test.
- Recovery rule: documented and implemented at the spike boundary; incomplete local files become visible interrupted/failed records, retained audio is retryable, and Watch audio is deleted only after a persisted durable acknowledgement. Single-file versus segmented architecture remains a physical-test decision.
- Latest verification: 21 iPhone unit tests and 1 iPhone UI launch test pass under the shared `Noted` scheme; the generic physical-watch build passes after the timestamped Watch-history change, the watchOS Simulator build/install/launch passes, and the signed iPhone device build/install passes. With both physical devices available again, `yPhone` reports unlocked since boot and `xcrun devicectl` launched Noted successfully. A local development-signed Watch build still fails before install because the Watch UDID is not registered; the Xcode Cloud/TestFlight path uses distribution signing and is tracked separately.
- Remote-start API investigation: the installed watchOS SDK exposes `AudioRecordingIntent`; adopting it still requires the real-device Live Activity/recording-indicator gate, so no unsupported remote-start behavior has been added to the spike.
- Remote-start fallback: prepared and documented as iPhone-first dual capture with an explicit `meetingID`; Watch-first capture remains independent if the phone cannot be legally remote-started.
- Latest CoreDevice recheck: the paired Series 11 and `yPhone` are both available and paired; the older paired Series 9 remains unavailable. The iPhone lock-state query reports unlocked since boot, and a connected Noted launch succeeded. Pairing metadata is present, but no physical Watch behavior or transfer result is inferred because Watch provisioning still blocks installation.
- Integration note: [APPLE_WATCH_IMPLEMENTATION_NOTE.md](APPLE_WATCH_IMPLEMENTATION_NOTE.md).
- Remote-start note: [APPLE_WATCH_PHASE1_REMOTE_START.md](APPLE_WATCH_PHASE1_REMOTE_START.md).
- Xcode Cloud/TestFlight setup: [APPLE_WATCH_XCODE_CLOUD.md](APPLE_WATCH_XCODE_CLOUD.md).
- Xcode Cloud validation: the checked-in project now passes post-clone target/scheme validation, the stable-runner guard rejects the local beta Xcode, the post-archive check verifies the embedded Watch app, and an unsigned Release archive contains it. The Watch target now also has aligned `1.0` marketing-version metadata, a compiled `AppIcon` catalog, and explicit icon plist entries; standalone Watch and embedded iOS archive checks pass locally. The current Cloud/TestFlight distribution has installed on both paired devices; the replacement audio fix is the next Cloud build.
- Physical TestFlight smoke: the latest Cloud/TestFlight build installed on both the paired iPhone and Apple Watch. Launch succeeds, but starting a Watch recording reports `OSStatus error -50`; this is a physical audio-session/recorder startup failure, not an install or Watch embedding failure.
- Current local processing path: the MacBook at `100.122.189.114` runs the Noted API and Ollama under restart-safe launch agents. The API is reachable on port `3333`, Ollama is healthy on its local port, and Whisper remains an on-demand local transcription binary rather than a permanent network listener. `ubuntumac` is not part of the current Noted path.
- Physical-device evidence: the iPhone and Watch TestFlight installation path is verified. The first physical Watch recording attempt fails at audio startup with `OSStatus error -50`; the next build uses asynchronous audio-session activation, defaults to the documented 16 kHz speech profile, and falls back to 16 kHz if a selected higher-rate profile is rejected.
- Current architectural decision: pending the spikes below.

## Baseline captured during audit

- Live repository: `/Users/yancyshepherd/Projects/noted`
- Existing iPhone deployment target: iOS 17.0.
- Existing iPhone recorder: `AVAudioRecorder`, AAC/M4A, mono, 44.1 kHz, 64 kbps.
- Existing iPhone local durability: Application Support with an atomic recording index and backup; interrupted drafts are surfaced for recovery.
- Existing iPhone transfer safety: native recording UUIDs make server retries idempotent, but this is an iPhone-to-server path, not the required Watch `transferFile` plus application-level durable acknowledgement path.
- Existing Watch integration: no Watch target, `WCSession` coordinator, shared capture model, or Watch complication found.
- Available physical devices at the initial audit on 2026-08-31: Apple Watch Series 11 (paired and available) and iPhone 17 Pro Max (paired and available). A second listed Apple Watch was unavailable. The later CoreDevice recheck recorded the Series 11 as disconnected and `yPhone` as paired but disconnected; this is the current transport state.
- Existing device validation notes already mark iPhone microphone, lock-screen/background, interruption, and network recovery checks as pending.

## Work queue

### A. Spike harness and instrumentation

- [x] **A1 — Add the minimal Watch spike target.**
  - Add only the target/configuration needed to run a recorder spike on the available paired Watch.
  - Keep production UI and the Phase 2 shared model out of this spike unless the test requires them.
  - Use public APIs only and preserve the existing iPhone target.
- [x] **A2 — Add structured spike evidence capture.**
  - Record device model, OS/build, codec settings, start/end timestamps, duration, file size, battery start/end, interruption reason, route, checksum, and transfer/ack state.
  - Do not record audio content or transcript text in logs.
- [x] **A3 — Add a repeatable evidence note template.**
  - Each result must state PASS/FAIL, exact device/build, steps, observed behavior, and the architecture decision it affects.

### B. Independent Watch recording

- [ ] **B1 — Background and wrist-down recording.**
  - Verify recording continues with the display asleep, wrist down, and the app no longer visually foregrounded where watchOS permits.
  - Repeat with iPhone nearby, out of Bluetooth range, powered off, and Watch Wi-Fi only where practical.
- [ ] **B2 — Endurance path.**
  - Run a shorter endurance test first, then the required four-hour continuous test.
  - Capture battery, file size, temperature/thermal observations, interruptions, and whether the file is playable after stop.
- [ ] **B3 — Permission and route behavior.**
  - Verify first-run microphone permission behavior and document the actual microphone route for nearby phone, remote phone, and connected Bluetooth audio.

### C. Audio profile decision

- [ ] **C1 — Compare the three required candidate profiles.**
  - 16 kHz / approximately 32 kbps AAC-LC mono M4A.
  - 24 kHz / approximately 48 kbps AAC-LC mono M4A.
  - 32 kHz / approximately 64 kbps AAC-LC mono M4A.
- [ ] **C2 — Run the real-room speech comparison.**
  - Compare speaking beside the iPhone, from the rear of a large room, near the Watch, and during normal movement.
  - Record intelligibility and later STT suitability, not music-quality impressions.
- [ ] **C3 — Select the lowest-cost adequate profile.**
  - Decision must include speech quality, file size, battery cost, CPU/thermal behavior, and four-hour feasibility.

### D. Crash and power-loss resilience

- [ ] **D1 — Test single-file recoverability.**
  - Test forced app termination, unexpected recorder interruption, and Watch shutdown/battery exhaustion where practical.
  - Verify whether the interrupted M4A remains recoverable without the normal `stop()` path.
- [ ] **D2 — Decide single-file versus segmented storage.**
  - If one file is not reliably recoverable, prototype 5–10 minute segments and measure boundary loss.
  - Keep segments hidden from the user and preserve one logical recording identity.
- [x] **D3 — Document the recovery rule.**
  - No captured audio may disappear silently, and relaunch must recover metadata for any retained audio.

### E. Physical Watch-to-iPhone transfer and durable acknowledgement

- [ ] **E1 — Prove physical `WCSession.transferFile`.**
  - Transfer a finalized Watch recording from the paired Watch to the paired iPhone under normal conditions, with the iPhone locked/backgrounded where supported.
  - Test delayed connectivity, Bluetooth/Wi-Fi toggles, Watch app relaunch, and retry.
- [x] **E2 — Implement or prototype the receiver durability boundary.**
  - Move/copy the received temporary file into Noted-owned durable storage before returning from the delegate callback.
  - Validate expected byte size and SHA-256 checksum.
- [ ] **E3 — Prove application-level acknowledgement.**
  - iPhone sends `durableAck` only after durable ingestion and stable metadata persistence.
  - Watch retains audio until that acknowledgement; lost acknowledgements must not cause early deletion.
- [ ] **E4 — Prove idempotent retry.**
  - Re-delivery of the same source/segment/checksum must acknowledge the existing copy without creating duplicate library content.

### F. Dual-source remote-start feasibility gate

- [ ] **F1 — Test the ideal Watch-initiated path on real devices.**
  - Investigate only documented public APIs, including `AudioRecordingIntent` and required system recording/Live Activity mechanisms where applicable.
  - Test with the iPhone locked/backgrounded and verify visible system recording indicators and TestFlight/release viability.
- [ ] **F2 — Record a hard PASS/FAIL with evidence.**
  - Do not infer feasibility from Simulator behavior or from a message reaching the iPhone.
- [x] **F3 — Prepare the required fallback if remote start fails.**
  - iPhone-first: iPhone creates `meetingID`, Watch discovers the active meeting, and Watch starts its independent source.
  - Watch-first remains reliable and may remain Watch-only until the iPhone explicitly joins.

### G. Phase 1 exit gate

- [ ] **G1 — Publish the spike results.**
  - Update the result tables below and add the supporting evidence notes.
- [ ] **G2 — Resolve architecture inputs for Phase 2.**
  - Final audio profile.
  - Single-file or segmented Watch storage.
  - Transfer/ack retry behavior.
  - Remote-start path or iPhone-first fallback.
- [ ] **G3 — Confirm no data-loss acceptance failure.**
  - No silent deletion, deletion before durable acknowledgement, duplicate transfer entry, orphaned audio, or Watch waiting on iPhone before recording.

### H. Noted distribution packaging

- [x] **H1 — Rename the iOS product and Xcode project to Noted.**
  - The project, app target, source/test modules, shared archive scheme, generated products, and Cloud scripts now use `Noted`.
  - The App Store bundle ID remains `com.shepswork.noted` so App Store Connect treats this as an update to the existing app.
- [x] **H2 — Embed the Noted Watch Spike in the iPhone archive.**
  - The `Noted` target depends on `Noted Watch Spike` and includes an `Embed Watch Content` phase; the unsigned Release archive contains `Noted.app/Watch/Noted Watch Spike.app`.
- [x] **H3 — Run the stable Xcode Cloud Archive and install through TestFlight.**
  - Requires the repository commit on the connected branch, App Store Connect identifiers/signing, and a stable non-beta Xcode Cloud runner.

## Evidence note template

Copy this block for each physical-device run and replace every placeholder:

```text
Result: PASS / FAIL / BLOCKED
Spike: <background | endurance | codec | recovery | transfer | acknowledgement | remote start>
Date/time: <local timestamp and timezone>
Watch: <model, watchOS version/build, app build>
iPhone: <model, iOS version/build, app build>
Setup: <pairing, network, Bluetooth/Wi-Fi, lock/background state>
Steps: <numbered actions>
Observed: <behavior, duration, file size, battery, route, interruptions, checksum, transfer state>
Failure or limitation: <none, or exact failure>
Architecture decision: <what this result changes for Phase 2>
Evidence location: <log, screenshot, or test note path>
```

## Evidence register

| Spike | Result | Evidence | Decision |
|---|---|---|---|
| Watch background / wrist-down | Pending | — | — |
| Four-hour endurance | Pending | — | — |
| Codec comparison | Pending | — | — |
| Interrupted-file recoverability | Pending | — | — |
| Physical `transferFile` | Pending | — | — |
| Durable acknowledgement | Pending | — | — |
| Dual-source remote start | Pending | `docs/APPLE_WATCH_PHASE1_REMOTE_START.md` | Real-device locked-phone test still required |
| TestFlight Watch recorder startup | FAIL | Physical TestFlight install; Watch displays `OSStatus error -50` when recording starts | Replace the audio-session/recorder startup path before transfer and endurance testing |

## Code-level recovery rule

This spike keeps one local M4A file per Watch source while the physical recoverability experiment is pending. The persisted record is created before recording starts and is checkpointed during recording. On relaunch:

- an unfinished local file is marked `interrupted` and remains visible for retry;
- a missing file is marked `failed` rather than silently removed;
- a pending transfer with no outstanding WatchConnectivity transfer is requeued;
- a matching durable acknowledgement may be reissued only after the iPhone revalidates the stored manifest and audio checksum;
- acknowledged Watch audio is removed only after the acknowledgement state is persisted, with cleanup retried on a later launch if needed.

This rule does not decide whether WatchOS requires segmentation; that remains the result of the physical interruption and power-loss tests.

## Implementation log

- 2026-08-31 — Added the `Noted Watch Spike` watchOS target, a minimal AVAudioRecorder-based recorder with the three candidate profiles, persistent local records/checksums, Mark support, stop confirmation, and retry/acknowledgement state.
- 2026-08-31 — Extended spike records with device/OS, battery, audio-route, and interruption evidence fields; existing records remain decodable when those fields are absent.
- 2026-08-31 — Added the iPhone `WatchTransferReceiver`. It moves received files into Noted-owned Application Support storage, validates size and SHA-256, persists the manifest, and sends an application-level durable acknowledgement. Duplicate matching deliveries are acknowledged without rewriting the stored copy.
- 2026-08-31 — Added Watch relaunch reconciliation against `WCSession.outstandingFileTransfers`; a pending local source with no outstanding transfer is safely requeued, allowing acknowledgement-loss recovery without deleting the Watch copy.
- 2026-08-31 — Simulator build passed for the Watch spike target. Simulator success does not advance the physical-device evidence rows above.
- 2026-08-31 — Rebuilt the Watch spike after adding battery, route, and interruption capture; watchOS Simulator build passed.
- 2026-08-31 — Generic watchOS device build and embedded iOS Simulator build both passed after instrumentation changes; only the expected AppIntents metadata-skipped warning remains because the spike has no AppIntents dependency.
- 2026-08-31 — Runtime smoke passed: the Watch spike launched on the DEMO Apple Watch Series 11 simulator and the Noted host launched on the DEMO iPhone 17 Pro simulator. This remains non-physical evidence.
- 2026-08-31 — Rebuilt the hardened Watch spike for watchOS Simulator, installed/launched it on the DEMO Apple Watch Series 11 simulator, and installed/launched the hardened Noted host on the DEMO iPhone 17 Pro simulator. This remains non-physical evidence.
- 2026-08-31 — Declared the Watch audio background mode required for the background-session spike; this does not substitute for a wrist-down or watch-face physical run.
- 2026-08-31 — iPhone unit tests passed: 15 tests, 0 failures, including manifest/acknowledgement/checksum protocol coverage and idempotent receiver-store coverage.
- 2026-08-31 — After recovery hardening, iPhone unit tests passed: 17 tests, 0 failures, including unsupported-protocol rejection and corrupted-destination repair on retry; the Watch target also rebuilt successfully for generic physical watchOS.
- 2026-08-31 — Signed Noted iPhone device build and install passed. Launch was refused because the phone was locked.
- 2026-08-31 — Rebuilt and reinstalled the current signed Noted iPhone build successfully; launch remains blocked by the phone’s locked state, so the receiver has not been activated on hardware.
- 2026-08-31 — Rebuilt and reinstalled the hardened signed Noted iPhone build successfully; the launch attempt again returned the explicit CoreDevice `Locked` denial. No hardware receiver result is inferred.
- 2026-08-31 — Final local smoke after launch-reconciliation hardening: the Watch spike and Noted host both rebuilt, installed, and launched successfully on the DEMO watchOS/iOS 27 simulator pair. This remains non-physical evidence.
- 2026-08-31 — Watch physical build/install is blocked by provisioning: the paired Watch is not registered in the active developer account, so its Watch provisioning profile cannot be installed. No Watch recording result has been inferred from the build.
- 2026-08-31 — A current Watch install retry did not reach provisioning validation because CoreDevice timed out establishing the Watch network tunnel. The earlier provisioning-profile failure remains the registration blocker once device transport is available.
- 2026-08-31 — A signed Watch build with `-allowProvisioningUpdates` also timed out waiting for the Watch destination; Xcode reported that the paired Watch connection could not be established before provisioning could run.
- 2026-08-31 — Added WatchConnectivity transfer completion handling: native transfer failure is persisted as retryable while successful delivery remains `awaitingAck` until the iPhone’s durable acknowledgement arrives; relaunch reconciliation also requeues interrupted native transfers.
- 2026-08-31 — Transfer-state hardening verification passed: 17 iPhone tests and the generic physical-watch build both succeeded after adding native transfer completion handling.
- 2026-08-31 — Final transfer-state simulator smoke passed: the hardened Watch spike rebuilt, installed, and launched on the DEMO Apple Watch Series 11 simulator.
- 2026-08-31 — Added a persisted Watch recorder lifecycle phase (`preparing` through `finalizing`, transfer wait, interruption, and failure) alongside the transfer state; the stop-confirmation cancel path now restores the recording phase.
- 2026-08-31 — Lifecycle-state verification passed: 17 iPhone tests, generic physical-watch build, and watchOS Simulator build all succeeded; the current Watch app installed and launched on the DEMO Apple Watch Series 11 simulator.
- 2026-08-31 — Replaced silent Watch metadata checkpoint failures with surfaced, audio-retaining persistence errors and added missing-file reconciliation for the `transferring` state; 17 iPhone tests and the generic physical-watch build passed afterward.
- 2026-08-31 — Added a durable Watch acknowledgement-status request: on relaunch the Watch asks whether iPhone already has a matching checksum before requeuing, and the receiver re-acks the stored manifest without duplicating audio.
- 2026-08-31 — Acknowledgement-reconciliation verification passed: 18 iPhone tests and the generic physical-watch build succeeded after adding the status-request protocol and receiver re-ack path.
- 2026-08-31 — Hardened acknowledgement reissue so iPhone re-acks only after validating both the stored manifest and durable audio bytes; added corruption regression coverage.
- 2026-08-31 — Documented and checked off the code-level recovery rule; physical interrupted-M4A recoverability and the single-file/segmented decision remain pending evidence.
- 2026-08-31 — Added the integration and remote-start feasibility notes so Phase 2 does not begin before the physical evidence resolves the storage, transfer, and locked-phone coordination questions.
- 2026-08-31 — CoreDevice recheck: pairing metadata remains present, but the Series 11 is disconnected, the Series 9 is unavailable, and `yPhone` is disconnected. Pairings management exposes list/pair/set-active/unpair only; no safe reconnect action was available, so no repeated physical install was attempted. The lock-state query reports `yPhone` as unlocked since boot, but that does not establish a launch or receiver result while transport is disconnected.
- 2026-08-31 — Physical transport recovered: CoreDevice reports the Series 11 and `yPhone` available and paired; the iPhone lock-state query reports unlocked since boot, and `xcrun devicectl` launched Noted successfully. This verifies the connected iPhone prerequisite, not Watch recording or transfer behavior.
- 2026-08-31 — Captured the physical iPhone prerequisite result: Noted is installed and a connected launch succeeded on `yPhone`; raw CoreDevice results are retained at `/tmp/noted-phase1-iphone-launch-current.json` and `/tmp/noted-phase1-iphone-app-current.json`.
- 2026-08-31 — Physical Watch build retry reached provisioning validation and failed because Watch UDID `00008310-001042C614F0E01E` is not registered in the active developer account; the resulting profile also excludes that device. No Watch install or runtime result is inferred.
- 2026-08-31 — Local provisioning-profile inventory contains no profile that includes Watch UDID `00008310-001042C614F0E01E`; a developer-account registration/profile refresh is required before another signed install attempt can succeed.
- 2026-08-31 — Registration recheck: both physical devices remain available and paired, but the signed Watch build still fails at provisioning with the same unregistered UDID/profile-exclusion errors. No install retry was attempted beyond this definitive validation.
- 2026-08-31 — Hardened Watch metadata durability with a backup index and relaunch scanning for retained, unindexed `.m4a` files; recovered files become visible interrupted records with checksum, size, inferred format, and retryable status. Generic watchOS build and 18 iPhone tests passed afterward.
- 2026-08-31 — Rebuilt, installed, and launched the orphan-recovery Watch spike on the DEMO Apple Watch Series 11 simulator. This remains non-physical evidence.
- 2026-08-31 — Isolated WatchConnectivity session activation, file transfer, user-info queuing, acknowledgement parsing, and native transfer completion behind `WatchConnectivityCoordinator`; regenerated the Xcode project and verified the Watch target plus 18 iPhone tests.
- 2026-08-31 — Rebuilt and installed the coordinator-backed Watch spike on the DEMO Apple Watch Series 11 simulator. The first launch request hit a transient scene-update denial; a follow-up launch returned the running process and simulator logs showed the app active. This remains non-physical evidence.
- 2026-08-31 — Added Watch-side connectivity reactivation ownership only where the watchOS SDK permits it; watchOS generic build and 18 iPhone tests pass after the correction. The iPhone-side receiver continues to handle its available inactive/deactivate callbacks.
- 2026-08-31 — Tightened transfer-protocol validation for nonempty manifests, valid checksum shape, nonnegative sequences, positive audio format fields, and durable-copy revalidation; Watch acknowledgement application now checks sequence identity. Added regression coverage; 19 iPhone tests and the generic Watch build pass.
- 2026-08-31 — Verified the generated project against the generic physical iOS SDK: the signed iPhone app, embedded Watch app, and receiver all build successfully without signing; physical install/launch remains transport-gated.
- 2026-08-31 — Added receiver-boundary coverage proving an empty Watch payload is rejected before a durable copy is created; 20 iPhone tests and the generic Watch build pass.
- 2026-08-31 — Added outbound-control-payload validation for acknowledgements and status requests, with regression coverage for invalid sequence/checksum values; 21 iPhone tests and the generic Watch build pass.
- 2026-08-31 — Hardened elapsed-duration and marker-offset capture to use monotonic Watch uptime when available; the generic watchOS build and all 21 iPhone tests passed afterward.
- 2026-08-31 — Confirmed the remote-start fallback is prepared in `APPLE_WATCH_PHASE1_REMOTE_START.md`: iPhone-first creates and publishes the meeting identity, then Watch records its independent source; Watch-first never waits on phone availability. Runtime association remains Phase 2 work after the physical gate.
- 2026-08-31 — Added the required confirmed Watch-history Delete action, including the unacknowledged-copy warning and rollback when metadata persistence or audio cleanup fails.
- 2026-08-31 — Watch-history Delete verification passed: generic physical-watch build succeeded and all 21 iPhone tests remained green; the existing AppIntents metadata-skipped warning and unrelated ShareExtension await warnings remain non-blocking.
- 2026-08-31 — Watch-history Delete simulator smoke passed: the updated Watch spike built, installed, and launched on the DEMO Apple Watch Series 11 simulator. This remains non-physical evidence.
- 2026-08-31 — Added the recording time to each Watch-history entry; the generic Watch target remains the compile gate for this minimal UI.
- 2026-08-31 — Timestamped Watch-history verification passed: the generic watchOS target built successfully after the UI update; the expected AppIntents metadata-skipped warning remains non-blocking.
- 2026-08-31 — Prepared stable Xcode Cloud/TestFlight distribution support: versioned iPhone bundle metadata, Xcode Cloud beta-runner/archive-scheme guards, checked-in project validation, and the App Store Connect setup note are now tracked. Physical Watch evidence remains pending until the Cloud-signed build is installed.
- 2026-08-31 — Added and locally exercised the Xcode Cloud post-archive check; it verifies `Noted.app/Watch/Noted Watch Spike.app` exists before a successful Cloud archive is treated as distribution-ready.
- 2026-08-31 — Full shared-scheme Cloud-style test action passed: 21 unit tests and 1 UI launch test passed on the iOS Simulator; the simulator accessibility duplicate warning is from the installed runtime and is unrelated to the app.
- 2026-08-31 — Renamed the iOS project, app target, source/test modules, shared archive scheme, generated app product, Cloud manifest, Cloud scripts, and distribution docs from MemoryGarden to Noted. Compatibility identifiers for the existing App Store app, App Group, local recording folder, and Keychain service remain unchanged.
- 2026-08-31 — Renamed-project verification passed: 22 simulator tests passed (21 unit tests plus the UI launch test), the generic `Noted Watch Spike` build passed, and an unsigned Release archive passed the Cloud post-archive check with `Noted.app/Watch/Noted Watch Spike.app` present. App Store Connect/TestFlight execution remains pending.
- 2026-08-31 — Xcode Cloud recovery: removed the checked-in manifest binding to deleted product `a9b9067e-...`; the project now has no stale product ID and is ready for fresh Cloud product discovery. The fix must be pushed before retrying setup.
- 2026-08-31 — Diagnosed the failed Cloud export: archive compilation passed, but export could not authenticate the Cloud session with App Store Connect and could not find profiles for the iPhone, Watch, or Share Extension identifiers.
- 2026-08-31 — Registered the missing explicit Watch App ID `com.shepswork.noted.watchkitapp` as `Noted Watch Spike` in the active Apple Developer account, then started a clean Xcode Cloud rebuild (Build 4) to re-test managed signing. Cloud completion remains pending verification.
- 2026-08-31 — Removed the two stale `iPhone Developer` identities from the iOS Release configurations and fixed the two unnecessary `await` warnings in ShareExtension. The local focused ShareExtension build is warning-free.
- 2026-08-31 — Added restart-safe MacBook launch agents for Ollama supervision and the local Noted API, with logs under `~/Library/Logs/Noted`. Verified Ollama health, API health at `100.122.189.114:3333`, real local LLM mode using `gpt-oss:20b`, and configured Groq transcription status.
- 2026-08-31 — App Store Connect rejected Build 5 because the Watch bundle still declared version `0.1` and had no icon metadata. Aligned the Watch and iPhone marketing version at `1.0`, added the Watch `AppIcon` catalog plus explicit icon plist entries, and verified both the standalone Watch build and embedded iOS archive locally. The replacement Cloud build is pending.
- 2026-08-31 — The Cloud/TestFlight build installed on the paired iPhone and Watch, but physical Watch recording startup reported `OSStatus error -50`. Updated Watch audio startup to use asynchronous session activation, default to the documented 16 kHz speech profile, and fall back to 16 kHz when a selected profile is rejected; standalone Watch build and embedded iOS archive both pass locally.

## Current blockers

- **Xcode Cloud/TestFlight export:** the `Noted by Shepswork` app record, workflow, stable `Latest Release` runner, shared `Noted` archive scheme, and all three identifiers are in place. The Watch version/icon rejection is fixed, the current Cloud/TestFlight build installed on both devices, and the next gate is a new managed-signing export containing the Watch audio startup fix.
- **Cloud account session:** Build 5 compiled and exported all distribution variants with managed profiles, but the App Store Connect preparation step could not authenticate the Xcode Cloud session, so TestFlight did not run. If the replacement build repeats that failure, the remaining recovery step is in App Store Connect/Xcode Cloud account access rather than the app source.
- **Future processing host:** `ubuntumac` (`100.105.31.42`) is intentionally out of scope for this sprint. Revisit it only after the MacBook/TestFlight path is installed and validated.
- **Local development install (optional):** the direct signed Watch build still requires registering Watch UDID `00008310-001042C614F0E01E` and regenerating the development profile. This is not required for a TestFlight distribution build.
- **Physical acceptance:** the next Cloud-signed build must clear the Watch recorder startup error before receiver/transfer flows can be tested. Permission prompts, wrist-down/background behavior, battery use, thermal behavior, audio-route behavior, and the full Phase 1 matrix still require hands-on physical testing.

## Explicit Phase 1 non-goals

- No polished Watch UI beyond what the spike needs.
- No Watch transcription, AI, cloud upload, waveform, or transcript display.
- No automatic audio merging or speaker diarization.
- No broad rewrite of the working iPhone recorder.

## Update rule

When a task changes state, update its checkbox, the Current status section, the Evidence register, and the relevant decision. Keep failed platform experiments visible; a documented limitation is a valid Phase 1 result.
