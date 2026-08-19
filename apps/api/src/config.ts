import path from "node:path";

const legacyWhisperConfigured = Boolean(process.env.AI_API_KEY && /^whisper/i.test(process.env.AI_MODEL ?? ""));
const env = (name: string, fallback?: string) => process.env[name] || fallback || "";

export const config = {
  port: Number(process.env.PORT ?? 3333),
  dataDir: path.resolve(process.env.DATA_DIR ?? "./storage"),
  authPassword: process.env.AUTH_PASSWORD ?? "memory",
  llmMode: env("LLM_MODE", env("AI_MODE", (process.env.LLM_API_KEY || process.env.AI_API_KEY) ? "real" : "mock")),
  llmBaseUrl: env("LLM_BASE_URL", env("AI_BASE_URL")),
  llmApiKey: env("LLM_API_KEY", env("AI_API_KEY")),
  llmModel: env("LLM_MODEL", env("AI_MODEL")),
  transcriptionProvider: env("TRANSCRIPTION_PROVIDER", "groq"),
  transcriptionMode: env("TRANSCRIPTION_MODE", (process.env.TRANSCRIPTION_API_KEY || legacyWhisperConfigured) ? "real" : "disabled"),
  transcriptionBaseUrl: env("TRANSCRIPTION_BASE_URL", legacyWhisperConfigured ? process.env.AI_BASE_URL : undefined) || "https://api.groq.com/openai/v1",
  transcriptionApiKey: env("TRANSCRIPTION_API_KEY", legacyWhisperConfigured ? process.env.AI_API_KEY : ""),
  transcriptionModel: env("TRANSCRIPTION_MODEL", legacyWhisperConfigured ? process.env.AI_MODEL : undefined) || "whisper-large-v3-turbo",
  transcriptionMaxBytes: Number(process.env.TRANSCRIPTION_MAX_MB ?? 20) * 1024 * 1024,
  transcriptionChunkSeconds: Number(process.env.TRANSCRIPTION_CHUNK_SECONDS ?? 600),
  ffmpegBinary: process.env.FFMPEG_BIN ?? "ffmpeg",
  ffprobeBinary: process.env.FFPROBE_BIN ?? "ffprobe",
  maxUploadBytes: Number(process.env.MAX_UPLOAD_MB ?? 256) * 1024 * 1024,
  jobLeaseMs: Number(process.env.JOB_LEASE_MS ?? 15 * 60 * 1000),
  jobMaxAttempts: Number(process.env.JOB_MAX_ATTEMPTS ?? 3),
  jobPollMs: Number(process.env.JOB_POLL_MS ?? 2_000),
  version: "0.2.0",
};
