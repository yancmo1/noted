# Noted roadmap

This is the current working roadmap. It is not a product requirement. Implemented code and the current product documents take precedence over this list.

## Completed

- Local Whisper transcription with Apple Silicon and Metal acceleration.
- The macOS Noted Transcriber app.
- Common audio and video import.
- Drag-and-drop and file-picker workflows.
- Editable timestamped transcripts.
- Reviewed Mac-to-Cloudflare transcript handoff.
- iOS local-first capture, upload retry, playback, and evidence seeking.
- Meeting brief fields for summary, key points, decisions, action items, follow-ups, unresolved questions, and calendar candidates.
- Apple Watch capture spike and iPhone import path, with remaining physical validation recorded in the Watch notes.

## Next meeting workflow

- Add a durable Meeting mode with title, start time, elapsed time, and a clear active state.
- Add timestamped scratch notes and Mark Moment entries.
- Join the reviewed Mac transcript to the active meeting session.
- Combine transcript, scratch notes, and markers during analysis.
- Show explicit recording, transcription, analysis, send, and retry states.

## Next finished-meeting experience

- Build a meeting view for overview, notes, transcript, and Ask.
- Keep raw transcript and user notes separate from generated output.
- Add source tracing for every generated claim.
- Add scoped Ask for one meeting.
- Add direct actions such as summary, action items, decisions, and follow-up email.

## Later work

- Full-text search across transcripts, notes, and generated memories.
- Recurring-meeting grouping and optional calendar context.
- An opt-in recordings-folder watcher.
- A reviewed-send preference.
- Phone handoff through AirDrop or Files, followed by a private Tailscale option if needed.
- Additional integrations only after the personal workflow proves their value.

## Explicit boundaries

- Do not expose the Mac or Whisper service to the public internet.
- Do not upload raw audio or video by default in the local-first workflow.
- Do not add team accounts, billing, or enterprise integrations as part of this roadmap.
- Do not treat the archived PRDs as current requirements.

## Apple Watch validation

The Apple Watch notes remain active technical evidence for the current spike. Check `docs/APPLE_WATCH_PHASE1_SPRINT.md` before treating physical-device support as complete. Simulator results do not close the physical acceptance gates.
