import { aiProvider, transcriptionProvider } from "./ai.js";
import { store } from "./db.js";
import { config } from "./config.js";
import { chunkText } from "./chunking.js";
import { transcribeWithChunking } from "./transcription.js";
import type { ClaimState, EntityType, EvidenceRef, MeetingActionItem, MeetingBrief, MeetingClaim, Memory, Source, TranscriptSegment } from "./types.js";

const active = new Set<string>();
const stopWords = new Set(["this", "that", "with", "from", "will", "have", "about", "instead", "into", "said", "still", "need", "what", "were", "they", "than"]);

function evidenceRefs(sourceId: string, hints: ({ segmentIndex: number; startMs?: number; endMs?: number; text: string } | undefined)[] | undefined, segments: TranscriptSegment[]): EvidenceRef[] {
  const refs: EvidenceRef[] = [];
  for (const hint of hints ?? []) {
    if (!hint) continue;
    const segment = segments.find((candidate) => candidate.segmentIndex === hint.segmentIndex);
    if (!segment) continue;
    const startMs = hint.startMs ?? segment.startMs;
    const endMs = hint.endMs ?? segment.endMs;
    if (startMs !== undefined && endMs !== undefined && endMs < startMs) continue;
    refs.push({ sourceId, segmentId: segment.id, startMs, endMs, quote: hint.text || segment.text });
  }
  return refs;
}

function transcriptHints(source: Source): { segmentIndex: number; startMs?: number; endMs?: number; text: string }[] {
  return store.transcriptForSource(source.id).map((segment) => ({ segmentIndex: segment.segmentIndex, startMs: segment.startMs, endMs: segment.endMs, text: segment.text }));
}

function asTranscriptSegments(result: { text: string; segments: Array<{ startMs?: number; endMs?: number; text: string; speaker?: string; confidence?: number; words?: TranscriptSegment["words"]; chunkIndex?: number; chunkStartMs?: number }> }): Array<Omit<TranscriptSegment, "id" | "sourceId" | "createdAt">> {
  return result.segments.length ? result.segments.map((segment, segmentIndex) => ({ ...segment, segmentIndex })) : [{ segmentIndex: 0, text: result.text }];
}

function claim(sourceId: string, input: { text: string; confidence: number; evidence?: { segmentIndex: number; startMs?: number; endMs?: number; text: string }[] }, segments: TranscriptSegment[]): MeetingClaim {
  return {
    id: crypto.randomUUID(),
    text: input.text.trim(),
    confidence: input.confidence,
    state: "generated",
    evidenceRefs: evidenceRefs(sourceId, input.evidence, segments),
  };
}

function meetingBrief(sourceId: string, analysis: Awaited<ReturnType<typeof aiProvider.analyzeSource>>, segments: TranscriptSegment[]): MeetingBrief {
  const mapClaims = (items: { text: string; confidence: number; evidence?: { segmentIndex: number; startMs?: number; endMs?: number; text: string }[] }[]) => items.filter((item) => item.text.trim()).map((item) => claim(sourceId, item, segments));
  const actionItems: MeetingActionItem[] = analysis.meeting.actionItems.filter((item) => item.text.trim()).map((item) => {
    const mapped = claim(sourceId, item, segments) as MeetingActionItem;
    mapped.status = "open";
    if (item.owner && item.owner.confidence >= 0.6) mapped.owner = { value: item.owner.value, confidence: item.owner.confidence, state: item.owner.state ?? "generated" as ClaimState };
    if (item.dueAt && item.dueAt.confidence >= 0.6) mapped.dueAt = { value: item.dueAt.value, confidence: item.dueAt.confidence, state: item.dueAt.state ?? "generated" as ClaimState };
    return mapped;
  });
  return {
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    summary: analysis.meeting.summary || analysis.summary,
    keyPoints: mapClaims(analysis.meeting.keyPoints),
    decisions: mapClaims(analysis.meeting.decisions),
    actionItems,
    suggestedFollowUps: mapClaims(analysis.meeting.suggestedFollowUps),
    unresolvedQuestions: mapClaims(analysis.meeting.unresolvedQuestions),
  };
}

function retryTime(attempts: number) {
  const delay = Math.min(5 * 60_000, 2_000 * (2 ** Math.max(0, attempts - 1)));
  return new Date(Date.now() + delay).toISOString();
}

export async function processSource(sourceId: string, jobId?: string) {
  if (active.has(sourceId)) return;
  active.add(sourceId);
  const source = store.getSource(sourceId);
  if (!source) {
    active.delete(sourceId);
    return;
  }

  let stage: "processing" | "transcription" | "analysis" = "processing";
  try {
    if (jobId) store.claimJob(jobId);
    store.updateSource(sourceId, { processingStatus: "processing", processingError: undefined });
    let text = source.transcriptText || source.extractedText || source.originalText;
    let segments = store.transcriptForSource(sourceId);

    if (source.type === "voice" && !text) {
      stage = "transcription";
      if (!source.filePath || !transcriptionProvider) {
        store.updateSource(sourceId, { processingStatus: "partial", transcriptStatus: "partial", processingError: "Audio is saved, but no transcription provider is configured. Add a transcript or configure one, then retry." });
        if (source.recordingSessionId) store.updateRecordingSession(source.recordingSessionId, { status: "partial" });
        if (jobId) store.updateJob(jobId, "complete");
        active.delete(sourceId);
        return;
      }
      store.updateSource(sourceId, { transcriptStatus: "processing" });
      const result = await transcribeWithChunking(transcriptionProvider, { filePath: source.filePath, mimeType: source.audioMimeType ?? source.mimeType, sourceId, durationMs: source.durationMs });
      segments = store.replaceTranscript(sourceId, asTranscriptSegments(result));
      text = result.text;
      store.updateSource(sourceId, { transcriptText: text, extractedText: text, transcriptStatus: "ready" });
    }

    if (source.type === "url" && !text) {
      try {
        const response = await fetch(source.sourceUrl!, { signal: AbortSignal.timeout(6_000) });
        if (!response.ok) throw new Error(`URL returned ${response.status}`);
        const html = await response.text();
        text = html.replace(/<script[\s\S]*?<\/script>/gi, " ").replace(/<style[\s\S]*?<\/style>/gi, " ").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim().slice(0, 20_000);
        if (!text) throw new Error("No readable text found");
        store.updateSource(sourceId, { extractedText: text });
      } catch (error) {
        const message = error instanceof Error ? error.message : "URL content could not be fetched";
        store.updateSource(sourceId, { processingStatus: "partial", processingError: `URL saved, but content extraction failed: ${message}` });
        if (jobId) store.updateJob(jobId, "complete");
        active.delete(sourceId);
        return;
      }
    }

    if (!text) {
      store.updateSource(sourceId, { processingStatus: "partial", processingError: "The source is saved, but no text is available for analysis yet." });
      if (jobId) store.updateJob(jobId, "complete");
      active.delete(sourceId);
      return;
    }

    if (source.type === "voice" && !segments.length) segments = store.replaceTranscript(sourceId, [{ segmentIndex: 0, text }]);
    if (source.type !== "voice") segments = [];
    const hints = source.type === "voice" ? transcriptHints(source) : undefined;
    stage = "analysis";
    const analysis = await aiProvider.analyzeSource(text, source.title, hints);

    // Replace derived data only after the new analysis has validated successfully.
    store.clearDerived(sourceId);
    store.replaceChunks(sourceId, chunkText(text));
    const created = [];
    for (const memoryInput of analysis.memories) {
      const memory = store.createMemory({
        id: crypto.randomUUID(),
        sourceId,
        memoryType: memoryInput.type,
        content: memoryInput.content,
        summary: memoryInput.content.slice(0, 240),
        importance: memoryInput.importance,
        confidence: memoryInput.confidence,
        occurredAt: memoryInput.occurredAt,
        status: "active",
        metadata: {},
        evidenceRefs: evidenceRefs(sourceId, memoryInput.evidence, segments),
      });
      created.push(memory);
    }

    for (const decision of analysis.meeting.decisions) {
      if (created.some((memory) => memory.content === decision.text)) continue;
      const memory = store.createMemory({ id: crypto.randomUUID(), sourceId, memoryType: "decision", content: decision.text, summary: decision.text.slice(0, 240), importance: 0.9, confidence: decision.confidence, status: "active", metadata: { projection: "meetingBrief" }, evidenceRefs: evidenceRefs(sourceId, decision.evidence, segments) });
      created.push(memory);
    }

    for (const entityInput of analysis.entities) {
      const entity = store.upsertEntity(entityInput.type as EntityType, entityInput.name, entityInput.description ?? "");
      for (const memory of created) store.addRelationship({ fromType: "memory", fromId: memory.id, relationshipType: "mentions", toType: "entity", toId: entity.id, confidence: 0.8, sourceId });
    }

    for (const loop of analysis.openLoops) {
      const memory = created.find((item) => item.content === loop.description) || created.find((item) => item.memoryType === "task") || created[0];
      if (memory) store.addLoop({ memoryId: memory.id, description: loop.description, status: "open", confidence: loop.confidence, dueAt: loop.dueAt, evidenceRefs: evidenceRefs(sourceId, loop.evidence, segments) });
    }

    for (const action of analysis.meeting.actionItems) {
      let memory: Memory | undefined = created.find((item) => item.content === action.text);
      if (!memory) {
        memory = store.createMemory({ id: crypto.randomUUID(), sourceId, memoryType: "task", content: action.text, summary: action.text.slice(0, 240), importance: 0.8, confidence: action.confidence, status: "active", metadata: { projection: "meetingBrief" }, evidenceRefs: evidenceRefs(sourceId, action.evidence, segments) });
      }
      if (!created.includes(memory)) created.push(memory);
      if (!store.memoriesForSource(sourceId).some((item) => item.id === memory.id && item.memoryType === "task")) continue;
      if (!store.listLoops().some((loop) => loop.memoryId === memory.id)) store.addLoop({ memoryId: memory.id, description: action.text, status: "open", confidence: action.confidence, dueAt: action.dueAt?.value, evidenceRefs: evidenceRefs(sourceId, action.evidence, segments) });
    }

    const decisions = created.filter((memory) => memory.memoryType === "decision");
    if (decisions.length) {
      const old = store.listMemories("decision").filter((memory) => memory.sourceId !== sourceId && !memory.supersededBy);
      for (const newer of decisions) {
        for (const previous of old) {
          const newerTokens = new Set(newer.content.toLowerCase().split(/\W+/).filter((token: string) => token.length > 3 && !stopWords.has(token)));
          const overlap = previous.content.toLowerCase().split(/\W+/).some((token) => newerTokens.has(token));
          if (overlap && new Date(previous.createdAt) < new Date(newer.createdAt)) store.updateMemory(previous.id, { supersededBy: newer.id, metadata: { ...previous.metadata, supersededReason: "Newer decision overlaps this source" } });
        }
      }
    }

    const brief = meetingBrief(sourceId, analysis, segments);
    store.updateMeetingBrief(sourceId, brief);
    store.updateSource(sourceId, { processingStatus: "ready", processingError: undefined, summary: brief.summary, transcriptStatus: source.type === "voice" ? "ready" : source.transcriptStatus, processingVersion: (source.processingVersion ?? 0) + 1 });
    if (source.recordingSessionId) store.updateRecordingSession(source.recordingSessionId, { status: "ready" });
    if (jobId) store.updateJob(jobId, "complete");
  } catch (error) {
    const message = error instanceof Error ? error.message : "Processing failed";
    const transcriptReady = source.type === "voice" && store.getSource(sourceId)?.transcriptStatus === "ready";
    const status = stage === "analysis" && transcriptReady ? "partial" : "failed";
    store.updateSource(sourceId, { processingStatus: status, processingError: `${stage}: ${message}`, transcriptStatus: transcriptReady ? "ready" : source.type === "voice" ? "failed" : source.transcriptStatus });
    if (source.recordingSessionId) store.updateRecordingSession(source.recordingSessionId, { status: status === "partial" ? "partial" : "failed" });
    if (jobId) {
      const job = store.getJob(jobId);
      if (job && job.attempts < config.jobMaxAttempts) store.updateJob(jobId, "retry_scheduled", message, retryTime(job.attempts));
      else store.updateJob(jobId, "failed", message);
    }
  } finally {
    active.delete(sourceId);
  }
}

export function queueSource(sourceId: string) {
  const job = store.createJob(sourceId);
  void processSource(sourceId, job);
  return job;
}
