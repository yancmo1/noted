# Noted ai-lab transcriber

This is the CPU transcription service used by the Noted API. It keeps
OpenAI Whisper `small.en` loaded through `faster-whisper` with CPU INT8
inference and exposes the endpoint shape that Noted already understands:

```text
POST /v1/audio/transcriptions
GET  /health
```

The ai-lab default is `small.en`, selected for practical CPU throughput on the
small always-on VM. The service accepts an optional `TRANSCRIBER_API_KEY`; when configured, clients must send
`Authorization: Bearer <key>`. Keep the port reachable only over the trusted
Tailscale/private network.

The existing Noted API remains the authenticated app-facing endpoint. It saves
the recording, queues the work, sends the audio here, persists the transcript,
and exposes it through the normal recording APIs.
