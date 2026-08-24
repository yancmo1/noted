import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config } from "./config.js";

const execFileAsync = promisify(execFile);

export class AudioValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AudioValidationError";
  }
}

export async function validateAudioFile(filePath: string): Promise<{ durationMs: number }> {
  try {
    const { stdout } = await execFileAsync(config.ffprobeBinary, [
      "-v", "error",
      "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1",
      filePath,
    ], { maxBuffer: 1024 * 1024 });
    const seconds = Number(String(stdout).trim());
    if (!Number.isFinite(seconds) || seconds <= 0) throw new Error("ffprobe returned no usable duration");
    return { durationMs: Math.round(seconds * 1000) };
  } catch (error) {
    const detail = error instanceof Error ? error.message : "unknown ffprobe error";
    throw new AudioValidationError(`Audio is not a complete playable file (ffprobe: ${detail}). Re-record and try again.`);
  }
}
