import os from "node:os";
import path from "node:path";

const legacyWhisperConfigured = Boolean(process.env.AI_API_KEY && /^whisper/i.test(process.env.AI_MODEL ?? ""));
const env = (name: string, fallback?: string) => process.env[name] || fallback || "";
const positiveNumber = (value: string | undefined, fallback: number) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};
const reasoningEffort = (value: string | undefined): "none" | "low" | "medium" | "high" => {
  switch (value) {
    case "none":
    case "low":
    case "medium":
    case "high":
      return value;
    default:
      return "low";
  }
};
const dataDir = path.resolve(process.env.DATA_DIR ?? "./storage");

export const config = {
  port: Number(process.env.PORT ?? 3333),
  dataDir,
  authPassword: process.env.AUTH_PASSWORD ?? "memory",
  llmMode: env("LLM_MODE", env("AI_MODE", (process.env.LLM_API_KEY || process.env.AI_API_KEY) ? "real" : "mock")),
  llmBaseUrl: env("LLM_BASE_URL", env("AI_BASE_URL")),
  llmApiKey: env("LLM_API_KEY", env("AI_API_KEY", process.env.TRANSCRIPTION_API_KEY)),
  llmModel: env("LLM_MODEL", env("AI_MODEL")),
  llmReasoningEffort: reasoningEffort(process.env.LLM_REASONING_EFFORT),
  llmAnalysisChunkChars: positiveNumber(process.env.LLM_ANALYSIS_CHUNK_CHARS, 0),
  llmAnalysisTimeoutMs: positiveNumber(process.env.LLM_ANALYSIS_TIMEOUT_MS, 0),
  transcriptionProvider: env("TRANSCRIPTION_PROVIDER", "ai-lab"),
  transcriptionMode: env("TRANSCRIPTION_MODE", (process.env.TRANSCRIPTION_API_KEY || legacyWhisperConfigured) ? "real" : "disabled"),
  transcriptionBaseUrl: env("TRANSCRIPTION_BASE_URL", legacyWhisperConfigured ? process.env.AI_BASE_URL : undefined) || "http://127.0.0.1:8787/v1",
  transcriptionApiKey: env("TRANSCRIPTION_API_KEY", legacyWhisperConfigured ? process.env.AI_API_KEY : ""),
  transcriptionModel: env("TRANSCRIPTION_MODEL", legacyWhisperConfigured ? process.env.AI_MODEL : undefined) || "small.en",
  transcriptionMaxBytes: Number(process.env.TRANSCRIPTION_MAX_MB ?? 20) * 1024 * 1024,
  // Keep each CPU transcription request short enough for the local HTTP
  // transport to remain open while the local model finishes inference.
  transcriptionChunkSeconds: Number(process.env.TRANSCRIPTION_CHUNK_SECONDS ?? 120),
  localWhisperWrapperPath: env("LOCAL_WHISPER_WRAPPER", path.join(os.homedir(), "Library/Application Support/Noted/transcription/bin/noted-transcribe")),
  localWhisperModel: env("LOCAL_WHISPER_MODEL", "ggml-large-v3-turbo-q5_0"),
  localWhisperOutputDir: path.resolve(env("LOCAL_WHISPER_OUTPUT_DIR", path.join(dataDir, "local-transcription"))),
  localWhisperTimeoutMs: positiveNumber(process.env.LOCAL_WHISPER_TIMEOUT_MS, 30 * 60 * 1000),
  localWhisperLanguage: env("LOCAL_WHISPER_LANGUAGE", "auto"),
  ffmpegBinary: process.env.FFMPEG_BIN ?? "ffmpeg",
  ffprobeBinary: process.env.FFPROBE_BIN ?? "ffprobe",
  maxUploadBytes: Number(process.env.MAX_UPLOAD_MB ?? 256) * 1024 * 1024,
  jobLeaseMs: Number(process.env.JOB_LEASE_MS ?? 15 * 60 * 1000),
  jobMaxAttempts: Number(process.env.JOB_MAX_ATTEMPTS ?? 3),
  jobPollMs: Number(process.env.JOB_POLL_MS ?? 2_000),
  version: "0.2.0",
};
