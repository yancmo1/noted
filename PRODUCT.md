# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Noted is currently a private tool for its owner, used during and after meetings, voice notes, and other recorded conversations. Additional independent users may be supported later.

## Product Purpose

Noted turns recordings and notes into durable, searchable memory. Success means capture is reliable, the original source remains available, transcripts are reviewable, and generated notes remain traceable to what was actually recorded.

## Positioning

Noted combines local-first capture and transcription with a web-based memory system. A small note or marked moment can steer the finished record, while raw recordings remain under the user's control.

## Operating Context

- Meetings are commonly held in Microsoft Teams and may be recorded through OBS.
- Recordings can also originate from Voice Memos, Apple Notes, Finder, a phone, or other audio and video applications.
- The Mac is available while many meetings occur but is not an always-on server.
- The Cloudflare-hosted web app remains the durable system of record for transcript text, notes, and generated meeting records.

## Capabilities and Constraints

- Accept common audio and video containers rather than depending on OBS.
- Transcribe recordings locally on Apple Silicon with `whisper.cpp` and Metal acceleration.
- Review-before-send is the default workflow.
- An explicit automatic-send preference may send completed transcript text without review.
- Raw audio remains local by default and must never be uploaded silently.
- Only transcript text and timestamp segments are sent to the Cloudflare-hosted app in the local-first workflow.
- The Mac must not be exposed directly to the public internet.
- Local work must survive Cloudflare outages and support retry without retranscription.
- Recording and transcription failures must be visible rather than silent.

## Brand Commitments

- Product name: Noted.
- Voice: calm, direct, reassuring, and plain-spoken.
- Preserve the existing deep green, sage, coral, lavender, and warm neutral identity used by the web and iOS applications.
- Use native platform behavior and familiar controls where reliability matters.

## Evidence on Hand

- Existing web application and Cloudflare Worker in this repository.
- Existing iOS application and Noted design tokens under `apps/ios/Noted`.
- Existing Noted icon assets under `apps/ios/Noted/Resources/Assets.xcassets` and `apps/web/public`.
- Verified local `whisper.cpp` installation, model, wrapper, and self-test documented outside the repository in the associated project notes.

## Product Principles

- Capture locally first.
- Make system state unmistakable.
- Preserve originals and source timestamps.
- Put the user in control of what leaves the device.
- Let automation be earned through successful reviewed use.

## Accessibility & Inclusion

Use native macOS and iOS accessibility behavior, keyboard navigation, descriptive labels, sufficient contrast, reduced-motion support, and status communication that does not rely on color alone.
