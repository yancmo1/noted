# Noted Xcode Cloud / TestFlight Setup

The repository is prepared for a stable Xcode Cloud archive of the iPhone app with the Watch spike embedded. TestFlight is the recommended way to install this build on the physical iPhone and paired Watch; it uses distribution signing and does not require registering an individual Watch UDID.

## Repository configuration

- Project: `apps/ios/Noted.xcodeproj`
- Archive scheme: `Noted`
- iPhone bundle ID: `com.shepswork.noted`
- Watch bundle ID: `com.shepswork.noted.watchkitapp`
- Share extension bundle ID: `com.shepswork.noted.share`
- App Store listing name: `Noted by Shepswork.`
- Compatibility identifiers intentionally retained: application group `group.com.memorygarden.ios`, local recording folder `Application Support/MemoryGarden`, and Keychain service `com.memorygarden.ios`. These preserve existing data and login access across the rename.
- Release API endpoint: `https://noted.shepswork.com`
- Xcode Cloud scripts: `apps/ios/ci_scripts/`

The project and both shared schemes are present in the repository so Xcode Cloud can build without installing XcodeGen. The post-clone script validates that the checked-in project contains the iPhone and Watch targets. The pre-build script fails a Cloud action if the selected runner reports a beta Xcode version or if an archive uses the Watch-only scheme. The post-build script verifies that a successful archive contains the embedded Watch app.

## One-time App Store Connect setup

1. Commit and push the repository changes, then connect the GitHub repository and select the branch containing them. Xcode Cloud builds a checked-out Git commit; it cannot see uncommitted local changes.
2. Create or select the App Store Connect app record for `com.shepswork.noted`.
3. In Certificates, Identifiers & Profiles, register the iPhone App ID, the Watch App ID `com.shepswork.noted.watchkitapp`, and the Share Extension App ID `com.shepswork.noted.share` under team `9PHS626XUN`. Ensure the application group `group.com.memorygarden.ios` exists and is assigned to the iPhone and Share Extension IDs.
4. In Xcode Cloud, create a workflow for the `Noted` scheme with a simulator Test action followed by an Archive action. The Test action runs the 21 unit tests and the UI launch test. Choose the latest available stable, non-beta Xcode version. Do not choose the local `Xcode-beta` version.
5. Enable automatic signing / Xcode Cloud-managed signing for the workflow and distribute the successful archive to TestFlight internal testers.
6. Start with the default Xcode Cloud build number. If App Store Connect reports a version/build collision, set the next Cloud build number in the app’s Xcode Cloud settings rather than hard-coding a timestamp or hash in the project.

## First Cloud run

Use an Archive action, not a Watch-only Build action. Confirm the archive contains `Noted.app/Watch/Noted Watch Spike.app`, wait for App Store Connect processing, then add the processed build to an internal TestFlight group. Install TestFlight on the paired iPhone, accept the invite, and install the Noted build; the embedded Watch app can then be installed from the Watch app on the iPhone.

This distribution build enables the physical Phase 1 tests, but it does not make those tests pass automatically. Record the Watch background, endurance, codec, interruption/recovery, transfer/acknowledgement, and locked-phone remote-start results in `APPLE_WATCH_PHASE1_SPRINT.md`.

## References

- [Apple: configuring your first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
- [Apple: writing custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Apple: upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
