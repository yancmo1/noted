import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { config } from "./config.js";
import { processingError, processingInfo } from "./diagnostics.js";
import type { TranscriptionInput, TranscriptionProvider, TranscriptionResult, TranscriptionSegment } from "./ai.js";

const execFileAsync = promisify(execFile);

export interface LocalWhisperSettings {
  wrapperPath: string;
  model: string;
  outputRoot: string;
  timeoutMs: number;
  language: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function nonNegativeMilliseconds(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) return undefined;
  return Math.round(value);
}

function nonEmptyString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function errorDetail(error: unknown): string {
  if (error instanceof Error && error.message.trim()) return error.message.trim();
  if (isRecord(error) && typeof error.stderr === "string" && error.stderr.trim()) return error.stderr.trim();
  return "The local Whisper process returned an unknown error.";
}

/** Parse the stable JSON shape emitted by the existing whisper.cpp wrapper. */
export function parseLocalWhisperDocument(document: unknown, textFileContents: string): TranscriptionResult {
  const root = isRecord(document) ? document : {};
  const result = isRecord(root.result) ? root.result : {};
  const language = nonEmptyString(result.language);
  const rawEntries = Array.isArray(root.transcription) ? root.transcription : [];
  const segments: TranscriptionSegment[] = rawEntries.flatMap((rawEntry): TranscriptionSegment[] => {
    if (!isRecord(rawEntry)) return [];
    const text = nonEmptyString(rawEntry.text);
    if (!text) return [];
    const offsets = isRecord(rawEntry.offsets) ? rawEntry.offsets : {};
    const startMs = nonNegativeMilliseconds(offsets.from);
    const endMs = nonNegativeMilliseconds(offsets.to);
    if (startMs !== undefined && endMs !== undefined && endMs < startMs) return [];
    const segment: TranscriptionSegment = { text };
    if (startMs !== undefined) segment.startMs = startMs;
    if (endMs !== undefined) segment.endMs = endMs;
    return [segment];
  });
  const text = textFileContents.trim() || segments.map((segment) => segment.text).join(" ").trim();
  if (!text) throw new Error("Local Whisper produced an empty transcript.");
  return { text, segments: segments.length ? segments : [{ text }], language };
}

export class LocalWhisperTranscriptionProvider implements TranscriptionProvider {
  private readonly settings: LocalWhisperSettings;

  constructor(settings: LocalWhisperSettings = {
    wrapperPath: config.localWhisperWrapperPath,
    model: config.localWhisperModel,
    outputRoot: config.localWhisperOutputDir,
    timeoutMs: config.localWhisperTimeoutMs,
    language: config.localWhisperLanguage,
  }) {
    this.settings = settings;
  }

  async transcribe(input: TranscriptionInput): Promise<TranscriptionResult> {
    const startedAt = performance.now();
    const outputDir = path.join(this.settings.outputRoot, input.sourceId);

    try {
      await fs.mkdir(outputDir, { recursive: true });
      const inputBytes = (await fs.stat(input.filePath)).size;
      processingInfo({
        event: "transcription_started",
        provider: "local-whisper",
        sourceId: input.sourceId,
        inputBytes,
        wrapperPath: this.settings.wrapperPath,
        model: this.settings.model,
        language: this.settings.language,
      }, "Local Whisper transcription started");

      await execFileAsync(this.settings.wrapperPath, [input.filePath, outputDir], {
        env: { ...process.env, NOTED_WHISPER_LANGUAGE: this.settings.language },
        timeout: this.settings.timeoutMs,
        maxBuffer: 1024 * 1024,
      });

      const jsonContents = await fs.readFile(path.join(outputDir, "transcript.json"), "utf8");
      const textContents = await fs.readFile(path.join(outputDir, "transcript.txt"), "utf8");
      const document: unknown = JSON.parse(jsonContents);
      const result = parseLocalWhisperDocument(document, textContents);
      processingInfo({
        event: "transcription_completed",
        provider: "local-whisper",
        sourceId: input.sourceId,
        elapsedMs: Math.round(performance.now() - startedAt),
        segmentCount: result.segments.length,
        transcriptCharacters: result.text.length,
        language: result.language ?? "unknown",
        outputDir,
      }, "Local Whisper transcription completed");
      return result;
    } catch (error) {
      const detail = errorDetail(error);
      processingError({
        event: "transcription_failed",
        provider: "local-whisper",
        sourceId: input.sourceId,
        elapsedMs: Math.round(performance.now() - startedAt),
        error: detail,
        outputDir,
      }, "Local Whisper transcription failed");
      throw new Error(`Local Whisper transcription failed: ${detail}`);
    }
  }
}
