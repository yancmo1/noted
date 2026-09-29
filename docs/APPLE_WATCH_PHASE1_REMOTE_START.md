# Phase 1 Remote-Start Feasibility Note

Status: **PENDING REAL-DEVICE TEST**

## Current evidence

- The installed watchOS SDK exposes the public `AudioRecordingIntent` protocol.
- Apple documents that adopting `AudioRecordingIntent` on watchOS requires an active Live Activity for the duration of recording; otherwise the recording stops.
- The current spike intentionally does not adopt that protocol. It has no iPhone recording intent, Live Activity, or claim that a Watch action can activate a locked/backgrounded iPhone microphone.
- The current Watch target now includes a WidgetKit complication. Its tap opens `noted-watch://capture` and presents a dedicated foreground Start screen. The complication reads a shared app-group snapshot for recorder state, while the visible Start button remains the microphone authorization boundary.
- The iPhone Record screen now offers an iPhone-first dual capture toggle. It starts the iPhone source locally, sends a reachable-only idempotent Watch start request with a shared `meetingID`, and reports partial success without invalidating the iPhone source. Stop requests preserve the Watch confirmation prompt and report the later completion acknowledgement.
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
