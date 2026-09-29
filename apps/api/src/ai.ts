import fs from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { config } from "./config.js";
import { chunkText } from "./chunking.js";
import { processingError, processingInfo } from "./diagnostics.js";
import { LocalWhisperTranscriptionProvider } from "./localWhisper.js";
import type { ClaimState, EntityType, MemoryType, TranscriptWord } from "./types.js";

export interface EvidenceHint {
  segmentIndex: number;
  startMs?: number;
  endMs?: number;
  text: string;
}

export interface AnalysisClaim {
  text: string;
  confidence: number;
  evidence?: EvidenceHint[];
}

export interface AnalysisActionItem extends AnalysisClaim {
  owner?: { value: string; confidence: number; state?: ClaimState };
  dueAt?: { value: string; confidence: number; state?: ClaimState };
}

export interface MeetingAnalysis {
  summary: string;
  keyPoints: AnalysisClaim[];
  decisions: AnalysisClaim[];
  actionItems: AnalysisActionItem[];
  suggestedFollowUps: AnalysisClaim[];
  unresolvedQuestions: AnalysisClaim[];
}

export interface Analysis {
  summary: string;
  memories: {
    type: MemoryType;
    content: string;
    importance: number;
    confidence: number;
    occurredAt?: string;
    evidence?: EvidenceHint[];
  }[];
  entities: { type: EntityType; name: string; description?: string }[];
  openLoops: { description: string; confidence: number; dueAt?: string; evidence?: EvidenceHint[] }[];
  relationships: { entityName: string; relationshipType: string; confidence: number }[];
  meeting: MeetingAnalysis;
}

export interface AIProvider {
  analyzeSource(text: string, title: string, evidenceSegments?: EvidenceHint[]): Promise<Analysis>;
  answerQuestion(question: string, context: string): Promise<string>;
}

export interface TranscriptionInput {
  filePath: string;
  mimeType?: string;
  sourceId: string;
  durationMs?: number;
}

export interface TranscriptionSegment {
  startMs?: number;
  endMs?: number;
  text: string;
  speaker?: string;
  confidence?: number;
  words?: TranscriptWord[];
  chunkIndex?: number;
  chunkStartMs?: number;
}

export interface TranscriptionResult {
  text: string;
  segments: TranscriptionSegment[];
  language?: string;
}

export interface TranscriptionProvider {
  transcribe(input: TranscriptionInput): Promise<TranscriptionResult>;
}

export interface TranscriptionProviderSettings {
  baseUrl: string;
  apiKey: string;
  model: string;
}

const evidenceSchema = z.object({
  segmentIndex: z.number().int().nonnegative(),
  startMs: z.number().nonnegative().optional(),
  endMs: z.number().nonnegative().optional(),
  text: z.string().default(""),
}).strict();

const claimSchema = z.object({
  text: z.string().min(1),
  confidence: z.number().min(0).max(1).default(0.7),
  evidence: z.array(evidenceSchema).optional(),
}).strict();

const meetingAnalysisSchema = z.object({
  summary: z.string().default(""),
  keyPoints: z.array(claimSchema).default([]),
  decisions: z.array(claimSchema).default([]),
  actionItems: z.array(claimSchema.extend({
    owner: z.object({ value: z.string().min(1), confidence: z.number().min(0).max(1), state: z.enum(["generated", "confirmed", "edited"]).optional() }).strict().optional(),
    dueAt: z.object({ value: z.string().min(1), confidence: z.number().min(0).max(1), state: z.enum(["generated", "confirmed", "edited"]).optional() }).strict().optional(),
  }).strict()).default([]),
  suggestedFollowUps: z.array(claimSchema).default([]),
  unresolvedQuestions: z.array(claimSchema).default([]),
}).strict();

const analysisSchema = z.object({
  summary: z.string().default(""),
  memories: z.array(z.object({
    type: z.enum(["fact", "decision", "idea", "task", "question", "preference", "reference", "observation", "event"]),
    content: z.string().min(1),
    importance: z.number().min(0).max(1).default(0.5),
    confidence: z.number().min(0).max(1).default(0.7),
    occurredAt: z.string().optional(),
    evidence: z.array(evidenceSchema).optional(),
  })).default([]),
  entities: z.array(z.object({
    type: z.enum(["person", "project", "organization", "product", "place", "topic", "technology", "document"]),
    name: z.string().min(1),
    description: z.string().optional(),
  })).default([]),
  openLoops: z.array(z.object({
    description: z.string().min(1),
    confidence: z.number().min(0).max(1).default(0.7),
    dueAt: z.string().optional(),
    evidence: z.array(evidenceSchema).optional(),
  })).default([]),
  relationships: z.array(z.object({
    entityName: z.string(),
    relationshipType: z.string(),
    confidence: z.number().min(0).max(1).default(0.7),
  })).default([]),
  meeting: meetingAnalysisSchema.optional(),
}).strict();

// Groq strict structured output requires every declared property to be required
// and every object to reject additional properties. Optional enrichment fields
// (dates, owners, descriptions) stay out of the constrained core schema rather
// than forcing the model to invent values that are not supported by evidence.
const evidenceJSONSchema = {
  type: "object",
  properties: {
    segmentIndex: { type: "integer" },
    text: { type: "string" },
  },
  required: ["segmentIndex", "text"],
  additionalProperties: false,
} as const;

const claimJSONSchema = {
  type: "object",
  properties: {
    text: { type: "string" },
    confidence: { type: "number" },
    evidence: { type: "array", items: evidenceJSONSchema },
  },
  required: ["text", "confidence", "evidence"],
  additionalProperties: false,
} as const;

const analysisJSONSchema = {
  type: "object",
  properties: {
    summary: { type: "string" },
    memories: {
      type: "array",
      items: {
        type: "object",
        properties: {
          type: { type: "string" },
          content: { type: "string" },
          importance: { type: "number" },
          confidence: { type: "number" },
          evidence: { type: "array", items: evidenceJSONSchema },
        },
        required: ["type", "content", "importance", "confidence", "evidence"],
        additionalProperties: false,
      },
    },
    entities: {
      type: "array",
      items: {
        type: "object",
        properties: {
          type: { type: "string" },
          name: { type: "string" },
        },
        required: ["type", "name"],
        additionalProperties: false,
      },
    },
    openLoops: {
      type: "array",
      items: {
        type: "object",
        properties: {
          description: { type: "string" },
          confidence: { type: "number" },
          evidence: { type: "array", items: evidenceJSONSchema },
        },
        required: ["description", "confidence", "evidence"],
        additionalProperties: false,
      },
    },
    relationships: {
      type: "array",
      items: {
        type: "object",
        properties: {
          entityName: { type: "string" },
          relationshipType: { type: "string" },
          confidence: { type: "number" },
        },
        required: ["entityName", "relationshipType", "confidence"],
        additionalProperties: false,
      },
    },
    meeting: {
      type: "object",
      properties: {
        keyPoints: { type: "array", items: claimJSONSchema },
        decisions: { type: "array", items: claimJSONSchema },
        actionItems: { type: "array", items: claimJSONSchema },
        suggestedFollowUps: { type: "array", items: claimJSONSchema },
        unresolvedQuestions: { type: "array", items: claimJSONSchema },
      },
      required: ["keyPoints", "decisions", "actionItems", "suggestedFollowUps", "unresolvedQuestions"],
      additionalProperties: false,
    },
  },
  required: ["summary", "memories", "entities", "openLoops", "relationships", "meeting"],
  additionalProperties: false,
} as const;

const memoryTypes = new Set<MemoryType>(["fact", "decision", "idea", "task", "question", "preference", "reference", "observation", "event"]);
const entityTypes = new Set<EntityType>(["person", "project", "organization", "product", "place", "topic", "technology", "document"]);
const boundedConfidence = (value: unknown, fallback = 0.7) => typeof value === "number" && Number.isFinite(value) ? Math.min(1, Math.max(0, value)) : fallback;
const usableText = (value: unknown) => typeof value === "string" ? value.trim() : "";

function normalizeAnalysis(value: any) {
  const evidence = (items: unknown) => Array.isArray(items) ? items.map((item: any) => ({
    segmentIndex: Math.max(0, Math.trunc(Number(item?.segmentIndex) || 0)),
    text: usableText(item?.text),
  })) : [];
  const claims = (items: unknown) => {
    if (!Array.isArray(items)) return [];
    return items.map((item: any) => {
      const value = typeof item === "string" ? { text: item } : item;
      return {
        text: usableText(value?.text),
        confidence: boundedConfidence(value?.confidence),
        evidence: evidence(value?.evidence),
      };
    }).filter((item) => item.text);
  };
  const memories = (items: unknown) => {
    if (!Array.isArray(items)) return [];
    return items.map((item: any) => {
      const memory = typeof item === "string" ? { content: item } : item;
      return {
        type: memoryTypes.has(memory?.type) ? memory.type : "observation",
        content: usableText(memory?.content),
        importance: boundedConfidence(memory?.importance, 0.5),
        confidence: boundedConfidence(memory?.confidence),
        evidence: evidence(memory?.evidence),
      };
    }).filter((item: any) => item.content);
  };
  const entities = (items: unknown) => {
    if (!Array.isArray(items)) return [];
    return items.map((item: any) => {
      const entity = typeof item === "string" ? { name: item } : item;
      return {
        type: entityTypes.has(entity?.type) ? entity.type : "topic",
        name: usableText(entity?.name),
      };
    }).filter((item: any) => item.name);
  };
  const openLoops = (items: unknown) => {
    if (!Array.isArray(items)) return [];
    return items.map((item: any) => {
      const loop = typeof item === "string" ? { description: item } : item;
      return {
        description: usableText(loop?.description),
        confidence: boundedConfidence(loop?.confidence),
        evidence: evidence(loop?.evidence),
      };
    }).filter((item: any) => item.description);
  };
  const relationships = (items: unknown) => {
    if (!Array.isArray(items)) return [];
    return items.map((item: any) => {
      const relationship = typeof item === "string" ? { entityName: item, relationshipType: "mentions" } : item;
      return {
        entityName: usableText(relationship?.entityName),
        relationshipType: usableText(relationship?.relationshipType),
        confidence: boundedConfidence(relationship?.confidence),
      };
    }).filter((item: any) => item.entityName && item.relationshipType);
  };
  const meeting = value?.meeting && typeof value.meeting === "object" ? value.meeting : {};
  return {
    summary: usableText(value?.summary),
    memories: memories(value?.memories),
    entities: entities(value?.entities),
    openLoops: openLoops(value?.openLoops),
    relationships: relationships(value?.relationships),
    meeting: {
      summary: usableText(value?.summary),
      keyPoints: claims(meeting.keyPoints),
      decisions: claims(meeting.decisions),
      actionItems: claims(meeting.actionItems),
      suggestedFollowUps: claims(meeting.suggestedFollowUps),
      unresolvedQuestions: claims(meeting.unresolvedQuestions),
    },
  };
}

interface AnalysisWindow {
  text: string;
  evidenceSegments?: EvidenceHint[];
  index: number;
  total: number;
}

type ConfidenceValue = { value: string; confidence: number; state?: ClaimState };

function splitAnalysisInput(text: string, evidenceSegments: EvidenceHint[] | undefined, maxChars: number): AnalysisWindow[] {
  if (maxChars <= 0 || text.length <= maxChars) return [{ text, evidenceSegments, index: 0, total: 1 }];

  const windows: Array<{ text: string; evidenceSegments?: EvidenceHint[] }> = [];
  if (evidenceSegments?.length) {
    let current: EvidenceHint[] = [];
    let currentChars = 0;
    const flush = () => {
      if (!current.length) return;
      windows.push({ text: current.map((segment) => segment.text.trim()).join("\n"), evidenceSegments: current });
      current = [];
      currentChars = 0;
    };

    for (const segment of evidenceSegments) {
      const segmentText = segment.text.trim();
      if (!segmentText) continue;
      const candidateChars = currentChars + (current.length ? 1 : 0) + segmentText.length;
      if (current.length && candidateChars > maxChars) flush();
      current.push(segment);
      currentChars += (current.length > 1 ? 1 : 0) + segmentText.length;
    }
    flush();
  }

  if (!windows.length) {
    const overlap = Math.min(120, Math.floor(maxChars / 5));
    const chunks = chunkText(text, maxChars, overlap);
    return chunks.map((chunk, index) => ({ text: chunk, index, total: chunks.length }));
  }

  return windows.map((window, index) => ({ ...window, index, total: windows.length }));
}

function normalizedKey(value: string) {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

function uniqueTexts(values: string[]) {
  const result: string[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    const text = value.trim();
    const key = normalizedKey(text);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    result.push(text);
  }
  return result;
}

function mergeEvidence(...groups: Array<EvidenceHint[] | undefined>): EvidenceHint[] | undefined {
  const result: EvidenceHint[] = [];
  const seen = new Set<string>();
  for (const group of groups) {
    for (const evidence of group ?? []) {
      const key = `${evidence.segmentIndex}|${evidence.startMs ?? ""}|${evidence.endMs ?? ""}|${normalizedKey(evidence.text)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      result.push(evidence);
    }
  }
  return result.length ? result : undefined;
}

function strongestValue(left: ConfidenceValue | undefined, right: ConfidenceValue | undefined) {
  if (!left) return right;
  if (!right || right.confidence <= left.confidence) return left;
  return right;
}

function mergeClaims(groups: AnalysisClaim[][]): AnalysisClaim[] {
  const result: AnalysisClaim[] = [];
  const indexes = new Map<string, number>();
  for (const claim of groups.flat()) {
    const key = normalizedKey(claim.text);
    if (!key) continue;
    const index = indexes.get(key);
    if (index === undefined) {
      indexes.set(key, result.length);
      result.push({ ...claim, evidence: mergeEvidence(claim.evidence) });
      continue;
    }
    const existing = result[index];
    existing.confidence = Math.max(existing.confidence, claim.confidence);
    existing.evidence = mergeEvidence(existing.evidence, claim.evidence);
  }
  return result;
}

function mergeActionItems(groups: AnalysisActionItem[][]): AnalysisActionItem[] {
  const result: AnalysisActionItem[] = [];
  const indexes = new Map<string, number>();
  for (const item of groups.flat()) {
    const key = normalizedKey(item.text);
    if (!key) continue;
    const index = indexes.get(key);
    if (index === undefined) {
      indexes.set(key, result.length);
      result.push({ ...item, evidence: mergeEvidence(item.evidence) });
      continue;
    }
    const existing = result[index];
    existing.confidence = Math.max(existing.confidence, item.confidence);
    existing.evidence = mergeEvidence(existing.evidence, item.evidence);
    existing.owner = strongestValue(existing.owner, item.owner);
    existing.dueAt = strongestValue(existing.dueAt, item.dueAt);
  }
  return result;
}

function mergeMemories(groups: Analysis["memories"][]): Analysis["memories"] {
  const result: Analysis["memories"] = [];
  const indexes = new Map<string, number>();
  for (const memory of groups.flat()) {
    const key = `${memory.type}|${normalizedKey(memory.content)}`;
    if (!memory.content.trim()) continue;
    const index = indexes.get(key);
    if (index === undefined) {
      indexes.set(key, result.length);
      result.push({ ...memory, evidence: mergeEvidence(memory.evidence) });
      continue;
    }
    const existing = result[index];
    existing.importance = Math.max(existing.importance, memory.importance);
    existing.confidence = Math.max(existing.confidence, memory.confidence);
    existing.occurredAt = existing.occurredAt ?? memory.occurredAt;
    existing.evidence = mergeEvidence(existing.evidence, memory.evidence);
  }
  return result;
}

function mergeEntities(groups: Analysis["entities"][]): Analysis["entities"] {
  const result: Analysis["entities"] = [];
  const seen = new Set<string>();
  for (const entity of groups.flat()) {
    const key = `${entity.type}|${normalizedKey(entity.name)}`;
    if (!entity.name.trim() || seen.has(key)) continue;
    seen.add(key);
    result.push(entity);
  }
  return result;
}

function mergeOpenLoops(groups: Analysis["openLoops"][]): Analysis["openLoops"] {
  const result: Analysis["openLoops"] = [];
  const indexes = new Map<string, number>();
  for (const loop of groups.flat()) {
    const key = normalizedKey(loop.description);
    if (!key) continue;
    const index = indexes.get(key);
    if (index === undefined) {
      indexes.set(key, result.length);
      result.push({ ...loop, evidence: mergeEvidence(loop.evidence) });
      continue;
    }
    const existing = result[index];
    existing.confidence = Math.max(existing.confidence, loop.confidence);
    existing.dueAt = existing.dueAt ?? loop.dueAt;
    existing.evidence = mergeEvidence(existing.evidence, loop.evidence);
  }
  return result;
}

function mergeRelationships(groups: Analysis["relationships"][]): Analysis["relationships"] {
  const result: Analysis["relationships"] = [];
  const seen = new Set<string>();
  for (const relationship of groups.flat()) {
    const key = `${normalizedKey(relationship.entityName)}|${normalizedKey(relationship.relationshipType)}`;
    if (!relationship.entityName.trim() || !relationship.relationshipType.trim() || seen.has(key)) continue;
    seen.add(key);
    result.push(relationship);
  }
  return result;
}

function mergeAnalyses(analyses: Analysis[]): Analysis {
  const summary = uniqueTexts(analyses.flatMap((analysis) => [analysis.summary, analysis.meeting.summary])).join(" ").slice(0, 1000);
  return {
    summary,
    memories: mergeMemories(analyses.map((analysis) => analysis.memories)),
    entities: mergeEntities(analyses.map((analysis) => analysis.entities)),
    openLoops: mergeOpenLoops(analyses.map((analysis) => analysis.openLoops)),
    relationships: mergeRelationships(analyses.map((analysis) => analysis.relationships)),
    meeting: {
      summary,
      keyPoints: mergeClaims(analyses.map((analysis) => analysis.meeting.keyPoints)),
      decisions: mergeClaims(analyses.map((analysis) => analysis.meeting.decisions)),
      actionItems: mergeActionItems(analyses.map((analysis) => analysis.meeting.actionItems)),
      suggestedFollowUps: mergeClaims(analyses.map((analysis) => analysis.meeting.suggestedFollowUps)),
      unresolvedQuestions: mergeClaims(analyses.map((analysis) => analysis.meeting.unresolvedQuestions)),
    },
  };
}

function sanitizeAnalysisEvidence(analysis: Analysis, allowedEvidence: EvidenceHint[] | undefined, inferMissing: boolean): Analysis {
  if (!allowedEvidence?.length) return analysis;
  const canonical = new Map(allowedEvidence.map((evidence) => [evidence.segmentIndex, evidence]));
  const evidence = (hints: EvidenceHint[] | undefined, text: string) => {
    const result: EvidenceHint[] = [];
    for (const hint of hints ?? []) {
      const source = canonical.get(hint.segmentIndex);
      if (!source) continue;
      result.push({ segmentIndex: source.segmentIndex, startMs: source.startMs, endMs: source.endMs, text: source.text });
    }
    return result.length ? mergeEvidence(result) : inferMissing ? inferredEvidence(text, allowedEvidence) : undefined;
  };
  const claims = (items: AnalysisClaim[]) => items.map((item) => ({ ...item, evidence: evidence(item.evidence, item.text) }));
  const actionItems = (items: AnalysisActionItem[]) => items.map((item) => ({ ...item, evidence: evidence(item.evidence, item.text) }));
  return {
    ...analysis,
    memories: analysis.memories.map((item) => ({ ...item, evidence: evidence(item.evidence, item.content) })),
    openLoops: analysis.openLoops.map((item) => ({ ...item, evidence: evidence(item.evidence, item.description) })),
    meeting: {
      ...analysis.meeting,
      keyPoints: claims(analysis.meeting.keyPoints),
      decisions: claims(analysis.meeting.decisions),
      actionItems: actionItems(analysis.meeting.actionItems),
      suggestedFollowUps: claims(analysis.meeting.suggestedFollowUps),
      unresolvedQuestions: claims(analysis.meeting.unresolvedQuestions),
    },
  };
}

function isLocalOllamaUrl(url: string) {
  return /^https?:\/\/(?:127\.0\.0\.1|localhost):11434(?:\/|$)/i.test(url);
}

const evidenceStopWords = new Set(["about", "after", "again", "also", "been", "being", "from", "have", "into", "just", "more", "only", "that", "their", "there", "these", "they", "this", "with", "would"]);

function inferredEvidence(text: string, allowedEvidence: EvidenceHint[]): EvidenceHint[] | undefined {
  const tokens = text.toLowerCase().match(/[a-z0-9][a-z0-9'-]*/g) ?? [];
  const significant = [...new Set(tokens.filter((token) => (token.length >= 4 || /^\d{2,}$/.test(token)) && !evidenceStopWords.has(token)))];
  if (!significant.length) return undefined;
  const scored = allowedEvidence.map((segment) => {
    const segmentTokens = new Set(segment.text.toLowerCase().match(/[a-z0-9][a-z0-9'-]*/g) ?? []);
    return { segment, score: significant.filter((token) => segmentTokens.has(token)).length };
  }).filter((item) => item.score > 0).sort((left, right) => right.score - left.score);
  const best = scored[0];
  return best && best.score >= 2 ? [best.segment] : undefined;
}

function sentenceParts(text: string) {
  return text.replace(/\s+/g, " ").split(/(?<=[.!?])\s+|\n+/).map((value) => value.trim()).filter((value) => value.length > 8);
}

function titleEntities(text: string) {
  const found = new Set<string>();
  for (const match of text.matchAll(/\b(?:Project\s+)?[A-Z][A-Za-z0-9-]{2,}(?:\s+[A-Z][A-Za-z0-9-]{2,})?\b/g)) {
    const name = match[0].replace(/^I\s+/i, "");
    if (!/^(The|This|That|What|When|Because|PostgreSQL|SQLite|OpenAI|Fusion|OCR|I|We)$/.test(name)) found.add(name);
  }
  return [...found];
}

const evidenceFor = (text: string, index: number, segments?: EvidenceHint[]) => {
  if (!segments?.length) return undefined;
  const lower = text.toLowerCase();
  return segments.filter((segment) => lower.includes(segment.text.toLowerCase().slice(0, Math.min(28, segment.text.length))) || segment.segmentIndex === index).slice(0, 1);
};

function mockMeeting(sentences: string[], memories: Analysis["memories"], loops: Analysis["openLoops"], questions: AnalysisClaim[]): MeetingAnalysis {
  const keyPoints = sentences.slice(0, 5).map((text, index) => ({ text, confidence: 0.65, evidence: memories[index]?.evidence }));
  const decisions = memories.filter((memory) => memory.type === "decision").map((memory) => ({ text: memory.content, confidence: memory.confidence, evidence: memory.evidence }));
  const actionItems = loops.map((loop) => ({ text: loop.description, confidence: loop.confidence, evidence: loop.evidence }));
  return {
    summary: sentences[0]?.slice(0, 240) ?? "",
    keyPoints,
    decisions,
    actionItems,
    suggestedFollowUps: actionItems,
    unresolvedQuestions: questions,
  };
}

export class MockAIProvider implements AIProvider {
  async analyzeSource(text: string, title: string, evidenceSegments?: EvidenceHint[]): Promise<Analysis> {
    const sentences = sentenceParts(text);
    const memories: Analysis["memories"] = [];
    const loops: Analysis["openLoops"] = [];
    const questions: AnalysisClaim[] = [];

    for (const [index, sentence] of sentences.entries()) {
      const lower = sentence.toLowerCase();
      const evidence = evidenceFor(sentence, index, evidenceSegments);
      const isLoop = /\b(still need|need to|needs to|remind me|should |follow up|todo|unfinished|have to)\b/.test(lower);
      if (isLoop) loops.push({ description: sentence.replace(/[.!?]$/, ""), confidence: 0.91, evidence });
      let type: MemoryType = "observation";
      if (/\b(decided|decision|choose|chose|changed my mind|will use|using|instead of)\b/.test(lower)) type = "decision";
      else if (/\b(idea|could |might |what if|consider)\b/.test(lower)) type = "idea";
      else if (/\?\s*$/.test(sentence)) type = "question";
      else if (/\b(prefer|like|always|avoid)\b/.test(lower)) type = "preference";
      else if (/\b(on |met |meeting|yesterday|today|tomorrow|said|told)\b/.test(lower)) type = "event";
      const memory = { type, content: sentence, importance: type === "decision" ? 0.9 : isLoop ? 0.8 : 0.55, confidence: 0.86, evidence };
      if (!isLoop || type !== "observation") memories.push(memory);
      if (type === "question") questions.push({ text: sentence, confidence: 0.8, evidence });
    }

    if (!memories.length && text.trim()) memories.push({ type: "reference", content: text.trim().slice(0, 500), importance: 0.5, confidence: 0.7, evidence: evidenceSegments?.slice(0, 1) });
    const names = titleEntities(`${title} ${text}`);
    const entities = names.map((name) => ({
      type: (/\b(postgresql|sqlite|react|typescript|ocr|docker|fusion)\b/i.test(name) ? "technology" : /^(Bill|Yancy|Alice|Bob)$/i.test(name) ? "person" : "project") as EntityType,
      name,
    }));
    return {
      summary: (sentences[0] ?? text).slice(0, 240),
      memories,
      entities,
      openLoops: loops,
      relationships: entities.map((entity) => ({ entityName: entity.name, relationshipType: "mentions", confidence: 0.8 })),
      meeting: mockMeeting(sentences, memories, loops, questions),
    };
  }

  async answerQuestion(question: string, context: string) {
    const lines = context.split("\n").filter(Boolean);
    const q = question.toLowerCase();
    if (!lines.length) return "I don't have enough evidence in your memories to answer that confidently.";
    if (/database|storage|sql|choose|decid/.test(q)) {
      const preferred = lines.find((line) => /postgresql/i.test(line) && !/superseded/i.test(line));
      if (preferred) return `You chose PostgreSQL for the project. ${preferred.replace(/^[-*]\s*/, "")}`;
      const any = lines.find((line) => /sqlite/i.test(line));
      if (any) return `The available memory mentions SQLite, but I could not confirm it is still current. ${any.replace(/^[-*]\s*/, "")}`;
    }
    const relevant = lines.find((line) => q.split(/\W+/).some((term) => term.length > 3 && line.toLowerCase().includes(term))) ?? lines[0];
    return `Based on your captured memories: ${relevant.replace(/^[-*]\s*/, "")}`;
  }
}

export class FixtureTranscriptionProvider implements TranscriptionProvider {
  constructor(private readonly fixture: string | TranscriptionResult) {}

  async transcribe(_input: TranscriptionInput) {
    if (typeof this.fixture !== "string") return this.fixture;
    return { text: this.fixture, segments: [{ text: this.fixture }] };
  }
}

function milliseconds(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) ? Math.round(value * 1000) : undefined;
}

function parseWord(raw: any): TranscriptWord | undefined {
  const word = String(raw?.word ?? raw?.text ?? "").trim();
  if (!word) return undefined;
  return {
    word,
    startMs: typeof raw?.startMs === "number" ? raw.startMs : milliseconds(raw?.start),
    endMs: typeof raw?.endMs === "number" ? raw.endMs : milliseconds(raw?.end),
    confidence: typeof raw?.confidence === "number" ? raw.confidence : undefined,
  };
}

function parseSegment(raw: any): TranscriptionSegment | undefined {
  const text = String(raw?.text ?? "").trim();
  if (!text) return undefined;
  const words = Array.isArray(raw?.words) ? raw.words.map(parseWord).filter(Boolean) as TranscriptWord[] : undefined;
  return {
    startMs: typeof raw?.startMs === "number" ? raw.startMs : milliseconds(raw?.start),
    endMs: typeof raw?.endMs === "number" ? raw.endMs : milliseconds(raw?.end),
    text,
    speaker: typeof raw?.speaker === "string" ? raw.speaker : undefined,
    confidence: typeof raw?.confidence === "number" ? raw.confidence : undefined,
    words,
  };
}

export function parseTranscriptionResponse(raw: unknown): TranscriptionResult {
  const value = raw && typeof raw === "object" ? raw as any : {};
  const text = typeof value.text === "string" ? value.text.trim() : "";
  const topWords = Array.isArray(value.words) ? value.words.map(parseWord).filter(Boolean) as TranscriptWord[] : [];
  let segments = Array.isArray(value.segments) ? value.segments.map(parseSegment).filter(Boolean) as TranscriptionSegment[] : [];
  if (topWords.length && segments.length) {
    segments = segments.map((segment) => {
      const start = segment.startMs ?? 0;
      const end = segment.endMs ?? Number.MAX_SAFE_INTEGER;
      const words = topWords.filter((word) => {
        const point = word.startMs ?? word.endMs ?? 0;
        return point >= start && point <= end;
      });
      return { ...segment, words: words.length ? words : segment.words };
    });
  } else if (topWords.length && !segments.length && text) {
    segments = [{ text, startMs: topWords[0].startMs, endMs: topWords.at(-1)?.endMs, words: topWords }];
  }
  if (!text && segments.length) return { text: segments.map((segment) => segment.text).join(" ").trim(), segments, language: typeof value.language === "string" ? value.language : undefined };
  return { text, segments: text && !segments.length ? [{ text }] : segments, language: typeof value.language === "string" ? value.language : undefined };
}

export class OpenAICompatibleTranscriptionProvider implements TranscriptionProvider {
  private readonly settings: TranscriptionProviderSettings;

  constructor(settings: TranscriptionProviderSettings = { baseUrl: config.transcriptionBaseUrl, apiKey: config.transcriptionApiKey, model: config.transcriptionModel }) {
    this.settings = settings;
  }

  async transcribe(input: TranscriptionInput): Promise<TranscriptionResult> {
    const body = new FormData();
    const bytes = await fs.readFile(input.filePath);
    body.append("file", new Blob([bytes], { type: input.mimeType ?? "application/octet-stream" }), path.basename(input.filePath));
    body.append("model", this.settings.model);
    body.append("response_format", "verbose_json");
    body.append("timestamp_granularities[]", "segment");
    const headers: Record<string, string> = {};
    if (this.settings.apiKey) headers.Authorization = `Bearer ${this.settings.apiKey}`;
    const response = await fetch(`${this.settings.baseUrl.replace(/\/$/, "")}/audio/transcriptions`, {
      method: "POST",
      headers,
      body,
    });
    if (!response.ok) throw new Error(`Transcription provider returned ${response.status}`);
    const result = parseTranscriptionResponse(await response.json());
    if (!result.text) throw new Error("Transcription provider returned no text");
    return result;
  }
}

export class OpenAICompatibleProvider implements AIProvider {
  private readonly fallback = new MockAIProvider();

  private async providerError(response: Response) {
    let detail = `request failed with status ${response.status}`;
    try {
      const body = await response.json() as { error?: { message?: unknown }; message?: unknown };
      const candidate = body.error?.message ?? body.message;
      if (typeof candidate === "string" && candidate.trim()) detail = candidate.trim();
    } catch {
      // Some compatible providers return an empty or non-JSON error body.
    }
    return new Error(`AI provider returned ${response.status}: ${detail}`);
  }

  private async analyzeWindow(text: string, title: string, evidenceSegments: EvidenceHint[] | undefined, window: AnalysisWindow): Promise<Analysis> {
    const localOllama = isLocalOllamaUrl(config.llmBaseUrl);
    const scopeInstruction = window.total > 1
      ? `This is analysis window ${window.index + 1} of ${window.total}. Analyze only facts explicitly present in this window; do not infer facts from omitted windows. Never invent a date, time, year, name, or medical detail. If a year is not explicit, leave it out. Evidence must use the supplied segmentIndex values and exact supplied evidence text.`
      : "Use only facts explicitly present in the transcript. Never invent a date, time, year, name, or medical detail. If a year is not explicit, leave it out. Evidence must use the supplied segmentIndex values and exact supplied evidence text.";
    const systemPrompt = localOllama
      ? `Return one compact JSON object with exactly these fields: summary (string), memories (array of short strings), entities (array of short strings), openLoops (array of short strings), relationships (array of short strings), and meeting (object with keyPoints, decisions, actionItems, suggestedFollowUps, and unresolvedQuestions arrays of short strings). Keep each array to five items or fewer and each item concise. Do not include evidence objects, markdown, or commentary. ${scopeInstruction.replace(/ Evidence must use.*$/, "")}`
      : `Extract a concise, evidence-grounded meeting record from the supplied transcript. Always return all six top-level fields required by the schema: summary, memories, entities, openLoops, relationships, and meeting. Meeting must always contain keyPoints, decisions, actionItems, suggestedFollowUps, and unresolvedQuestions. Use an empty array for every unsupported category; never omit a required field. Return arrays of JSON objects, not prose strings. Memory objects use type, content, importance, confidence, and evidence. Claim objects use text, confidence, and evidence. Evidence objects use segmentIndex and exact text from the supplied evidence segments. Distinguish explicit decisions and commitments from suggestions. Action items and follow-ups must be genuinely actionable. Keep each category to its five most useful items so the response stays compact. ${scopeInstruction}`;
    const userContent = localOllama
      ? `Title: ${title}\nTranscript:\n${text}`
      : `Title: ${title}\nEvidence segments: ${JSON.stringify(evidenceSegments ?? [])}\nTranscript:\n${text}`;
    const response = await fetch(`${config.llmBaseUrl.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${config.llmApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: config.llmModel,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userContent },
        ],
        response_format: localOllama
          ? { type: "json_object" }
          : {
            type: "json_schema",
            json_schema: {
              name: "memory_garden_analysis",
              strict: true,
              schema: analysisJSONSchema,
            },
          },
        reasoning_effort: config.llmReasoningEffort,
        max_completion_tokens: localOllama ? 1024 : 4096,
        temperature: 0.1,
      }),
      ...(config.llmAnalysisTimeoutMs > 0 ? { signal: AbortSignal.timeout(config.llmAnalysisTimeoutMs) } : {}),
    });
    if (!response.ok) throw await this.providerError(response);
    const json = await response.json() as any;
    const content = json.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("AI provider returned no structured content");
    const parsed = analysisSchema.parse(normalizeAnalysis(JSON.parse(content)));
    const fallbackMeeting = await this.fallback.analyzeSource(text, title, evidenceSegments);
    const analysis: Analysis = {
      summary: parsed.summary,
      memories: parsed.memories,
      entities: parsed.entities,
      openLoops: parsed.openLoops,
      relationships: parsed.relationships,
      meeting: parsed.meeting ?? fallbackMeeting.meeting,
    };
    return sanitizeAnalysisEvidence(analysis, evidenceSegments, localOllama);
  }

  async analyzeSource(text: string, title: string, evidenceSegments?: EvidenceHint[]) {
    if (!(config.llmBaseUrl && config.llmApiKey && config.llmMode === "real")) return this.fallback.analyzeSource(text, title, evidenceSegments);
    const windows = splitAnalysisInput(text, evidenceSegments, config.llmAnalysisChunkChars);
    if (windows.length === 1) return this.analyzeWindow(text, title, evidenceSegments, windows[0]);

    const analyses: Analysis[] = [];
    for (const window of windows) {
      const startedAt = performance.now();
      processingInfo({ event: "analysis_chunk_started", model: config.llmModel, chunkIndex: window.index, chunkCount: window.total, textCharacters: window.text.length, evidenceSegments: window.evidenceSegments?.length ?? 0 }, "Local analysis window started");
      try {
        const analysis = await this.analyzeWindow(window.text, title, window.evidenceSegments, window);
        analyses.push(analysis);
        processingInfo({ event: "analysis_chunk_completed", model: config.llmModel, chunkIndex: window.index, chunkCount: window.total, elapsedMs: Math.round(performance.now() - startedAt), memoryCount: analysis.memories.length, actionItemCount: analysis.meeting.actionItems.length }, "Local analysis window completed");
      } catch (error) {
        const message = error instanceof Error ? error.message : "Unknown analysis error";
        processingError({ event: "analysis_chunk_failed", model: config.llmModel, chunkIndex: window.index, chunkCount: window.total, elapsedMs: Math.round(performance.now() - startedAt), error: message }, "Local analysis window failed");
        throw new Error(`Analysis window ${window.index + 1}/${window.total} failed: ${message}`);
      }
    }
    return mergeAnalyses(analyses);
  }

  async answerQuestion(question: string, context: string) {
    if (!(config.llmBaseUrl && config.llmApiKey && config.llmMode === "real")) return this.fallback.answerQuestion(question, context);
    const response = await fetch(`${config.llmBaseUrl.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${config.llmApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: config.llmModel, messages: [{ role: "system", content: "Answer only from the supplied personal-memory evidence. If it is insufficient, say so." }, { role: "user", content: `Question: ${question}\nEvidence:\n${context}` }], temperature: 0.1 }),
    });
    if (!response.ok) throw await this.providerError(response);
    const json = await response.json() as any;
    return String(json.choices?.[0]?.message?.content ?? "I don't have enough evidence in your memories to answer that confidently.");
  }
}

export const aiProvider: AIProvider = config.llmMode === "real" ? new OpenAICompatibleProvider() : new MockAIProvider();
const localWhisperSelected = ["local-whisper", "mac-local"].includes(config.transcriptionProvider.toLowerCase());
export const transcriptionProvider: TranscriptionProvider | undefined = localWhisperSelected && config.transcriptionMode !== "disabled"
  ? new LocalWhisperTranscriptionProvider()
  : config.transcriptionMode !== "disabled" && config.transcriptionApiKey && config.transcriptionBaseUrl && config.transcriptionModel
    ? new OpenAICompatibleTranscriptionProvider()
    : undefined;
