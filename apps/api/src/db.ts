import fs from "node:fs";
import path from "node:path";
import { config } from "./config.js";
import type {
  Chunk,
  Entity,
  JobStatus,
  MeetingBrief,
  Memory,
  OpenLoop,
  ProcessingJob,
  RecordingSession,
  Relationship,
  Source,
  TranscriptSegment,
} from "./types.js";

export const STORAGE_VERSION = 3;

type State = {
  storageVersion: number;
  sources: Source[];
  memories: Memory[];
  entities: Entity[];
  relationships: Relationship[];
  openLoops: OpenLoop[];
  chunks: Chunk[];
  jobs: ProcessingJob[];
  recordingSessions: RecordingSession[];
  transcriptSegments: TranscriptSegment[];
  [key: string]: unknown;
};

const file = path.join(config.dataDir, "memory-garden.json");
fs.mkdirSync(path.join(config.dataDir, "uploads", "incoming"), { recursive: true });

const defaultState = (): State => ({
  storageVersion: STORAGE_VERSION,
  sources: [],
  memories: [],
  entities: [],
  relationships: [],
  openLoops: [],
  chunks: [],
  jobs: [],
  recordingSessions: [],
  transcriptSegments: [],
});

const objectValue = (raw: unknown): Record<string, unknown> => (
  raw && typeof raw === "object" && !Array.isArray(raw) ? raw as Record<string, unknown> : {}
);

export function normalizeState(raw: unknown): State {
  const input = objectValue(raw);
  const out: State = { ...defaultState(), ...input, storageVersion: STORAGE_VERSION } as State;
  out.sources = Array.isArray(input.sources)
    ? (input.sources as Source[]).map((source) => ({
      ...source,
      metadata: source.metadata ?? {},
      transcriptStatus: source.transcriptStatus ?? (source.type === "voice" ? "pending" : "not_applicable"),
    }))
    : [];
  out.memories = Array.isArray(input.memories) ? input.memories as Memory[] : [];
  out.entities = Array.isArray(input.entities) ? input.entities as Entity[] : [];
  out.relationships = Array.isArray(input.relationships) ? input.relationships as Relationship[] : [];
  out.openLoops = Array.isArray(input.openLoops) ? input.openLoops as OpenLoop[] : [];
  out.chunks = Array.isArray(input.chunks) ? input.chunks as Chunk[] : [];
  out.jobs = Array.isArray(input.jobs)
    ? (input.jobs as ProcessingJob[]).map((job) => ({
      ...job,
      status: job.status === "processing" || job.status === "complete" || job.status === "failed" || job.status === "retry_scheduled"
        ? job.status
        : "pending",
      attempts: Number(job.attempts ?? 0),
    }))
    : [];
  out.recordingSessions = Array.isArray(input.recordingSessions) ? input.recordingSessions as RecordingSession[] : [];
  out.transcriptSegments = Array.isArray(input.transcriptSegments) ? input.transcriptSegments as TranscriptSegment[] : [];
  return out;
}

let state: State = defaultState();
try {
  if (fs.existsSync(file)) state = normalizeState(JSON.parse(fs.readFileSync(file, "utf8")));
} catch {
  state = defaultState();
}

const now = () => new Date().toISOString();
const save = () => {
  const temporary = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(temporary, JSON.stringify(state, null, 2));
  fs.renameSync(temporary, file);
};

function activeJobForSource(sourceId: string) {
  return state.jobs.find((job) => job.sourceId === sourceId && ["pending", "processing", "retry_scheduled"].includes(job.status));
}

export const store = {
  createSource(input: Partial<Source> & { type: Source["type"]; title: string }) {
    const timestamp = now();
    const source: Source = {
      id: input.id ?? crypto.randomUUID(),
      type: input.type,
      title: input.title,
      originalText: input.originalText ?? "",
      extractedText: input.extractedText ?? "",
      sourceUrl: input.sourceUrl,
      filePath: input.filePath,
      mimeType: input.mimeType,
      createdAt: timestamp,
      updatedAt: timestamp,
      capturedAt: input.capturedAt ?? timestamp,
      processingStatus: input.processingStatus ?? "pending",
      processingError: input.processingError,
      metadata: input.metadata ?? {},
      summary: input.summary,
      transcriptText: input.transcriptText,
      transcriptStatus: input.transcriptStatus ?? (input.type === "voice" ? "pending" : "not_applicable"),
      durationMs: input.durationMs,
      audioMimeType: input.audioMimeType,
      consentMode: input.consentMode,
      consentAcknowledged: input.consentAcknowledged,
      recordingSessionId: input.recordingSessionId,
      processingVersion: input.processingVersion ?? 0,
      meetingBrief: input.meetingBrief,
    };
    state.sources.push(source);
    save();
    return source;
  },

  findSourceByClientRecordingId(clientRecordingId: string) {
    return state.sources.find((source) => source.type === "voice" && source.metadata?.clientRecordingId === clientRecordingId);
  },

  createVoiceSourceIfAbsent(input: Partial<Source> & { id: string; title: string; clientRecordingId: string }) {
    const existing = this.findSourceByClientRecordingId(input.clientRecordingId);
    if (existing) return { source: existing, created: false };
    const source = this.createSource({
      ...input,
      type: "voice",
      metadata: { ...(input.metadata ?? {}), clientRecordingId: input.clientRecordingId },
    });
    return { source, created: true };
  },

  getSource(id: string) {
    return state.sources.find((source) => source.id === id);
  },

  listSources(limit = 50, offset = 0) {
    return state.sources.slice().sort((a, b) => b.capturedAt.localeCompare(a.capturedAt)).slice(offset, offset + limit);
  },

  updateSource(id: string, patch: Partial<Source>) {
    const source = this.getSource(id);
    if (!source) return;
    Object.assign(source, patch, { updatedAt: now() });
    save();
    return source;
  },

  createRecordingSession(input: Omit<RecordingSession, "id">) {
    const session: RecordingSession = { ...input, id: crypto.randomUUID() };
    state.recordingSessions.push(session);
    save();
    return session;
  },

  getRecordingSession(id: string) {
    return state.recordingSessions.find((session) => session.id === id);
  },

  getRecordingSessionForSource(sourceId: string) {
    return state.recordingSessions.find((session) => session.sourceId === sourceId);
  },

  updateRecordingSession(id: string, patch: Partial<RecordingSession>) {
    const session = this.getRecordingSession(id);
    if (!session) return;
    Object.assign(session, patch);
    save();
    return session;
  },

  createJob(sourceId: string) {
    const active = activeJobForSource(sourceId);
    if (active) return active.id;
    const timestamp = now();
    const job: ProcessingJob = {
      id: crypto.randomUUID(),
      sourceId,
      status: "pending",
      attempts: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    state.jobs.push(job);
    save();
    return job.id;
  },

  getJob(id: string) {
    return state.jobs.find((job) => job.id === id);
  },

  claimJob(id: string) {
    const job = this.getJob(id);
    if (!job) return;
    job.status = "processing";
    job.attempts += 1;
    job.leaseStartedAt = now();
    job.updatedAt = now();
    save();
    return job;
  },

  updateJob(id: string, status: JobStatus, error?: string, nextAttemptAt?: string) {
    const job = this.getJob(id);
    if (!job) return;
    job.status = status;
    job.error = error;
    job.nextAttemptAt = nextAttemptAt;
    job.leaseStartedAt = status === "processing" ? job.leaseStartedAt : undefined;
    job.updatedAt = now();
    save();
    return job;
  },

  pendingJobs(at = Date.now()) {
    return state.jobs.filter((job) => (
      (job.status === "pending" || (job.status === "retry_scheduled" && (!job.nextAttemptAt || Date.parse(job.nextAttemptAt) <= at)))
    ));
  },

  recoverStaleJobs(maxAgeMs: number, at = Date.now()) {
    let changed = false;
    for (const job of state.jobs) {
      if (job.status !== "processing" || !job.leaseStartedAt) continue;
      if (at - Date.parse(job.leaseStartedAt) <= maxAgeMs) continue;
      job.status = "retry_scheduled";
      job.nextAttemptAt = new Date(at).toISOString();
      job.error = "Recovered a processing job after an API restart.";
      job.updatedAt = new Date(at).toISOString();
      changed = true;
    }
    if (changed) save();
  },

  createMemory(input: Omit<Memory, "createdAt"> & { createdAt?: string }) {
    const memory = { ...input, createdAt: input.createdAt ?? now() };
    state.memories.push(memory);
    save();
    return memory;
  },

  getMemory(id: string) {
    return state.memories.find((memory) => memory.id === id);
  },

  listMemories(type?: string) {
    return state.memories.filter((memory) => memory.status === "active" && (!type || memory.memoryType === type)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },

  updateMemory(id: string, patch: Partial<Memory>) {
    const memory = this.getMemory(id);
    if (!memory) return;
    Object.assign(memory, patch);
    save();
    return memory;
  },

  memoriesForSource(sourceId: string) {
    return state.memories.filter((memory) => memory.sourceId === sourceId).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  },

  clearDerived(sourceId: string) {
    const memoryIds = new Set(state.memories.filter((memory) => memory.sourceId === sourceId).map((memory) => memory.id));
    state.memories = state.memories.filter((memory) => memory.sourceId !== sourceId);
    state.openLoops = state.openLoops.filter((loop) => !memoryIds.has(loop.memoryId));
    state.relationships = state.relationships.filter((relationship) => relationship.sourceId !== sourceId);
    state.chunks = state.chunks.filter((chunk) => chunk.sourceId !== sourceId);
    const source = this.getSource(sourceId);
    if (source) source.meetingBrief = undefined;
    save();
  },

  updateMeetingBrief(sourceId: string, meetingBrief: MeetingBrief | undefined) {
    return this.updateSource(sourceId, { meetingBrief });
  },

  findEntities() {
    return state.entities.slice().sort((a, b) => b.updatedAt.localeCompare(a.updatedAt));
  },

  upsertEntity(type: Entity["entityType"], name: string, description = "") {
    const canonical = name.trim().replace(/\s+/g, " ");
    const old = state.entities.find((entity) => entity.entityType === type && entity.canonicalName.toLowerCase() === canonical.toLowerCase());
    if (old) return old;
    const timestamp = now();
    const entity: Entity = { id: crypto.randomUUID(), entityType: type, canonicalName: canonical, description, createdAt: timestamp, updatedAt: timestamp };
    state.entities.push(entity);
    save();
    return entity;
  },

  entitiesForSource(sourceId: string) {
    const ids = new Set(state.relationships.filter((relationship) => relationship.sourceId === sourceId && relationship.toType === "entity").map((relationship) => relationship.toId));
    return state.entities.filter((entity) => ids.has(entity.id));
  },

  addRelationship(input: Omit<Relationship, "id" | "createdAt">) {
    state.relationships.push({ ...input, id: crypto.randomUUID(), createdAt: now() });
    save();
  },

  addLoop(input: Omit<OpenLoop, "id" | "createdAt"> & { createdAt?: string }) {
    const loop: OpenLoop = { ...input, id: crypto.randomUUID(), createdAt: input.createdAt ?? now() };
    state.openLoops.push(loop);
    save();
    return loop;
  },

  listLoops(status?: string) {
    return state.openLoops.filter((loop) => !status || loop.status === status).sort((a, b) => (a.status === "open" ? 0 : 1) - (b.status === "open" ? 0 : 1) || b.createdAt.localeCompare(a.createdAt));
  },

  getLoop(id: string) {
    return state.openLoops.find((loop) => loop.id === id);
  },

  updateLoop(id: string, status: OpenLoop["status"]) {
    const loop = this.getLoop(id);
    if (!loop) return;
    loop.status = status;
    loop.resolvedAt = status === "open" ? undefined : now();
    save();
    return loop;
  },

  replaceChunks(sourceId: string, parts: string[]) {
    state.chunks = state.chunks.filter((chunk) => chunk.sourceId !== sourceId);
    const chunks = parts.map((text, index) => ({ id: crypto.randomUUID(), sourceId, chunkIndex: index, text: text.trim(), createdAt: now() }));
    state.chunks.push(...chunks);
    save();
    return chunks;
  },

  transcriptForSource(sourceId: string) {
    return state.transcriptSegments.filter((segment) => segment.sourceId === sourceId).sort((a, b) => a.segmentIndex - b.segmentIndex);
  },

  replaceTranscript(sourceId: string, segments: Array<Omit<TranscriptSegment, "id" | "sourceId" | "createdAt">>) {
    state.transcriptSegments = state.transcriptSegments.filter((segment) => segment.sourceId !== sourceId);
    const out = segments.map((segment) => ({ ...segment, id: crypto.randomUUID(), sourceId, createdAt: now() }));
    state.transcriptSegments.push(...out);
    save();
    return out;
  },

  search(q: string, type?: string) {
    const terms = q.toLowerCase().split(/\W+/).filter(Boolean);
    const sources = new Map(this.listSources(10_000).map((source) => [source.id, source]));
    const entities = this.findEntities();
    return this.listMemories(type).map((memory) => {
      const source = sources.get(memory.sourceId);
      const related = entities.filter((entity) => state.relationships.some((relationship) => relationship.sourceId === memory.sourceId && relationship.toId === entity.id)).map((entity) => entity.canonicalName).join(" ");
      const haystack = `${memory.content} ${memory.summary} ${source?.title ?? ""} ${source?.transcriptText ?? ""} ${related}`.toLowerCase();
      const score = terms.reduce((total, term) => total + (haystack.includes(term) ? 1 : 0), 0);
      return { ...memory, source, score };
    }).filter((result) => result.score > 0).sort((a, b) => b.score - a.score || b.createdAt.localeCompare(a.createdAt)).slice(0, 30);
  },

  recentSources() {
    return this.listSources(8);
  },

  resurfaced() {
    return this.listMemories().filter((memory) => Date.now() - Date.parse(memory.createdAt) > 1000 * 60 * 60 * 24 * 2).slice(0, 4);
  },

  deleteSource(id: string) {
    const source = this.getSource(id);
    if (!source) return false;
    const memoryIds = new Set(state.memories.filter((memory) => memory.sourceId === id).map((memory) => memory.id));
    state.sources = state.sources.filter((item) => item.id !== id);
    state.memories = state.memories.filter((memory) => memory.sourceId !== id);
    state.openLoops = state.openLoops.filter((loop) => !memoryIds.has(loop.memoryId));
    state.relationships = state.relationships.filter((relationship) => relationship.sourceId !== id);
    state.chunks = state.chunks.filter((chunk) => chunk.sourceId !== id);
    state.jobs = state.jobs.filter((job) => job.sourceId !== id);
    state.recordingSessions = state.recordingSessions.filter((session) => session.sourceId !== id);
    state.transcriptSegments = state.transcriptSegments.filter((segment) => segment.sourceId !== id);
    try {
      if (source.filePath && fs.existsSync(source.filePath)) fs.unlinkSync(source.filePath);
    } catch {
      // A missing upload is already deleted from the user's perspective.
    }
    save();
    return true;
  },

  exportData() {
    return {
      storageVersion: STORAGE_VERSION,
      sources: this.listSources(10_000),
      recordingSessions: state.recordingSessions,
      transcriptSegments: state.transcriptSegments,
      memories: state.memories,
      entities: this.findEntities(),
      openLoops: this.listLoops(),
      evidenceRefs: state.memories.flatMap((memory) => memory.evidenceRefs ?? []),
    };
  },
};
