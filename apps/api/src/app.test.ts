import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "./app.js";
import { store } from "./db.js";

function multipartBody(boundary: string, fields: Record<string, string>, file: Buffer, filename = "meeting.wav", mimeType = "audio/wav") {
  const chunks: Buffer[] = [];
  for (const [name, value] of Object.entries(fields)) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`));
  }
  chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${filename}"\r\nContent-Type: ${mimeType}\r\n\r\n`));
  chunks.push(file);
  chunks.push(Buffer.from(`\r\n--${boundary}--\r\n`));
  return Buffer.concat(chunks);
}

function silentWav(durationMs = 1_200) {
  const sampleRate = 8_000;
  const channels = 1;
  const bitsPerSample = 16;
  const dataSize = Math.max(1, Math.round(sampleRate * durationMs / 1000) * channels * bitsPerSample / 8);
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + dataSize, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(channels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * channels * bitsPerSample / 8, 28);
  header.writeUInt16LE(channels * bitsPerSample / 8, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write("data", 36);
  header.writeUInt32LE(dataSize, 40);
  return Buffer.concat([header, Buffer.alloc(dataSize)]);
}

describe("API meeting capture contract", () => {
  let app: FastifyInstance;
  let cookie = "";
  const createdSourceIDs: string[] = [];

  beforeAll(async () => {
    app = await buildApp();
    await app.ready();
  });

  afterAll(async () => {
    for (const id of createdSourceIDs) store.deleteSource(id);
    await app.close();
  });

  it("keeps health public and protects memory data", async () => {
    expect((await app.inject({ method: "GET", url: "/api/health" })).statusCode).toBe(200);
    expect((await app.inject({ method: "GET", url: "/api/sources" })).statusCode).toBe(401);
  });

  it("accepts a voice recording once and reconciles retries by client id", async () => {
    const login = await app.inject({
      method: "POST",
      url: "/api/auth/login",
      payload: { password: "test-password" },
    });
    expect(login.statusCode).toBe(200);
    const setCookie = login.headers["set-cookie"];
    cookie = (Array.isArray(setCookie) ? setCookie[0] : setCookie ?? "").split(";", 1)[0];
    expect(cookie).toMatch(/^mg_session=/);

    const clientRecordingId = "native-integration-recording";
    const boundary = "memory-garden-test-boundary";
    const payload = multipartBody(boundary, {
      title: "Integration meeting",
      clientRecordingId,
      consentMode: "meeting",
      consentAcknowledged: "true",
      durationMs: "1200",
      startedAt: "2026-08-19T12:00:00.000Z",
      endedAt: "2026-08-19T12:00:01.200Z",
      client: "native",
    }, silentWav());
    const headers = { cookie, "content-type": `multipart/form-data; boundary=${boundary}` };
    const first = await app.inject({ method: "POST", url: "/api/capture/voice", headers, payload });
    expect(first.statusCode).toBe(200);
    const firstBody = first.json<{ id: string; deduplicated: boolean }>();
    expect(firstBody.deduplicated).toBe(false);
    createdSourceIDs.push(firstBody.id);

    const second = await app.inject({ method: "POST", url: "/api/capture/voice", headers, payload });
    expect(second.statusCode).toBe(200);
    expect(second.json<{ id: string; deduplicated: boolean }>()).toMatchObject({ id: firstBody.id, deduplicated: true });

    const reconciled = await app.inject({ method: "GET", url: `/api/recordings/by-client-id/${clientRecordingId}`, headers: { cookie } });
    expect(reconciled.statusCode).toBe(200);
    expect(reconciled.json<{ id: string }>().id).toBe(firstBody.id);

    const range = await app.inject({ method: "GET", url: `/files/${firstBody.id}`, headers: { cookie, range: "bytes=0-3" } });
    expect(range.statusCode).toBe(206);
    expect(range.body).toBe("RIFF");
  });

  it("rejects incomplete M4A uploads without creating a source", async () => {
    const boundary = "memory-garden-invalid-audio-boundary";
    const clientRecordingId = "invalid-moov-recording";
    const payload = multipartBody(boundary, {
      title: "Corrupt recording",
      clientRecordingId,
      consentMode: "private_thought",
      consentAcknowledged: "true",
      durationMs: "1200",
      startedAt: "2026-08-19T12:00:00.000Z",
      endedAt: "2026-08-19T12:00:01.200Z",
      client: "native",
    }, Buffer.from("this is not an m4a"), "broken.m4a", "audio/mp4");
    const response = await app.inject({ method: "POST", url: "/api/capture/voice", headers: { cookie, "content-type": `multipart/form-data; boundary=${boundary}` }, payload });
    expect(response.statusCode).toBe(422);
    expect(response.json<{ error: string }>().error).toMatch(/complete playable file/i);
    expect(store.findSourceByClientRecordingId(clientRecordingId)).toBeUndefined();
  });

  it("accepts a structurally valid audio fixture and uses its probed duration", async () => {
    const boundary = "memory-garden-valid-audio-boundary";
    const clientRecordingId = "valid-probed-duration-recording";
    const payload = multipartBody(boundary, {
      title: "Valid recording",
      clientRecordingId,
      consentMode: "private_thought",
      consentAcknowledged: "true",
      durationMs: "999999",
      startedAt: "2026-08-19T12:00:00.000Z",
      endedAt: "2026-08-19T12:00:01.200Z",
      client: "native",
    }, silentWav(1200));
    const response = await app.inject({ method: "POST", url: "/api/capture/voice", headers: { cookie, "content-type": `multipart/form-data; boundary=${boundary}` }, payload });
    expect(response.statusCode).toBe(200);
    const body = response.json<{ id: string; durationMs?: number }>();
    createdSourceIDs.push(body.id);
    expect(body.durationMs).toBe(1200);
  });
});
