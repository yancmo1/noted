# Noted — Granola-inspired task list

This is the working backlog for turning Noted into a focused, local-first meeting memory tool. The order favors the workflow we can use immediately and postpones enterprise features.

## Complete

- [x] Install and verify local whisper.cpp with Apple Silicon/Metal acceleration.
- [x] Add the native macOS Noted Transcriber app.
- [x] Accept common audio and video recordings, not just OBS output.
- [x] Support drag-and-drop and a native file chooser.
- [x] Preserve the original recording on the Mac.
- [x] Generate an editable transcript with timestamped segments.
- [x] Add a text-only, authenticated Mac → Cloudflare handoff.
- [x] Show the sent transcript in the Cloudflare-hosted Noted webpage.

## Next: meeting workflow (P0)

- [ ] **Start Meeting mode** — title, start time, elapsed timer, and unmistakable “Meeting in progress” state.
  - Acceptance: a meeting session survives a page refresh and can be ended cleanly.
- [ ] **Timestamped scratchpad** — every note stores its relative meeting timestamp and original creation time.
  - Acceptance: editing a note never changes its original meeting timestamp.
- [ ] **Mark Moment ⭐** — one-click marker with optional text added afterward.
  - Acceptance: a marker appears immediately and is included in the finished meeting record.
- [ ] **End Meeting flow** — freeze timer, preserve notes/markers, and prompt for the OBS recording.
- [ ] **OBS safety checklist** — remind the user to start OBS, verify both audio meters, and confirm recording was stopped.
- [ ] **Join local transcript to meeting session** — the Mac transcript should attach to the open meeting rather than appear as an unrelated recording.
- [ ] **Combine transcript + scratch notes + markers** in the analysis prompt, with user notes treated as high-priority context.

## Next: finished meeting experience (P0/P1)

- [ ] Build the four-part meeting view: **Overview · My Notes · Transcript · Ask**.
- [ ] Preserve the raw transcript and original notes as separate source material; generated notes never replace them.
- [ ] Improve structured output: summary, key points, decisions, action items, follow-ups, and “my important moments.”
- [ ] Add explicit processing states and retry actions for recording, transcription, analysis, and send failures.
- [ ] Persist remote-send status and source ID locally so a restart cannot make a successful send look unsent.

## Trust and usefulness features (P1)

- [ ] **Source tracing** — every generated bullet can show the supporting transcript segment and jump to its timestamp.
- [ ] **Ask this meeting** — scoped questions grounded in the meeting transcript, notes, and markers.
- [ ] **Actions** — one-tap commands such as Summarize, Action Items, Decisions, Follow-up Email, and What Did I Miss?
- [ ] **Templates** — Auto, General Meeting, Training/Class, Project Meeting, 1-on-1, Brain Dump, and custom templates.
- [ ] **Scan handwritten notes** from the phone, OCR them, and retain the image alongside extracted text.

## Search and continuity (P1/P2)

- [ ] Full-text search across transcripts, notes, and generated memories.
- [ ] Ask across all Noted recordings and memories.
- [ ] People and organization tagging.
- [ ] Recurring-meeting grouping so current and previous meetings appear together.
- [ ] Optional calendar context for title, attendees, agenda, and “what happened last time.”

## Local automation and additional sources (P2)

- [ ] Add an opt-in watcher for a chosen recordings folder.
- [ ] Add an “always send after review” preference; never make raw-audio upload automatic.
- [ ] Add phone handoff through AirDrop/Files first, with an optional private Tailscale transfer later.
- [ ] Add Teams transcript import as a complementary path when company policy permits it.
- [ ] Add a background Mac agent with outbound-only authenticated job polling for unattended processing.

## Later, only if the workflow earns it (P3)

- [ ] Replace OBS with a small native audio-capture helper.
- [ ] Optional speaker diarization improvements.
- [ ] Apple Watch or quick-capture integrations.
- [ ] Per-user data isolation for additional Noted users.
- [ ] MCP/ChatGPT access to selected Noted memories.
- [ ] Carefully chosen integrations, if they solve a demonstrated personal workflow.

## Explicitly not part of the current plan

- Do not expose the Mac or Whisper service directly to the public internet.
- Do not upload raw audio/video to Cloudflare by default.
- Do not build a Teams bot or require a company-wide Teams installation.
- Do not start with workspaces, shared team folders, CRM/Slack/Zapier integrations, or enterprise collaboration.

## Recommended next build slice

1. Start Meeting mode and the elapsed timer.
2. Timestamped scratchpad.
3. Mark Moment ⭐.
4. End Meeting + OBS checklist.
5. Attach the existing Mac transcript handoff to that meeting session.

That slice delivers the part of Granola that most directly improves the user’s memory of a real meeting, while reusing the transcription path that just succeeded.
