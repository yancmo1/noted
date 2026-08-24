import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

const required = ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", "D1_DATABASE_ID", "R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"];
const missing = required.filter((name) => !process.env[name]);
if (missing.length || process.env.IMPORT_CONFIRM !== "YES") {
  console.error(`Refusing to import. Set ${missing.join(", ") || "the required variables"} and IMPORT_CONFIRM=YES.`);
  process.exit(1);
}

const root = path.resolve(process.env.LOCAL_PROJECT_DIR ?? path.join(import.meta.dirname, "../.."));
const statePath = path.resolve(process.env.LOCAL_STATE_FILE ?? path.join(root, "storage/memory-garden.json"));
const state = JSON.parse(await fs.readFile(statePath, "utf8"));
const account = process.env.CLOUDFLARE_ACCOUNT_ID;
const database = process.env.D1_DATABASE_ID;
const bucket = process.env.R2_BUCKET ?? "noted-audio";
const d1URL = `https://api.cloudflare.com/client/v4/accounts/${account}/d1/database/${database}/query`;
const headers = { Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}`, "Content-Type": "application/json" };
const r2 = new S3Client({ region: "auto", endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`, credentials: { accessKeyId: process.env.R2_ACCESS_KEY_ID, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY } });
const iso = () => new Date().toISOString();
const j = (value, fallback = {}) => JSON.stringify(value ?? fallback);
const q = async (sql, params = []) => {
  const response = await fetch(d1URL, { method: "POST", headers, body: JSON.stringify({ sql, params }) });
  const payload = await response.json();
  if (!response.ok || !payload.success) throw new Error(`D1 import failed: ${JSON.stringify(payload.errors ?? payload)}`);
};
const exists = async (file) => Boolean(await fs.stat(file).catch(() => undefined));

let uploaded = 0;
for (const source of state.sources ?? []) {
  let fileKey = null;
  if (source.filePath) {
    const localPath = path.isAbsolute(source.filePath) ? source.filePath : path.resolve(root, source.filePath);
    if (await exists(localPath)) {
      fileKey = `audio/${source.id}/original`;
      await r2.send(new PutObjectCommand({ Bucket: bucket, Key: fileKey, Body: await fs.readFile(localPath), ContentType: source.audioMimeType ?? source.mimeType ?? "application/octet-stream" }));
      uploaded += 1;
    }
  }
  await q(`INSERT OR REPLACE INTO sources (id, client_recording_id, type, title, original_text, extracted_text, source_url, file_key, mime_type, audio_mime_type, captured_at, created_at, updated_at, processing_status, processing_error, metadata_json, summary, transcript_text, transcript_status, duration_ms, consent_mode, consent_acknowledged, recording_session_id, processing_version, meeting_brief_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, [source.id, source.metadata?.clientRecordingId ?? null, source.type, source.title, source.originalText ?? "", source.extractedText ?? "", source.sourceUrl ?? null, fileKey, source.mimeType ?? null, source.audioMimeType ?? null, source.capturedAt, source.createdAt, source.updatedAt, source.processingStatus ?? "partial", source.processingError ?? (source.filePath && !fileKey ? "Original file was not found during import." : null), j(source.metadata), source.summary ?? null, source.transcriptText ?? null, source.transcriptStatus ?? (source.type === "voice" ? "pending" : "not_applicable"), source.durationMs ?? null, source.consentMode ?? null, source.consentAcknowledged ? 1 : 0, source.recordingSessionId ?? null, source.processingVersion ?? 0, j(source.meetingBrief, null)]);
}
for (const session of state.recordingSessions ?? []) await q("INSERT OR REPLACE INTO recording_sessions (id, source_id, status, started_at, ended_at, duration_ms, mime_type, client, consent_mode, consent_acknowledged, metadata_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [session.id, session.sourceId, session.status, session.startedAt, session.endedAt ?? null, session.durationMs ?? null, session.mimeType ?? null, session.client, session.consentMode, session.consentAcknowledged ? 1 : 0, j(session.metadata)]);
for (const segment of state.transcriptSegments ?? []) await q("INSERT OR REPLACE INTO transcript_segments (id, source_id, segment_index, start_ms, end_ms, text, speaker, confidence, words_json, chunk_index, chunk_start_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [segment.id, segment.sourceId, segment.segmentIndex, segment.startMs ?? null, segment.endMs ?? null, segment.text, segment.speaker ?? null, segment.confidence ?? null, j(segment.words, []), segment.chunkIndex ?? null, segment.chunkStartMs ?? null]);
for (const chunk of state.chunks ?? []) await q("INSERT OR REPLACE INTO chunks (id, source_id, chunk_index, text, created_at) VALUES (?, ?, ?, ?, ?)", [chunk.id, chunk.sourceId, chunk.chunkIndex, chunk.text, chunk.createdAt]);
for (const memory of state.memories ?? []) await q("INSERT OR REPLACE INTO memories (id, source_id, memory_type, content, summary, importance, confidence, status, superseded_by, metadata_json, evidence_refs_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [memory.id, memory.sourceId, memory.memoryType, memory.content, memory.summary ?? "", memory.importance ?? 0.5, memory.confidence ?? 0.7, memory.status ?? "active", memory.supersededBy ?? null, j(memory.metadata), j(memory.evidenceRefs, []), memory.createdAt]);
for (const entity of state.entities ?? []) await q("INSERT OR REPLACE INTO entities (id, entity_type, canonical_name, description, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", [entity.id, entity.entityType, entity.canonicalName, entity.description ?? "", entity.createdAt, entity.updatedAt]);
for (const relationship of state.relationships ?? []) await q("INSERT OR REPLACE INTO relationships (id, source_id, from_type, from_id, relationship_type, to_type, to_id, confidence, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [relationship.id, relationship.sourceId, relationship.fromType, relationship.fromId, relationship.relationshipType, relationship.toType, relationship.toId, relationship.confidence ?? 0.7, relationship.createdAt]);
for (const loop of state.openLoops ?? []) await q("INSERT OR REPLACE INTO open_loops (id, memory_id, description, status, confidence, due_at, evidence_refs_json, created_at, resolved_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", [loop.id, loop.memoryId, loop.description, loop.status, loop.confidence ?? 0.7, loop.dueAt ?? null, j(loop.evidenceRefs, []), loop.createdAt, loop.resolvedAt ?? null]);
console.log(JSON.stringify({ statePath, sources: state.sources?.length ?? 0, uploadedAudio: uploaded, memories: state.memories?.length ?? 0, segments: state.transcriptSegments?.length ?? 0 }, null, 2));
