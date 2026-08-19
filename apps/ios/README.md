# Memory Garden iOS

Native SwiftUI capture client for the existing Memory Garden API.

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

The Debug configuration points to `http://127.0.0.1:3333`, which works in the iOS Simulator when the API is running locally. For a physical iPhone, change `apps/ios/Config/Debug.xcconfig` to the Mac's LAN address using the xcconfig-safe form, for example `API_BASE_URL = http:/$()/192.168.1.20:3333`, and ensure the phone can reach the API.

The app uses the existing local password login. The password is stored in Keychain; no AI or Groq credentials are shipped in the app.

## Login troubleshooting

Start the API before opening the iOS app:

```bash
npm run dev
```

If this reports `EADDRINUSE` for ports `3333` or `5173`, the development stack is already running in another terminal. Use that existing stack, or press `Ctrl-C` in the original terminal before starting it again. For an orphaned process, inspect it with `lsof -nP -iTCP:3333 -sTCP:LISTEN` and stop only the listed process before retrying.

The current workspace `.env` sets the password to `memory`. If `AUTH_PASSWORD` is changed, restart the API and use the new value. The Simulator uses `http://127.0.0.1:3333`; a physical iPhone must use the Mac's LAN address in `Config/Debug.xcconfig`.

## Native behavior

- Recordings are written to Application Support before upload.
- Uploads retain the local file until the API acknowledges the Source.
- A client recording UUID makes retries idempotent.
- Failed/offline uploads remain queued and are retried when the app becomes active.
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

Physical-device and signing validation must be completed in Xcode with an Apple development team. The project does not commit signing credentials.
