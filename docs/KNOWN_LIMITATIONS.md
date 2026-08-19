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
- The iOS project has passed the generic build, simulator unit tests, simulator UI launch test, signed physical-device build, installation, and launch. Microphone permission, lock-screen/background capture, route changes, offline relaunch, and the full LAN-backed processing flow still require hands-on validation on the connected phone.
- Native upload retry is durable, idempotent, and triggered by scene activation/network restoration while the app is running. It is not yet a fully delegated background `URLSession` transfer workflow after the OS suspends the app.
