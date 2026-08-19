import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "./app.js";
import { store } from "./db.js";

function multipartBody(boundary: string, fields: Record<string, string>, file: Buffer) {
  const chunks: Buffer[] = [];
  for (const [name, value] of Object.entries(fields)) {
    chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="${name}"\r\n\r\n${value}\r\n`));
  }
  chunks.push(Buffer.from(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="meeting.m4a"\r\nContent-Type: audio/mp4\r\n\r\n`));
  chunks.push(file);
  chunks.push(Buffer.from(`\r\n--${boundary}--\r\n`));
  return Buffer.concat(chunks);
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
    }, Buffer.from("test-audio"));
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
    expect(range.body).toBe("test");
  });
});
