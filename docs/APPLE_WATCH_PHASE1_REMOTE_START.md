# Phase 1 Remote-Start Feasibility Note

Status: **PENDING REAL-DEVICE TEST**

## Current evidence

- The installed watchOS SDK exposes the public `AudioRecordingIntent` protocol.
- Apple documents that adopting `AudioRecordingIntent` on watchOS requires an active Live Activity for the duration of recording; otherwise the recording stops.
- The current spike intentionally does not adopt that protocol. It has no iPhone recording intent, Live Activity, or claim that a Watch action can activate a locked/backgrounded iPhone microphone.
- Simulator launch and WatchConnectivity message behavior would not prove the locked-phone privacy path.

## Required physical experiment

1. Build a release/TestFlight-valid pair with the documented intent and Live Activity path, if implementation is attempted.
2. Lock the paired iPhone and leave Noted backgrounded.
3. Start from the Watch through the visible user action.
4. Verify that the Watch starts immediately, the iPhone starts through documented public APIs, both system recording indicators appear, and the behavior survives the release distribution path.
5. Record PASS or FAIL using the template in `APPLE_WATCH_PHASE1_SPRINT.md`.

## Fallback if the gate fails

Keep Watch-first recording independent and use iPhone-first dual capture: the iPhone creates and publishes a meeting, then the Watch joins that meeting before starting its independent source. Do not make Watch recording wait for a phone start acknowledgement.

References:

- https://developer.apple.com/documentation/appintents/audiorecordingintent
- https://developer.apple.com/documentation/xcode/configuring-background-execution-modes
