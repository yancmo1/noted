# Noted on Cloudflare

This is the serverless deployment target for Noted. It replaces the local API's JSON repository and upload directory with:

Production domain: `https://noted.shepswork.com`

- Cloudflare Worker for the REST API and authentication.
- D1 for metadata, transcripts, memories, sessions, and processing state.
- Private R2 bucket for original audio.
- Cloudflare Queues for durable transcription/analysis jobs.
- Groq for speech-to-text and structured meeting analysis.

The existing Node/Docker API remains the local development implementation. This directory is intentionally separate so the local server and its recordings are not changed during cutover.

## One-time Cloudflare setup

From this directory:

```bash
npx wrangler login
npx wrangler d1 create noted-db
npx wrangler r2 bucket create noted-audio
npx wrangler queues create noted-processing
npx wrangler queues create noted-processing-dlq
```

Copy the D1 database ID into `wrangler.jsonc`. Store the app password and Groq key as Wrangler secrets; do not commit them:

```bash
npx wrangler secret put APP_PASSWORD
npx wrangler secret put GROQ_API_KEY
```

Apply the schema and deploy:

```bash
npx wrangler d1 migrations apply noted-db --remote
npx wrangler deploy
```

## Import existing local data

After the Worker is deployed and tested with an empty database, import the existing JSON state and audio without deleting the local copy. The importer refuses to run unless the explicit confirmation variable is set:

```bash
IMPORT_CONFIRM=YES \\
LOCAL_PROJECT_DIR=/absolute/path/to/AUTONOMOUS_AGENT \\
CLOUDFLARE_API_TOKEN=... \\
CLOUDFLARE_ACCOUNT_ID=... \\
D1_DATABASE_ID=... \\
R2_ACCOUNT_ID=... \\
R2_ACCESS_KEY_ID=... \\
R2_SECRET_ACCESS_KEY=... \\
npm run import:local
```

It preserves source IDs, uploads files to `audio/{sourceId}/original`, and marks missing local files as needing attention. Verify counts and playback before changing the iOS release endpoint.

## Direct mobile upload flow

The iOS client first requests `/api/recordings/upload-url`, receives an authenticated Noted upload URL, streams the audio through the Worker into private R2, and then calls `/api/recordings/:id/complete`. This avoids persistent R2 API credentials in the Worker. The local API fallback remains in the client during transition.

## Important migration limitation

Cloudflare Workers cannot run the current `ffprobe`/`ffmpeg` subprocess flow. The Worker path currently accepts recordings within Groq's speech upload limit and processes them from R2. Long-recording chunking and container-level media validation need a separate follow-up design before large recordings are cut over.

Do not delete the local `storage/` directory until the data import and playback checks are complete. The importer is intentionally conservative: it preserves source IDs, keeps the local copy, and requires an explicit `IMPORT_CONFIRM=YES` before writing to Cloudflare.
