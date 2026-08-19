import path from "node:path";

const legacyWhisperConfigured=Boolean(process.env.AI_API_KEY&&/^whisper/i.test(process.env.AI_MODEL??""));

export const config = {
  port: Number(process.env.PORT ?? 3333),
  dataDir: path.resolve(process.env.DATA_DIR ?? "./storage"),
  authPassword: process.env.AUTH_PASSWORD ?? "memory",
  llmMode: process.env.LLM_MODE || process.env.AI_MODE || ((process.env.LLM_API_KEY || process.env.AI_API_KEY) ? "real" : "mock"),
  llmBaseUrl: process.env.LLM_BASE_URL || process.env.AI_BASE_URL || "",
  llmApiKey: process.env.LLM_API_KEY || process.env.AI_API_KEY || "",
  llmModel: process.env.LLM_MODEL || process.env.AI_MODEL || "",
  transcriptionProvider: process.env.TRANSCRIPTION_PROVIDER || "groq",
  transcriptionMode: process.env.TRANSCRIPTION_MODE || (process.env.TRANSCRIPTION_API_KEY || legacyWhisperConfigured ? "real" : "disabled"),
  transcriptionBaseUrl: process.env.TRANSCRIPTION_BASE_URL || (legacyWhisperConfigured ? process.env.AI_BASE_URL : undefined) || "https://api.groq.com/openai/v1",
  transcriptionApiKey: process.env.TRANSCRIPTION_API_KEY || (legacyWhisperConfigured ? process.env.AI_API_KEY : "") || "",
  transcriptionModel: process.env.TRANSCRIPTION_MODEL || (legacyWhisperConfigured ? process.env.AI_MODEL : undefined) || "whisper-large-v3-turbo",
  transcriptionMaxBytes: Number(process.env.TRANSCRIPTION_MAX_MB ?? 20) * 1024 * 1024,
  transcriptionChunkSeconds: Number(process.env.TRANSCRIPTION_CHUNK_SECONDS ?? 600),
  ffmpegBinary: process.env.FFMPEG_BIN ?? "ffmpeg",
  ffprobeBinary: process.env.FFPROBE_BIN ?? "ffprobe",
  maxUploadBytes: Number(process.env.MAX_UPLOAD_MB ?? 25) * 1024 * 1024,
  version: "0.1.0"
};
