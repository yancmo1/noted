import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll } from "vitest";

const testDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "memory-garden-test-"));
fs.mkdirSync(path.join(testDataDir, "uploads"), { recursive: true });
process.env.DATA_DIR = testDataDir;
process.env.AUTH_PASSWORD = "test-password";
process.env.TRANSCRIPTION_MODE = "disabled";
process.env.TRANSCRIPTION_API_KEY = "";

afterAll(() => {
  fs.rmSync(testDataDir, { recursive: true, force: true });
});
