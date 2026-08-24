# Noted iOS

Native SwiftUI capture client for the existing Noted API.

## Requirements

- Xcode 26+
- iOS 17+
- A physical iPhone for microphone, lock-screen, and background recording validation
- `xcodegen` to regenerate the project after changing `project.yml`

## Open and run

```bash
xcodegen generate --spec project.yml
open MemoryGarden.xcodeproj
```

The editable Debug configuration defaults to the Mac's Tailscale address (`http://100.122.189.114:3333`) so the physical iPhone can reach the API over Tailscale. Change only the address in `apps/ios/Config/Debug.xcconfig` when using another Mac, LAN, or local simulator setup, using the xcconfig-safe form such as `API_BASE_URL = http:/$()/192.168.1.20:3333`. Ensure the phone can reach that address before launching the app.

The app uses the existing local password login. The password is stored in Keychain; no AI or Groq credentials are shipped in the app.

## Login troubleshooting

Start the API before opening the iOS app:

```bash
npm run dev
```

If this reports `EADDRINUSE` for ports `3333` or `5173`, the development stack is already running in another terminal. Use that existing stack, or press `Ctrl-C` in the original terminal before starting it again. For an orphaned process, inspect it with `lsof -nP -iTCP:3333 -sTCP:LISTEN` and stop only the listed process before retrying.

The current workspace `.env` sets the password to `memory`. If `AUTH_PASSWORD` is changed, restart the API and use the new value. The Debug build defaults to the Mac's Tailscale address in `Config/Debug.xcconfig`; edit that one line whenever the server address changes.

## Native behavior

- Recordings are written to Application Support before upload.
- Uploads retain the local file until the API acknowledges the Source.
- A client recording UUID makes retries idempotent.
- Recordings are sent individually from their meeting detail screen. Failed sends remain local and can be retried from that same recording; reconnecting or refreshing never sends the rest automatically. A stale recording draft is surfaced as Recovered instead of being hidden.
- Audio uses M4A/AAC at 44.1 kHz mono and the audio background mode is enabled.
- Mark Moments are persisted locally and shown on playback.

## Device checklist

1. Grant microphone permission.
2. Start a private-thought recording.
3. Lock the phone and wait, then unlock and stop.
4. Verify the local recording remains playable.
5. Disable network, record and stop, then relaunch.
6. Restore network and verify exactly one server Source is created.
7. Open the recording, tap transcript/evidence timestamps, and verify seeking.

The current build has been signed, installed, and launched on `yPhone` with team `9PHS626XUN`. The project does not commit signing credentials. Complete the hands-on microphone, lock-screen/background, interruption, airplane-mode, and LAN processing checklist before calling the release gate complete.
