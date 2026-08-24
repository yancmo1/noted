import Fastify, { type FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import multipart from "@fastify/multipart";
import cookie from "@fastify/cookie";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { config } from "./config.js";
import { store } from "./db.js";
import { queueSource } from "./processor.js";
import { aiProvider, transcriptionProvider } from "./ai.js";
import { validateAudioFile } from "./audioValidation.js";
import type { ConsentMode, LoopStatus, SourceType, TranscriptSegment } from "./types.js";

type MultipartUpload = {
  filePath: string;
  filename: string;
  mimetype: string;
  fields: Record<string, unknown>;
};

function field(fields: Record<string, unknown>, name: string) {
  const value = fields[name];
  return typeof value === "string" ? value : (value as any)?.value;
}

function boolField(value: unknown) {
  return value === true || value === "true" || value === "1";
}

function consentMode(value: unknown): ConsentMode {
  return value === "conversation" || value === "meeting" ? value : "private_thought";
}

function clientType(value: unknown): "web" | "native" | "hardware" {
  return value === "native" || value === "hardware" ? value : "web";
}

function safeFileName(value: string, fallback: string) {
  const safe = value.replace(/[^a-zA-Z0-9._-]/g, "_");
  return safe || fallback;
}

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: { level: process.env.LOG_LEVEL ?? "info" }, bodyLimit: config.maxUploadBytes + 1024 * 1024 });
  await app.register(cors, { origin: true, credentials: true });
  await app.register(multipart, { limits: { fileSize: config.maxUploadBytes, files: 1 } });
  await app.register(cookie);

  const sessions = new Map<string, { createdAt: number }>();
  const isAuthed = (request: any) => {
    const token = request.cookies?.mg_session ?? request.headers.authorization?.replace("Bearer ", "");
    return Boolean(token && sessions.has(token));
  };

  app.addHook("onRequest", async (request, reply) => {
    if (request.url.startsWith("/api/health") || request.url.startsWith("/api/auth") || request.url.startsWith("/api/settings/status")) return;
    if (!isAuthed(request)) return reply.code(401).send({ error: "Authentication required" });
  });

  app.get("/api/health", async () => ({ status: "ok", version: config.version, now: new Date().toISOString() }));
  app.get("/api/auth/status", async (request) => ({ authenticated: isAuthed(request) }));

  app.post("/api/auth/login", async (request: any, reply) => {
    const body = request.body as { password?: string };
    if (!body?.password || body.password !== config.authPassword) return reply.code(401).send({ error: "Incorrect password" });
    const token = crypto.randomUUID();
    sessions.set(token, { createdAt: Date.now() });
    reply.setCookie("mg_session", token, { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production", path: "/", maxAge: 60 * 60 * 24 * 30 });
    return { ok: true };
  });

  app.post("/api/auth/logout", async (request: any, reply) => {
    sessions.delete(request.cookies?.mg_session);
    reply.clearCookie("mg_session", { path: "/" });
    return { ok: true };
  });

  function createCapture(type: SourceType, title: string, text: string, extra: Record<string, unknown> = {}) {
    const source = store.createSource({ type, title, originalText: text, extractedText: type === "note" ? text : "", sourceUrl: extra.sourceUrl as string | undefined, filePath: extra.filePath as string | undefined, mimeType: extra.mimeType as string | undefined, metadata: (extra.metadata as Record<string, unknown>) ?? {} });
    queueSource(source.id);
    return source;
  }

  app.post("/api/capture/note", async (request: any, reply) => {
    const text = String(request.body?.text ?? "").trim();
    if (!text) return reply.code(400).send({ error: "Note text is required" });
    return createCapture("note", String(request.body?.title ?? "Quick note"), text);
  });

  app.post("/api/capture/url", async (request: any, reply) => {
    const url = String(request.body?.url ?? "").trim();
    try { new URL(url); } catch { return reply.code(400).send({ error: "Enter a valid URL" }); }
    return createCapture("url", String(request.body?.title ?? url), "", { sourceUrl: url });
  });

  async function multipartUpload(request: any): Promise<MultipartUpload> {
    const fields: Record<string, unknown> = {};
    let filePath = "";
    let filename = "recording";
    let mimetype = "application/octet-stream";
    const incomingDir = path.join(config.dataDir, "uploads", "incoming");
    await fsp.mkdir(incomingDir, { recursive: true });

    for await (const part of request.parts()) {
      if (part.type === "file") {
        filePath = path.join(incomingDir, `upload-${crypto.randomUUID()}.part`);
        filename = String(part.filename ?? filename);
        mimetype = part.mimetype;
        await pipeline(part.file, fs.createWriteStream(filePath, { flags: "wx" }));
        if (part.file.truncated) throw new Error("Uploaded file exceeds the configured size limit");
      } else {
        fields[part.fieldname] = part.value;
      }
    }
    if (!filePath) throw new Error("A file is required");
    return { filePath, filename, mimetype, fields };
  }

  app.post("/api/capture/voice", async (request: any, reply) => {
    let upload: MultipartUpload | undefined;
    try {
      upload = await multipartUpload(request);
      const clientRecordingId = String(field(upload.fields, "clientRecordingId") ?? "").trim();
      if (!clientRecordingId) {
        await fsp.rm(upload.filePath, { force: true });
        upload.filePath = "";
        return reply.code(400).send({ error: "clientRecordingId is required" });
      }
      const existing = store.findSourceByClientRecordingId(clientRecordingId);
      if (existing) {
        await fsp.rm(upload.filePath, { force: true });
        const existingSession = existing.recordingSessionId ? store.getRecordingSession(existing.recordingSessionId) : store.getRecordingSessionForSource(existing.id);
        return { ...existing, recordingSession: existingSession, deduplicated: true };
      }

      const mode = consentMode(field(upload.fields, "consentMode"));
      const acknowledged = boolField(field(upload.fields, "consentAcknowledged"));
      if ((mode === "conversation" || mode === "meeting") && !acknowledged) {
        await fsp.rm(upload.filePath, { force: true });
        upload.filePath = "";
        return reply.code(400).send({ error: "Consent acknowledgement is required for conversation or meeting mode" });
      }

      const client = clientType(field(upload.fields, "client"));
      if (clientRecordingId && client !== "native") {
        await fsp.rm(upload.filePath, { force: true });
        upload.filePath = "";
        return reply.code(400).send({ error: "Native uploads must identify client=native" });
      }
      if (clientRecordingId && (!field(upload.fields, "title") || !field(upload.fields, "startedAt") || !field(upload.fields, "endedAt") || field(upload.fields, "durationMs") === undefined)) {
        await fsp.rm(upload.filePath, { force: true });
        upload.filePath = "";
        return reply.code(400).send({ error: "Native uploads require title, start/end timestamps, and duration" });
      }

      let validatedAudio: { durationMs: number };
      try {
        validatedAudio = await validateAudioFile(upload.filePath);
      } catch (error) {
        await fsp.rm(upload.filePath, { force: true });
        upload.filePath = "";
        return reply.code(422).send({ error: error instanceof Error ? error.message : "Audio is not a complete playable file. Re-record and try again." });
      }

      const id = crypto.randomUUID();
      const startedAt = String(field(upload.fields, "startedAt") ?? new Date().toISOString());
      const endedAt = String(field(upload.fields, "endedAt") ?? new Date().toISOString());
      const durationMs = validatedAudio.durationMs;
      const finalPath = path.join(config.dataDir, "uploads", `${id}-${safeFileName(upload.filename, "recording")}`);
      await fsp.rename(upload.filePath, finalPath);
      upload.filePath = "";

      const { source, created } = store.createVoiceSourceIfAbsent({
        id,
        title: String(field(upload.fields, "title") ?? `Recording — ${new Date(startedAt).toLocaleString()}`),
        clientRecordingId,
        originalText: "",
        extractedText: "",
        filePath: finalPath,
        mimeType: upload.mimetype,
        audioMimeType: upload.mimetype,
        durationMs,
        capturedAt: startedAt,
        consentMode: mode,
        consentAcknowledged: acknowledged,
        transcriptStatus: "pending",
        metadata: { client, clientRecordingId },
      });
      if (!created) await fsp.rm(finalPath, { force: true });
      const session = created ? store.createRecordingSession({ sourceId: source.id, status: "uploaded", startedAt, endedAt, durationMs, mimeType: upload.mimetype, client, consentMode: mode, consentAcknowledged: acknowledged, metadata: { filename: upload.filename, clientRecordingId } }) : source.recordingSessionId ? store.getRecordingSession(source.recordingSessionId) : store.getRecordingSessionForSource(source.id);
      if (created && session) store.updateSource(source.id, { recordingSessionId: session.id });
      if (created) queueSource(source.id);
      return { ...store.getSource(source.id), recordingSession: session, deduplicated: !created };
    } catch (error) {
      if (upload?.filePath) await fsp.rm(upload.filePath, { force: true });
      const message = error instanceof Error ? error.message : "Upload failed";
      return reply.code(message.includes("size limit") ? 413 : 400).send({ error: message });
    }
  });

  app.get("/api/recordings/by-client-id/:clientRecordingId", async (request: any, reply) => {
    const source = store.findSourceByClientRecordingId(request.params.clientRecordingId);
    if (!source) return reply.code(404).send({ error: "Recording not found" });
    const recordingSession = source.recordingSessionId ? store.getRecordingSession(source.recordingSessionId) : store.getRecordingSessionForSource(source.id);
    return { ...source, recordingSession, deduplicated: true };
  });

  app.post("/api/capture/file", async (request: any, reply) => {
    let upload: MultipartUpload | undefined;
    try {
      upload = await multipartUpload(request);
      const id = crypto.randomUUID();
      const finalPath = path.join(config.dataDir, "uploads", `${id}-${safeFileName(upload.filename, "file")}`);
      await fsp.rename(upload.filePath, finalPath);
      upload.filePath = "";
      const content = await fsp.readFile(finalPath);
      const extracted = /text\/(plain|markdown)|\.(md|txt)$/i.test(`${upload.mimetype} ${upload.filename}`) ? content.toString("utf8") : "";
      const type = /image\//.test(upload.mimetype) ? "image" : "file";
      return createCapture(type, upload.filename, extracted, { filePath: finalPath, mimeType: upload.mimetype, metadata: { size: content.byteLength } });
    } catch (error) {
      if (upload?.filePath) await fsp.rm(upload.filePath, { force: true });
      return reply.code(400).send({ error: error instanceof Error ? error.message : "File upload failed" });
    }
  });

  function sourceBundle(id: string) {
    const source = store.getSource(id);
    if (!source) return undefined;
    const recordingSession = source.recordingSessionId ? store.getRecordingSession(source.recordingSessionId) : store.getRecordingSessionForSource(id);
    const memories = store.memoriesForSource(id);
    return { source, recordingSession, transcript: { text: source.transcriptText ?? "", segments: store.transcriptForSource(id) }, memories, entities: store.entitiesForSource(id), openLoops: memories.flatMap((memory) => store.listLoops().filter((loop) => loop.memoryId === memory.id)) };
  }

  app.get("/api/sources", async (request: any) => {
    const query = request.query as { limit?: string; offset?: string };
    return { sources: store.listSources(Number(query.limit ?? 50), Number(query.offset ?? 0)) };
  });
  app.get("/api/sources/:id", async (request: any, reply) => {
    const bundle = sourceBundle(request.params.id);
    if (!bundle) return reply.code(404).send({ error: "Source not found" });
    return bundle;
  });
  app.get("/api/recordings/:id", async (request: any, reply) => {
    const bundle = sourceBundle(request.params.id);
    if (!bundle || bundle.source.type !== "voice") return reply.code(404).send({ error: "Recording not found" });
    return bundle;
  });
  app.get("/api/recordings/:id/transcript", async (request: any, reply) => {
    const bundle = sourceBundle(request.params.id);
    if (!bundle || bundle.source.type !== "voice") return reply.code(404).send({ error: "Recording not found" });
    return bundle.transcript;
  });
  app.patch("/api/recordings/:id/transcript", async (request: any, reply) => {
    const source = store.getSource(request.params.id);
    if (!source || source.type !== "voice") return reply.code(404).send({ error: "Recording not found" });
    const text = String(request.body?.text ?? "").trim();
    if (!text) return reply.code(400).send({ error: "Transcript text is required" });
    const rawSegments: unknown[] = Array.isArray(request.body?.segments) ? request.body.segments : [];
    const segments: Omit<TranscriptSegment, "id" | "sourceId" | "createdAt">[] = rawSegments.length
      ? rawSegments.map((raw: any, index) => ({ segmentIndex: index, text: String(raw.text ?? "").trim(), startMs: typeof raw.startMs === "number" ? raw.startMs : undefined, endMs: typeof raw.endMs === "number" ? raw.endMs : undefined, speaker: typeof raw.speaker === "string" ? raw.speaker : undefined, confidence: typeof raw.confidence === "number" ? raw.confidence : undefined })).filter((segment) => segment.text)
      : [{ segmentIndex: 0, text }];
    store.replaceTranscript(source.id, segments);
    store.updateSource(source.id, { transcriptText: text, extractedText: text, transcriptStatus: "ready", processingStatus: "pending", processingError: undefined });
    if (source.recordingSessionId) store.updateRecordingSession(source.recordingSessionId, { status: "uploaded" });
    queueSource(source.id);
    return sourceBundle(source.id);
  });
  app.post("/api/sources/:id/reprocess", async (request: any, reply) => {
    const source = store.getSource(request.params.id);
    if (!source) return reply.code(404).send({ error: "Source not found" });
    queueSource(source.id);
    return { ok: true, sourceId: source.id };
  });
  app.patch("/api/sources/:id", async (request: any, reply) => {
    const source = store.updateSource(request.params.id, { title: String(request.body?.title ?? "").trim() || undefined });
    if (!source) return reply.code(404).send({ error: "Source not found" });
    return source;
  });
  app.delete("/api/sources/:id", async (request: any, reply) => {
    if (!store.deleteSource(request.params.id)) return reply.code(404).send({ error: "Source not found" });
    return { ok: true };
  });

  app.patch("/api/recordings/:id/action-items/:actionItemId", async (request: any, reply) => {
    const source = store.getSource(request.params.id);
    const brief = source?.meetingBrief;
    const action = brief?.actionItems.find((item) => item.id === request.params.actionItemId);
    if (!source || !brief || !action) return reply.code(404).send({ error: "Action item not found" });
    const status = request.body?.status;
    if (status !== "open" && status !== "done") return reply.code(400).send({ error: "Invalid action item status" });
    action.status = status;
    if (request.body?.state === "confirmed" || request.body?.state === "edited") action.state = request.body.state;
    store.updateMeetingBrief(source.id, brief);
    return action;
  });

  app.get("/files/:id", async (request: any, reply) => {
    const source = store.getSource(request.params.id);
    if (!source?.filePath) return reply.code(404).send({ error: "File not found" });
    try {
      const stats = await fsp.stat(source.filePath);
      const mime = source.audioMimeType ?? source.mimeType ?? "application/octet-stream";
      const range = String(request.headers.range ?? "");
      if (!range.startsWith("bytes=")) return reply.headers({ "Accept-Ranges": "bytes", "Content-Length": String(stats.size) }).type(mime).send(fs.createReadStream(source.filePath));
      const [startText, endText] = range.slice(6).split("-");
      const start = Number(startText) || 0;
      const end = Math.min(endText ? Number(endText) : stats.size - 1, stats.size - 1);
      if (start >= stats.size || end < start) return reply.code(416).header("Content-Range", `bytes */${stats.size}`).send();
      return reply.code(206).headers({ "Accept-Ranges": "bytes", "Content-Range": `bytes ${start}-${end}/${stats.size}`, "Content-Length": String(end - start + 1) }).type(mime).send(fs.createReadStream(source.filePath, { start, end }));
    } catch {
      return reply.code(404).send({ error: "File not found" });
    }
  });

  app.get("/api/memories", async (request: any) => ({ memories: store.listMemories(request.query?.type) }));
  app.patch("/api/memories/:id", async (request: any, reply) => {
    const current = store.getMemory(request.params.id);
    if (!current) return reply.code(404).send({ error: "Memory not found" });
    return store.updateMemory(request.params.id, { content: typeof request.body?.content === "string" ? request.body.content.trim() : current.content, summary: typeof request.body?.summary === "string" ? request.body.summary.trim() : current.summary, status: request.body?.status ?? current.status });
  });
  app.get("/api/entities", async () => ({ entities: store.findEntities() }));
  app.get("/api/open-loops", async (request: any) => ({ openLoops: store.listLoops(request.query?.status) }));
  app.patch("/api/open-loops/:id", async (request: any, reply) => {
    const status = request.body?.status as LoopStatus;
    if (!["open", "resolved", "dismissed"].includes(status)) return reply.code(400).send({ error: "Invalid status" });
    const loop = store.updateLoop(request.params.id, status);
    if (!loop) return reply.code(404).send({ error: "Open loop not found" });
    return loop;
  });
  app.get("/api/search", async (request: any) => {
    const query = String(request.query?.q ?? "");
    return { query, results: query ? store.search(query, request.query?.type) : [] };
  });
  app.post("/api/ask", async (request: any, reply) => {
    const question = String(request.body?.question ?? "").trim();
    if (!question) return reply.code(400).send({ error: "Question is required" });
    const results = store.search(question);
    const context = results.slice(0, 8).map((result: any) => `- ${result.content}${result.supersededBy ? " (superseded)" : ""}${result.evidenceRefs?.[0]?.quote ? ` [evidence: ${result.evidenceRefs[0].quote}]` : ""}`).join("\n");
    const answer = await aiProvider.answerQuestion(question, context);
    return { answer, citations: results.slice(0, 5).map((result: any) => { const evidence = result.evidenceRefs?.[0]; return { memoryId: result.id, sourceId: result.sourceId, sourceTitle: result.source?.title, sourceType: result.source?.type, capturedAt: result.source?.capturedAt, content: result.content, superseded: Boolean(result.supersededBy), segmentId: evidence?.segmentId, startMs: evidence?.startMs, endMs: evidence?.endMs, quote: evidence?.quote }; }) };
  });
  app.get("/api/today", async () => { const recent = store.recentSources(); return { openLoops: store.listLoops("open").slice(0, 8), recent, resurfaced: store.resurfaced(), recordings: recent.filter((source) => source.type === "voice"), now: new Date().toISOString() }; });
  app.get("/api/settings/status", async () => ({ llmMode: config.llmMode === "mock" ? "mock" : "real", llmModel: config.llmModel || "Deterministic Mock AI", embeddingModel: process.env.EMBEDDING_MODEL ?? "Keyword retrieval (local)", transcriptionProvider: config.transcriptionProvider, transcriptionMode: transcriptionProvider ? "configured" : "not configured", transcriptionModel: config.transcriptionModel, transcriptionChunkSeconds: config.transcriptionChunkSeconds, storage: "local filesystem", database: "JSON repository (single API writer)", version: config.version }));
  app.get("/api/export", async () => store.exportData());

  return app;
}
