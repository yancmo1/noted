# Device validation — 2026-08-19

## Environment

- Device: `yPhone` (iPhone 17 Pro Max), connected through CoreDevice
- Team: `9PHS626XUN`
- Build: Debug, Xcode 27 beta, Noted app bundle `com.shepswork.noted` (bundle identifier retained for upgrade compatibility)
- Backend configuration category: local Debug endpoint (`127.0.0.1` in the installed build; no credentials recorded)

## Evidence

| Check | Result | Evidence |
|---|---|---|
| Signed physical build | Pass | `xcodebuild` for `yPhone` succeeded with the Apple Development identity and team profile |
| Install | Pass | `devicectl device install app --device yPhone` reported bundle installed |
| Launch | Pass | `devicectl device process launch --device yPhone com.shepswork.noted` reported Noted launched |
| iOS unit tests | Pass | 3 tests passed on DEMO-iPhone 17 Pro simulator |
| iOS UI launch test | Pass | Meetings and Record tab entry points found on the simulator |
| Microphone / lock screen / background | Pending | Requires hands-on interaction on `yPhone` |
| Airplane mode upload recovery | Pending | Requires API reachable from the phone over the Mac LAN address |
| Transcript / meeting brief / evidence seek | Pending | Requires configured provider path and representative audio |

The release gate remains open until the pending physical checks are executed. No audio or provider secrets were added to the repository.
