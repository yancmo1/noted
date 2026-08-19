# Known limitations

- The local MVP persistence backend is an atomic JSON document rather than PostgreSQL/pgvector. It is appropriate for a private single-user installation and thousands of modest captures, but it is not a multi-user database.
- Semantic embeddings are not generated in mock mode; retrieval is token-based keyword scoring with source-title matching.
- Reasoning and transcription credentials are separate. Groq transcription is the default provider/model, but audio stays `partial` when no transcription key is configured; manual transcripts remain supported. Mock analysis does not fabricate speech from arbitrary audio bytes.
- PDF/DOCX/image OCR is not enabled by default. File and link captures still preserve the original source and can be reprocessed when an extractor is added.
- Browser recording depends on the page remaining active and on browser microphone permissions. The native iOS client supports lock-screen/background audio capture and Bluetooth routes; diarization and speaker labeling are not implemented yet.
- Transcript offsets depend on the configured provider or manual segment input. When only a plain transcript is available, evidence can identify the source and quote without a precise audio seek target.
- Long-recording chunking requires `ffmpeg` and `ffprobe` on the API runtime. The Docker API image installs them; local development machines must install them separately if recordings exceed the configured limits.
- Sessions are held in process memory and expire when the API restarts. Use a reverse proxy and persistent auth layer before exposing this beyond a trusted self-hosted network.
- Automated Playwright coverage is not included in the initial dependency set. The API lifecycle has deterministic Vitest coverage, and the recording-first surface was manually checked in the local in-app browser during this build.
- The iOS project compiles and its unit/UI test targets compile with `xcodebuild`, but this environment could not run Simulator tests because CoreSimulatorService was unavailable. Physical iPhone validation remains required for microphone permission, lock-screen/background recording, route changes, offline relaunch, and signing.
- Native upload retry is durable and idempotent, but the MVP retries while the app is active/foregrounded. A future pass can promote this to a fully delegated background `URLSession` transfer workflow.
