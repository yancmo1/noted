export interface Env {
  DB: D1Database;
  AUDIO_BUCKET: R2Bucket;
  PROCESSING_QUEUE: Queue<{ sourceId: string }>;
  APP_PASSWORD: string;
  GROQ_API_KEY: string;
  LLM_MODEL: string;
  TRANSCRIPTION_MODEL: string;
  R2_BUCKET?: string;
}

type SourceRow = Record<string, unknown> & { id: string; type: string; title: string; processing_status: string };
type Claim = { text: string; confidence?: number; evidence?: Array<{ segmentIndex: number; text: string }> };

const json = (value: unknown, init: ResponseInit = {}) => new Response(JSON.stringify(value), { ...init, headers: { "content-type": "application/json; charset=utf-8", ...(init.headers ?? {}) } });
const now = () => new Date().toISOString();
const id = () => crypto.randomUUID();
const parseJSON = <T>(value: unknown, fallback: T): T => { try { return value ? JSON.parse(String(value)) as T : fallback; } catch { return fallback; } };
const clamp = (value: unknown, fallback = 0.7) => typeof value === "number" && Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : fallback;
const text = (value: unknown) => typeof value === "string" ? value.trim() : "";

async function query<T = Record<string, unknown>>(db: D1Database, sql: string, ...params: unknown[]) {
  return (await db.prepare(sql).bind(...params).all<T>()).results;
}
async function first<T = Record<string, unknown>>(db: D1Database, sql: string, ...params: unknown[]) {
  return (await db.prepare(sql).bind(...params).first<T>()) ?? undefined;
}
async function run(db: D1Database, sql: string, ...params: unknown[]) {
  return db.prepare(sql).bind(...params).run();
}

function sourceFromRow(row: SourceRow) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    originalText: String(row.original_text ?? ""),
    extractedText: String(row.extracted_text ?? ""),
    sourceUrl: row.source_url ?? undefined,
    createdAt: String(row.created_at),
    updatedAt: String(row.updated_at),
    capturedAt: String(row.captured_at),
    processingStatus: row.processing_status,
    processingError: row.processing_error ?? undefined,
    metadata: parseJSON(row.metadata_json, {}),
    summary: row.summary ?? undefined,
    transcriptText: row.transcript_text ?? undefined,
    transcriptStatus: row.transcript_status,
    durationMs: row.duration_ms ?? undefined,
    audioMimeType: row.audio_mime_type ?? undefined,
    mimeType: row.mime_type ?? undefined,
    consentMode: row.consent_mode ?? undefined,
    consentAcknowledged: Boolean(row.consent_acknowledged),
    recordingSessionId: row.recording_session_id ?? undefined,
    meetingBrief: parseJSON(row.meeting_brief_json, undefined),
  };
}

async function currentSource(env: Env, sourceId: string) {
  const row = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE id = ?", sourceId);
  return row ? sourceFromRow(row) : undefined;
}

async function sourceBundle(env: Env, sourceId: string) {
  const sourceRow = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE id = ?", sourceId);
  if (!sourceRow) return undefined;
  const source = sourceFromRow(sourceRow);
  const session = await first(env.DB, "SELECT id, source_id as sourceId, status, started_at as startedAt, ended_at as endedAt, duration_ms as durationMs, mime_type as mimeType, client, consent_mode as consentMode, consent_acknowledged as consentAcknowledged FROM recording_sessions WHERE source_id = ?", sourceId);
  const segments = (await query<any>(env.DB, "SELECT id, source_id as sourceId, segment_index as segmentIndex, start_ms as startMs, end_ms as endMs, text, speaker, confidence, words_json, chunk_index as chunkIndex, chunk_start_ms as chunkStartMs FROM transcript_segments WHERE source_id = ? ORDER BY segment_index", sourceId)).map((row) => ({ ...row, words: parseJSON(row.words_json, undefined) }));
  const memories = (await query<any>(env.DB, "SELECT * FROM memories WHERE source_id = ? ORDER BY created_at DESC", sourceId)).map((row) => ({ id: row.id, sourceId: row.source_id, memoryType: row.memory_type, content: row.content, summary: row.summary, importance: row.importance, confidence: row.confidence, status: row.status, supersededBy: row.superseded_by, metadata: parseJSON(row.metadata_json, {}), evidenceRefs: parseJSON(row.evidence_refs_json, []) }));
  const memoryIds = memories.map((memory) => memory.id);
  const loops = memoryIds.length ? (await query<any>(env.DB, `SELECT * FROM open_loops WHERE memory_id IN (${memoryIds.map(() => "?").join(",")}) ORDER BY created_at DESC`, ...memoryIds)).map((row) => ({ id: row.id, memoryId: row.memory_id, description: row.description, status: row.status, confidence: row.confidence, dueAt: row.due_at, evidenceRefs: parseJSON(row.evidence_refs_json, []) })) : [];
  const entities = await query(env.DB, "SELECT DISTINCT e.id, e.entity_type as entityType, e.canonical_name as canonicalName, e.description FROM entities e JOIN relationships r ON r.to_id = e.id WHERE r.source_id = ? AND r.to_type = 'entity'", sourceId);
  return { source, recordingSession: session ? { ...session, consentAcknowledged: Boolean((session as any).consentAcknowledged) } : undefined, transcript: { text: source.transcriptText ?? "", segments }, memories, entities, openLoops: loops };
}

async function sessionToken(request: Request) {
  const cookie = request.headers.get("cookie")?.match(/(?:^|;\s*)mg_session=([^;]+)/)?.[1];
  const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return cookie || bearer;
}
async function hashToken(token: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, "0")).join("");
}
async function isAuthed(env: Env, request: Request) {
  const token = await sessionToken(request);
  if (!token) return false;
  const row = await first<{ token_hash: string; expires_at: string }>(env.DB, "SELECT token_hash, expires_at FROM sessions WHERE token_hash = ?", await hashToken(token));
  return Boolean(row && Date.parse(row.expires_at) > Date.now());
}
function cookie(token: string, maxAge = 60 * 60 * 24 * 30) { return `mg_session=${token}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${maxAge}`; }

async function enqueue(env: Env, sourceId: string) {
  const jobId = id();
  await run(env.DB, "INSERT OR IGNORE INTO jobs (id, source_id, status, attempts, created_at, updated_at) VALUES (?, ?, 'pending', 0, ?, ?)", jobId, sourceId, now(), now());
  await env.PROCESSING_QUEUE.send({ sourceId });
}

async function createVoiceSource(env: Env, data: { title: string; clientRecordingId: string; startedAt: string; endedAt: string; durationMs: number; mimeType: string; consentMode: string; consentAcknowledged: boolean; client?: string; fileKey: string }) {
  const existing = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE client_recording_id = ?", data.clientRecordingId);
  if (existing) return { source: sourceFromRow(existing), deduplicated: true };
  const sourceId = id(); const sessionId = id(); const timestamp = now();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO sources (id, client_recording_id, type, title, captured_at, created_at, updated_at, processing_status, transcript_status, metadata_json, file_key, mime_type, audio_mime_type, duration_ms, consent_mode, consent_acknowledged, recording_session_id) VALUES (?, ?, 'voice', ?, ?, ?, ?, 'pending', 'pending', ?, ?, ?, ?, ?, ?, ?, ?)").bind(sourceId, data.clientRecordingId, data.title || `Recording — ${data.startedAt}`, data.startedAt, timestamp, timestamp, JSON.stringify({ client: data.client ?? "native", clientRecordingId: data.clientRecordingId }), data.fileKey, data.mimeType, data.mimeType, data.durationMs, data.consentMode, data.consentAcknowledged ? 1 : 0, sessionId),
    env.DB.prepare("INSERT INTO recording_sessions (id, source_id, status, started_at, ended_at, duration_ms, mime_type, client, consent_mode, consent_acknowledged, metadata_json) VALUES (?, ?, 'uploaded', ?, ?, ?, ?, ?, ?, ?, '{}')").bind(sessionId, sourceId, data.startedAt, data.endedAt, data.durationMs, data.mimeType, data.client ?? "native", data.consentMode, data.consentAcknowledged ? 1 : 0),
  ]);
  return { source: await currentSource(env, sourceId), deduplicated: false };
}

async function createTextSource(env: Env, data: { type: string; title: string; originalText: string; sourceUrl?: string; metadata?: Record<string, unknown> }) {
  const sourceId = id();
  const timestamp = now();
  await run(env.DB, "INSERT INTO sources (id, type, title, original_text, extracted_text, source_url, captured_at, created_at, updated_at, processing_status, transcript_status, metadata_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 'not_applicable', ?)", sourceId, data.type, data.title, data.originalText, data.originalText, data.sourceUrl ?? null, timestamp, timestamp, timestamp, JSON.stringify(data.metadata ?? {}));
  await enqueue(env, sourceId);
  return currentSource(env, sourceId);
}

function normalizeClaims(items: unknown): Claim[] {
  return Array.isArray(items) ? items.map((item: any) => ({ text: text(item?.text), confidence: clamp(item?.confidence), evidence: Array.isArray(item?.evidence) ? item.evidence.map((e: any) => ({ segmentIndex: Math.max(0, Math.trunc(Number(e?.segmentIndex) || 0)), text: text(e?.text) })).filter((e: any) => e.text) : [] })).filter((item) => item.text) : [];
}

async function processSource(env: Env, sourceId: string) {
  const source = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE id = ?", sourceId);
  if (!source) return;
  const job = await first<{ id: string }>(env.DB, "SELECT id FROM jobs WHERE source_id = ? AND status IN ('pending', 'retry_scheduled', 'failed') ORDER BY created_at DESC LIMIT 1", sourceId);
  if (job) await run(env.DB, "UPDATE jobs SET status = 'processing', attempts = attempts + 1, lease_started_at = ?, updated_at = ? WHERE id = ?", now(), now(), job.id);
  await run(env.DB, "UPDATE sources SET processing_status = 'processing', processing_error = NULL, transcript_status = 'processing', updated_at = ? WHERE id = ?", now(), sourceId);
  try {
    if (source.type !== "voice" && (text(source.extracted_text) || text(source.original_text))) {
      await analyzeAndSave(env, source, text(source.extracted_text) || text(source.original_text), []);
      await run(env.DB, "UPDATE jobs SET status = 'complete', updated_at = ? WHERE source_id = ? AND status = 'processing'", now(), sourceId);
      return;
    }
    if (!source.file_key) {
      const sourceText = text(source.extracted_text) || text(source.original_text);
      if (!sourceText) throw new Error("This source has no text to process.");
      await analyzeAndSave(env, source, sourceText, []);
      return;
    }
    const object = await env.AUDIO_BUCKET.get(String(source.file_key));
    if (!object?.body) throw new Error("The audio object is missing from R2.");
    const audio = await object.arrayBuffer();
    if (audio.byteLength > 25 * 1024 * 1024) throw new Error("This recording is larger than Groq's current 25 MB speech upload limit.");
    const form = new FormData();
    form.append("file", new Blob([audio], { type: String(source.audio_mime_type ?? "audio/mp4") }), `${sourceId}.m4a`);
    form.append("model", env.TRANSCRIPTION_MODEL || "whisper-large-v3-turbo");
    form.append("response_format", "verbose_json");
    form.append("timestamp_granularities[]", "segment");
    form.append("timestamp_granularities[]", "word");
    const transcriptResponse = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", { method: "POST", headers: { Authorization: `Bearer ${env.GROQ_API_KEY}` }, body: form });
    if (!transcriptResponse.ok) throw new Error(`Groq transcription returned ${transcriptResponse.status}: ${await transcriptResponse.text()}`);
    const transcript = await transcriptResponse.json() as any;
    const transcriptText = text(transcript.text);
    if (!transcriptText) throw new Error("Groq returned no transcript text.");
    const segments = Array.isArray(transcript.segments) && transcript.segments.length ? transcript.segments : [{ text: transcriptText }];
    await env.DB.batch([
      env.DB.prepare("DELETE FROM transcript_segments WHERE source_id = ?").bind(sourceId),
      ...segments.map((segment: any, index: number) => env.DB.prepare("INSERT INTO transcript_segments (id, source_id, segment_index, start_ms, end_ms, text, speaker, confidence, words_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)").bind(id(), sourceId, index, typeof segment.start === "number" ? Math.round(segment.start * 1000) : null, typeof segment.end === "number" ? Math.round(segment.end * 1000) : null, text(segment.text), segment.speaker ?? null, typeof segment.avg_logprob === "number" ? clamp((segment.avg_logprob + 1) / 1) : null, JSON.stringify(segment.words ?? []))),
      env.DB.prepare("UPDATE sources SET transcript_text = ?, extracted_text = ?, transcript_status = 'ready', updated_at = ? WHERE id = ?").bind(transcriptText, transcriptText, now(), sourceId),
    ]);

    const evidenceSegments = segments.map((segment: any, index: number) => ({ segmentIndex: index, text: text(segment.text) }));
    await analyzeAndSave(env, source, transcriptText, evidenceSegments);
    await run(env.DB, "UPDATE jobs SET status = 'complete', updated_at = ? WHERE source_id = ? AND status = 'processing'", now(), sourceId);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Processing failed";
    await run(env.DB, "UPDATE jobs SET status = 'failed', error = ?, updated_at = ? WHERE source_id = ? AND status = 'processing'", message, now(), sourceId);
    await run(env.DB, "UPDATE sources SET processing_status = 'partial', processing_error = ?, transcript_status = CASE WHEN transcript_text IS NULL OR transcript_text = '' THEN 'failed' ELSE transcript_status END, updated_at = ? WHERE id = ?", message, now(), sourceId);
    throw error;
  }
}

async function analyzeAndSave(env: Env, source: SourceRow, sourceText: string, evidenceSegments: Array<{ segmentIndex: number; text: string }>) {
  const analysisResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", { method: "POST", headers: { Authorization: `Bearer ${env.GROQ_API_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ model: env.LLM_MODEL || "openai/gpt-oss-120b", messages: [{ role: "system", content: "Return concise JSON with summary, memories, entities, openLoops, relationships, and meeting. meeting contains keyPoints, decisions, actionItems, suggestedFollowUps, unresolvedQuestions. Use empty arrays when unsupported. Ground claims in the evidence segments." }, { role: "user", content: `Title: ${source.title}\nEvidence segments: ${JSON.stringify(evidenceSegments)}\nSource text:\n${sourceText}` }], response_format: { type: "json_object" }, temperature: 0.1 }) });
  if (!analysisResponse.ok) throw new Error(`Groq analysis returned ${analysisResponse.status}: ${await analysisResponse.text()}`);
  const analysisJSON = await analysisResponse.json() as any;
  let raw: any;
  try { raw = JSON.parse(String(analysisJSON.choices?.[0]?.message?.content ?? "{}")); } catch { throw new Error("Groq returned invalid analysis JSON."); }
  await saveAnalysis(env, source.id, source.title, sourceText, raw);
}

async function saveAnalysis(env: Env, sourceId: string, title: string, transcriptText: string, raw: any) {
  const memories = Array.isArray(raw.memories) ? raw.memories : [];
  const entities = Array.isArray(raw.entities) ? raw.entities : [];
  const loops = Array.isArray(raw.openLoops) ? raw.openLoops : [];
  const meeting = raw.meeting && typeof raw.meeting === "object" ? raw.meeting : {};
  const createdAt = now();
  const brief = { schemaVersion: 1, generatedAt: createdAt, summary: text(raw.summary) || text(meeting.summary), keyPoints: normalizeClaims(meeting.keyPoints).map((claim) => ({ id: id(), text: claim.text, confidence: clamp(claim.confidence), state: "generated", evidenceRefs: [] })), decisions: normalizeClaims(meeting.decisions).map((claim) => ({ id: id(), text: claim.text, confidence: clamp(claim.confidence), state: "generated", evidenceRefs: [] })), actionItems: normalizeClaims(meeting.actionItems).map((claim) => ({ id: id(), text: claim.text, confidence: clamp(claim.confidence), state: "generated", evidenceRefs: [], owner: null, dueAt: null, status: "open" })), suggestedFollowUps: normalizeClaims(meeting.suggestedFollowUps).map((claim) => ({ id: id(), text: claim.text, confidence: clamp(claim.confidence), state: "generated", evidenceRefs: [] })), unresolvedQuestions: normalizeClaims(meeting.unresolvedQuestions).map((claim) => ({ id: id(), text: claim.text, confidence: clamp(claim.confidence), state: "generated", evidenceRefs: [] })) };
  const statements: D1PreparedStatement[] = [
    env.DB.prepare("DELETE FROM open_loops WHERE memory_id IN (SELECT id FROM memories WHERE source_id = ?)").bind(sourceId),
    env.DB.prepare("DELETE FROM memories WHERE source_id = ?").bind(sourceId),
    env.DB.prepare("DELETE FROM relationships WHERE source_id = ?").bind(sourceId),
  ];
  for (const rawMemory of memories.slice(0, 20)) {
    const memoryId = id(); const content = text(rawMemory?.content ?? rawMemory?.text); if (!content) continue;
    const memoryType = ["fact", "decision", "idea", "task", "question", "preference", "reference", "observation", "event"].includes(rawMemory?.type) ? rawMemory.type : "observation";
    statements.push(env.DB.prepare("INSERT INTO memories (id, source_id, memory_type, content, summary, importance, confidence, status, metadata_json, evidence_refs_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'active', '{}', '[]', ?)").bind(memoryId, sourceId, memoryType, content, content, clamp(rawMemory?.importance, 0.5), clamp(rawMemory?.confidence), createdAt));
  }
  for (const rawEntity of entities.slice(0, 20)) {
    const entityName = text(rawEntity?.name); if (!entityName) continue;
    const entityType = ["person", "project", "organization", "product", "place", "topic", "technology", "document"].includes(rawEntity?.type) ? rawEntity.type : "topic";
    const entityId = id();
    statements.push(env.DB.prepare("INSERT INTO entities (id, entity_type, canonical_name, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(entity_type, canonical_name) DO UPDATE SET updated_at = excluded.updated_at").bind(entityId, entityType, entityName, text(rawEntity?.description), createdAt, createdAt));
    statements.push(env.DB.prepare("INSERT INTO relationships (id, source_id, from_type, from_id, relationship_type, to_type, to_id, confidence, created_at) SELECT ?, ?, 'source', ?, 'mentions', 'entity', id, ?, ? FROM entities WHERE entity_type = ? AND canonical_name = ?").bind(id(), sourceId, sourceId, clamp(rawEntity?.confidence), createdAt, entityType, entityName));
  }
  for (const rawLoop of loops.slice(0, 20)) {
    const description = text(rawLoop?.description ?? rawLoop?.text); if (!description) continue;
    const memoryId = id();
    statements.push(env.DB.prepare("INSERT INTO memories (id, source_id, memory_type, content, summary, importance, confidence, status, metadata_json, evidence_refs_json, created_at) VALUES (?, ?, 'task', ?, ?, 0.7, ?, 'active', '{}', '[]', ?)").bind(memoryId, sourceId, description, description, clamp(rawLoop?.confidence), createdAt));
    statements.push(env.DB.prepare("INSERT INTO open_loops (id, memory_id, description, status, confidence, due_at, evidence_refs_json, created_at) VALUES (?, ?, ?, 'open', ?, ?, '[]', ?)").bind(id(), memoryId, description, clamp(rawLoop?.confidence), rawLoop?.dueAt ?? null, createdAt));
  }
  statements.push(env.DB.prepare("UPDATE sources SET summary = ?, meeting_brief_json = ?, processing_status = 'ready', processing_error = NULL, transcript_status = CASE WHEN type = 'voice' THEN transcript_status ELSE 'not_applicable' END, processing_version = processing_version + 1, updated_at = ? WHERE id = ?").bind(brief.summary, JSON.stringify(brief), createdAt, sourceId));
  await env.DB.batch(statements);
}

async function handleRequest(request: Request, env: Env) {
  const url = new URL(request.url); const path = url.pathname;
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "content-type, authorization", "access-control-allow-methods": "GET,POST,PATCH,PUT,DELETE,OPTIONS" } });
  if (path === "/api/health") return json({ status: "ok", version: "cloudflare-0.1.0", now: now() });
  if (path === "/api/settings/status") return json({ llmMode: "real", llmModel: env.LLM_MODEL, transcriptionProvider: "groq", transcriptionMode: "configured", transcriptionModel: env.TRANSCRIPTION_MODEL, storage: "Cloudflare R2", database: "Cloudflare D1" });
  if (path === "/api/auth/status") return json({ authenticated: await isAuthed(env, request) });
  if (path === "/api/auth/login" && request.method === "POST") {
    const body = await request.json().catch(() => ({})) as any;
    if (!body.password || body.password !== env.APP_PASSWORD) return json({ error: "Incorrect password" }, { status: 401 });
    const token = crypto.randomUUID(); const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
    await run(env.DB, "INSERT INTO sessions (token_hash, expires_at) VALUES (?, ?)", await hashToken(token), expires);
    return json({ ok: true }, { headers: { "set-cookie": cookie(token) } });
  }
  if (path === "/api/auth/logout" && request.method === "POST") {
    const token = await sessionToken(request); if (token) await run(env.DB, "DELETE FROM sessions WHERE token_hash = ?", await hashToken(token));
    return json({ ok: true }, { headers: { "set-cookie": cookie("", 0) } });
  }
  if (!(await isAuthed(env, request))) return json({ error: "Authentication required" }, { status: 401 });

  if (path === "/api/capture/note" && request.method === "POST") {
    const body = await request.json().catch(() => ({})) as any;
    const note = text(body.text);
    if (!note) return json({ error: "Note text is required" }, { status: 400 });
    return json(await createTextSource(env, { type: "note", title: text(body.title) || "Quick note", originalText: note }));
  }
  if (path === "/api/capture/url" && request.method === "POST") {
    const body = await request.json().catch(() => ({})) as any;
    const sourceUrl = text(body.url);
    try { new URL(sourceUrl); } catch { return json({ error: "Enter a valid URL" }, { status: 400 }); }
    return json(await createTextSource(env, { type: "url", title: text(body.title) || sourceUrl, originalText: sourceUrl, sourceUrl }));
  }
  if (path === "/api/capture/file" && request.method === "POST") {
    const form = await request.formData();
    const file = form.get("file");
    if (!(file instanceof File)) return json({ error: "A file is required" }, { status: 400 });
    if (file.size > 25 * 1024 * 1024) return json({ error: "Uploaded file exceeds the 25 MB limit." }, { status: 413 });
    const sourceId = id();
    const key = `files/${sourceId}/${file.name.replace(/[^a-zA-Z0-9._-]/g, "_") || "upload"}`;
    await env.AUDIO_BUCKET.put(key, file.stream(), { httpMetadata: { contentType: file.type || "application/octet-stream" } });
    const textBody = /text\/(plain|markdown)/i.test(file.type) || /\.(md|txt)$/i.test(file.name) ? await file.text() : "";
    const timestamp = now();
    await run(env.DB, "INSERT INTO sources (id, type, title, original_text, extracted_text, captured_at, created_at, updated_at, processing_status, transcript_status, file_key, mime_type, metadata_json) VALUES (?, ?, ?, '', ?, ?, ?, ?, 'pending', 'not_applicable', ?, ?, ?)", sourceId, /image\//i.test(file.type) ? "image" : "file", file.name || "Uploaded file", textBody, timestamp, timestamp, timestamp, key, file.type || "application/octet-stream", JSON.stringify({ size: file.size }));
    await enqueue(env, sourceId);
    return json(await currentSource(env, sourceId));
  }
  if (path === "/api/capture/voice" && request.method === "POST") {
    const form = await request.formData();
    const file = form.get("file");
    if (!(file instanceof File)) return json({ error: "A file is required" }, { status: 400 });
    if (file.size > 25 * 1024 * 1024) return json({ error: "Uploaded file exceeds Groq's current 25 MB speech limit." }, { status: 413 });
    const clientRecordingId = text(form.get("clientRecordingId")) || id();
    const mimeType = file.type || "audio/mp4";
    const mode = text(form.get("consentMode")) || "private_thought";
    const acknowledged = form.get("consentAcknowledged") === "true" || form.get("consentAcknowledged") === "1";
    if ((mode === "conversation" || mode === "meeting") && !acknowledged) return json({ error: "Consent acknowledgement is required for conversation or meeting mode" }, { status: 400 });
    const startedAt = text(form.get("startedAt")) || now();
    const endedAt = text(form.get("endedAt")) || now();
    const created = await createVoiceSource(env, { title: text(form.get("title")) || "Untitled Recording", clientRecordingId, startedAt, endedAt, durationMs: Math.max(0, Number(form.get("durationMs")) || 0), mimeType, consentMode: mode, consentAcknowledged: acknowledged, client: text(form.get("client")) || "web", fileKey: `audio/${clientRecordingId}.m4a` });
    if (!created.deduplicated) {
      await env.AUDIO_BUCKET.put(`audio/${clientRecordingId}.m4a`, file.stream(), { httpMetadata: { contentType: mimeType } });
      await enqueue(env, created.source!.id);
    }
    return json({ ...created.source, recordingSession: await first(env.DB, "SELECT id, source_id as sourceId, status, started_at as startedAt, ended_at as endedAt, duration_ms as durationMs, mime_type as mimeType, client, consent_mode as consentMode, consent_acknowledged as consentAcknowledged FROM recording_sessions WHERE source_id = ?", created.source!.id), deduplicated: created.deduplicated });
  }

  if (path === "/api/recordings/upload-url" && request.method === "POST") {
    const body = await request.json().catch(() => ({})) as any;
    const clientRecordingId = text(body.clientRecordingId); if (!clientRecordingId) return json({ error: "clientRecordingId is required" }, { status: 400 });
    const mimeType = text(body.mimeType) || "audio/mp4"; const fileKey = `audio/${clientRecordingId}.m4a`;
    const created = await createVoiceSource(env, { title: text(body.title) || "Untitled Recording", clientRecordingId, startedAt: text(body.startedAt) || now(), endedAt: text(body.endedAt) || now(), durationMs: Math.max(0, Number(body.durationMs) || 0), mimeType, consentMode: text(body.consentMode) || "private_thought", consentAcknowledged: Boolean(body.consentAcknowledged), client: "native", fileKey });
    if (created.deduplicated) return json({ source: created.source, deduplicated: true, uploadURL: null, uploadHeaders: {} });
    return json({ source: created.source, deduplicated: false, uploadURL: new URL(`/api/recordings/${created.source!.id}/upload`, request.url).toString(), uploadHeaders: { "Content-Type": mimeType } });
  }
  const uploadMatch = path.match(/^\/api\/recordings\/([^/]+)\/upload$/);
  if (uploadMatch && request.method === "PUT") {
    const sourceRow = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE id = ?", uploadMatch[1]);
    if (!sourceRow?.file_key) return json({ error: "Recording not found" }, { status: 404 });
    const contentLength = Number(request.headers.get("content-length") ?? 0);
    if (contentLength > 25 * 1024 * 1024) return json({ error: "Recording exceeds the current 25 MB processing limit." }, { status: 413 });
    if (!request.body) return json({ error: "Audio data is required" }, { status: 400 });
    await env.AUDIO_BUCKET.put(String(sourceRow.file_key), request.body, { httpMetadata: { contentType: request.headers.get("content-type") || String(sourceRow.audio_mime_type ?? "audio/mp4") } });
    return json({ ok: true });
  }
  const completeMatch = path.match(/^\/api\/recordings\/([^/]+)\/complete$/);
  if (completeMatch && request.method === "POST") {
    const sourceRow = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE id = ?", completeMatch[1]); if (!sourceRow) return json({ error: "Recording not found" }, { status: 404 });
    const object = await env.AUDIO_BUCKET.head(String(sourceRow.file_key)); if (!object) return json({ error: "The audio upload has not reached R2 yet." }, { status: 409 });
    await run(env.DB, "UPDATE sources SET processing_status = 'pending', updated_at = ? WHERE id = ?", now(), completeMatch[1]); await enqueue(env, completeMatch[1]);
    return json({ ...(sourceFromRow(sourceRow)), processingStatus: "pending", deduplicated: false });
  }
  if (path === "/api/sources" && request.method === "GET") {
    const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") ?? 50))); const offset = Math.max(0, Number(url.searchParams.get("offset") ?? 0));
    const rows = await query<SourceRow>(env.DB, "SELECT * FROM sources ORDER BY captured_at DESC LIMIT ? OFFSET ?", limit, offset); return json({ sources: rows.map(sourceFromRow) });
  }
  const clientMatch = path.match(/^\/api\/recordings\/by-client-id\/([^/]+)$/);
  if (clientMatch && request.method === "GET") { const row = await first<SourceRow>(env.DB, "SELECT * FROM sources WHERE client_recording_id = ?", clientMatch[1]); if (!row) return json({ error: "Recording not found" }, { status: 404 }); return json({ ...sourceFromRow(row), deduplicated: true }); }
  const sourceMatch = path.match(/^\/api\/sources\/([^/]+)$/);
  if (sourceMatch && request.method === "GET") { const bundle = await sourceBundle(env, sourceMatch[1]); return bundle ? json(bundle) : json({ error: "Source not found" }, { status: 404 }); }
  const recordingMatch = path.match(/^\/api\/recordings\/([^/]+)$/);
  if (recordingMatch && request.method === "GET") { const bundle = await sourceBundle(env, recordingMatch[1]); return bundle?.source.type === "voice" ? json(bundle) : json({ error: "Recording not found" }, { status: 404 }); }
  if (sourceMatch && request.method === "PATCH") { const title = text((await request.json().catch(() => ({})) as any).title); const result = await run(env.DB, "UPDATE sources SET title = ?, updated_at = ? WHERE id = ?", title || "Untitled", now(), sourceMatch[1]); return result.meta.changes ? json(await currentSource(env, sourceMatch[1])) : json({ error: "Source not found" }, { status: 404 }); }
  if (sourceMatch && request.method === "DELETE") { const row = await first<SourceRow>(env.DB, "SELECT file_key FROM sources WHERE id = ?", sourceMatch[1]); if (!row) return json({ error: "Source not found" }, { status: 404 }); await env.DB.batch([env.DB.prepare("DELETE FROM sources WHERE id = ?").bind(sourceMatch[1]), env.DB.prepare("DELETE FROM sessions WHERE expires_at < ?").bind(now())]); if (row.file_key) await env.AUDIO_BUCKET.delete(String(row.file_key)); return json({ ok: true }); }
  const reprocessMatch = path.match(/^\/api\/sources\/([^/]+)\/reprocess$/);
  if (reprocessMatch && request.method === "POST") { const row = await first(env.DB, "SELECT id FROM sources WHERE id = ?", reprocessMatch[1]); if (!row) return json({ error: "Source not found" }, { status: 404 }); await run(env.DB, "UPDATE sources SET processing_status = 'pending', processing_error = NULL, updated_at = ? WHERE id = ?", now(), reprocessMatch[1]); await enqueue(env, reprocessMatch[1]); return json({ ok: true, sourceId: reprocessMatch[1] }); }
  const transcriptMatch = path.match(/^\/api\/recordings\/([^/]+)\/transcript$/);
  if (transcriptMatch && request.method === "GET") { const bundle = await sourceBundle(env, transcriptMatch[1]); return bundle ? json(bundle.transcript) : json({ error: "Recording not found" }, { status: 404 }); }
  if (transcriptMatch && request.method === "PATCH") { const body = await request.json().catch(() => ({})) as any; const transcriptText = text(body.text); if (!transcriptText) return json({ error: "Transcript text is required" }, { status: 400 }); await run(env.DB, "UPDATE sources SET transcript_text = ?, extracted_text = ?, transcript_status = 'ready', processing_status = 'pending', processing_error = NULL, updated_at = ? WHERE id = ?", transcriptText, transcriptText, now(), transcriptMatch[1]); await enqueue(env, transcriptMatch[1]); return json(await sourceBundle(env, transcriptMatch[1])); }
  const actionMatch = path.match(/^\/api\/recordings\/([^/]+)\/action-items\/([^/]+)$/);
  if (actionMatch && request.method === "PATCH") {
    const body = await request.json().catch(() => ({})) as any;
    const sourceRow = await first<SourceRow>(env.DB, "SELECT meeting_brief_json FROM sources WHERE id = ?", actionMatch[1]);
    const brief = parseJSON<any>(sourceRow?.meeting_brief_json, undefined);
    const action = brief?.actionItems?.find((item: any) => item.id === actionMatch[2]);
    if (!action) return json({ error: "Action item not found" }, { status: 404 });
    if (body.status !== "open" && body.status !== "done") return json({ error: "Invalid action item status" }, { status: 400 });
    action.status = body.status; if (body.state === "confirmed" || body.state === "edited") action.state = body.state;
    await run(env.DB, "UPDATE sources SET meeting_brief_json = ?, updated_at = ? WHERE id = ?", JSON.stringify(brief), now(), actionMatch[1]);
    return json(action);
  }
  const fileMatch = path.match(/^\/files\/([^/]+)$/);
  if (fileMatch && request.method === "GET") { const row = await first<SourceRow>(env.DB, "SELECT file_key, audio_mime_type, mime_type FROM sources WHERE id = ?", fileMatch[1]); if (!row?.file_key) return json({ error: "File not found" }, { status: 404 }); const range = request.headers.get("range"); const object = await env.AUDIO_BUCKET.get(String(row.file_key), range ? { range: request.headers } : undefined); if (!object?.body) return json({ error: "File not found" }, { status: 404 }); const headers = new Headers(); object.writeHttpMetadata(headers); headers.set("accept-ranges", "bytes"); headers.set("etag", object.httpEtag); return new Response(object.body, { status: range ? 206 : 200, headers }); }
  if (path === "/api/memories" && request.method === "GET") { const typeFilter = url.searchParams.get("type"); const rows = await query<any>(env.DB, `SELECT * FROM memories WHERE status = 'active' ${typeFilter ? "AND memory_type = ?" : ""} ORDER BY created_at DESC`, ...(typeFilter ? [typeFilter] : [])); return json({ memories: rows.map((row) => ({ id: row.id, sourceId: row.source_id, memoryType: row.memory_type, content: row.content, summary: row.summary, confidence: row.confidence, supersededBy: row.superseded_by, evidenceRefs: parseJSON(row.evidence_refs_json, []) })) }); }
  if (path === "/api/entities" && request.method === "GET") return json({ entities: await query(env.DB, "SELECT id, entity_type as entityType, canonical_name as canonicalName, description, created_at as createdAt, updated_at as updatedAt FROM entities ORDER BY updated_at DESC") });
  if (path === "/api/open-loops" && request.method === "GET") { const statusFilter = url.searchParams.get("status"); const rows = await query<any>(env.DB, `SELECT * FROM open_loops ${statusFilter ? "WHERE status = ?" : ""} ORDER BY created_at DESC`, ...(statusFilter ? [statusFilter] : [])); return json({ openLoops: rows.map((row) => ({ id: row.id, memoryId: row.memory_id, description: row.description, status: row.status, confidence: row.confidence, dueAt: row.due_at, evidenceRefs: parseJSON(row.evidence_refs_json, []) })) }); }
  const loopMatch = path.match(/^\/api\/open-loops\/([^/]+)$/);
  if (loopMatch && request.method === "PATCH") { const status = (await request.json().catch(() => ({})) as any).status; if (!["open", "resolved", "dismissed"].includes(status)) return json({ error: "Invalid status" }, { status: 400 }); const result = await run(env.DB, "UPDATE open_loops SET status = ?, resolved_at = ? WHERE id = ?", status, status === "open" ? null : now(), loopMatch[1]); return result.meta.changes ? json(await first(env.DB, "SELECT id, memory_id as memoryId, description, status, confidence, due_at as dueAt FROM open_loops WHERE id = ?", loopMatch[1])) : json({ error: "Open loop not found" }, { status: 404 }); }
  if (path === "/api/today" && request.method === "GET") { const recentRows = await query<SourceRow>(env.DB, "SELECT * FROM sources ORDER BY captured_at DESC LIMIT 8"); const loops = await query(env.DB, "SELECT id, memory_id as memoryId, description, status, confidence, due_at as dueAt FROM open_loops WHERE status = 'open' ORDER BY created_at DESC LIMIT 8"); return json({ openLoops: loops, recent: recentRows.map(sourceFromRow), recordings: recentRows.filter((row) => row.type === "voice").map(sourceFromRow), resurfaced: [], now: now() }); }
  if (path === "/api/search" && request.method === "GET") {
    const q = text(url.searchParams.get("q"));
    if (!q) return json({ query: q, results: [] });
    const typeFilter = text(url.searchParams.get("type"));
    const rows = await query<any>(env.DB, `SELECT m.*, s.title as source_title, s.type as source_type, s.captured_at as source_captured_at FROM memories m JOIN sources s ON s.id = m.source_id WHERE m.status = 'active' AND (m.content LIKE ? OR m.summary LIKE ?) ${typeFilter ? "AND m.memory_type = ?" : ""} ORDER BY m.created_at DESC LIMIT 50`, ...(typeFilter ? [`%${q}%`, `%${q}%`, typeFilter] : [`%${q}%`, `%${q}%`]));
    return json({ query: q, results: rows.map((row) => ({ id: row.id, sourceId: row.source_id, memoryType: row.memory_type, content: row.content, summary: row.summary, confidence: row.confidence, supersededBy: row.superseded_by, source: { id: row.source_id, title: row.source_title, type: row.source_type, capturedAt: row.source_captured_at }, evidenceRefs: parseJSON(row.evidence_refs_json, []) })) });
  }
  if (path === "/api/ask" && request.method === "POST") {
    const body = await request.json().catch(() => ({})) as any;
    const question = text(body.question); if (!question) return json({ error: "Question is required" }, { status: 400 });
    const rows = await query<any>(env.DB, "SELECT m.*, s.title as source_title, s.type as source_type, s.captured_at as source_captured_at FROM memories m JOIN sources s ON s.id = m.source_id WHERE m.status = 'active' ORDER BY m.created_at DESC LIMIT 100");
    const relevant = rows.filter((row) => `${row.content} ${row.summary}`.toLowerCase().includes(question.toLowerCase())).slice(0, 8);
    const context = (relevant.length ? relevant : rows.slice(0, 8)).map((row) => `- ${row.content}`).join("\n");
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", { method: "POST", headers: { Authorization: `Bearer ${env.GROQ_API_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify({ model: env.LLM_MODEL || "openai/gpt-oss-120b", messages: [{ role: "system", content: "Answer only from the supplied memory context. If the context is insufficient, say so plainly." }, { role: "user", content: `Question: ${question}\nMemory context:\n${context}` }], temperature: 0.1 }) });
    if (!response.ok) return json({ error: `Groq answer returned ${response.status}` }, { status: 502 });
    const answerJSON = await response.json() as any;
    const answer = text(answerJSON.choices?.[0]?.message?.content) || "I could not find enough evidence in Noted.";
    return json({ answer, citations: (relevant.length ? relevant : rows.slice(0, 5)).slice(0, 5).map((row) => { const evidence = parseJSON<Record<string, unknown>[]>(row.evidence_refs_json, [])[0] ?? {}; return { memoryId: row.id, sourceId: row.source_id, sourceTitle: row.source_title, sourceType: row.source_type, capturedAt: row.source_captured_at, content: row.content, superseded: Boolean(row.superseded_by), ...evidence }; }) });
  }
  if (path === "/api/export" && request.method === "GET") { const tables = ["sources", "recording_sessions", "transcript_segments", "memories", "entities", "relationships", "open_loops"]; const output: Record<string, unknown> = {}; for (const table of tables) output[table] = await query(env.DB, `SELECT * FROM ${table}`); return json(output); }
  return json({ error: "Not found" }, { status: 404 });
}

export default {
  fetch(request: Request, env: Env) { return handleRequest(request, env); },
  async queue(batch: MessageBatch<{ sourceId: string }>, env: Env) { for (const message of batch.messages) { try { await processSource(env, message.body.sourceId); message.ack(); } catch { message.retry(); } } },
};
