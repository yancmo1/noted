import fs from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { config } from "./config.js";
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
    body.append("timestamp_granularities[]", "word");
    const response = await fetch(`${this.settings.baseUrl.replace(/\/$/, "")}/audio/transcriptions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${this.settings.apiKey}` },
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

  async analyzeSource(text: string, title: string, evidenceSegments?: EvidenceHint[]) {
    if (!(config.llmBaseUrl && config.llmApiKey && config.llmMode === "real")) return this.fallback.analyzeSource(text, title, evidenceSegments);
    const response = await fetch(`${config.llmBaseUrl.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${config.llmApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: config.llmModel,
        messages: [
          {
            role: "system",
            content: "Extract a meeting record from the supplied transcript. Return only JSON with summary, memories, entities, openLoops, relationships, and meeting. meeting must contain summary, keyPoints, decisions, actionItems, suggestedFollowUps, unresolvedQuestions. Each claim has text, confidence, and evidence segment indexes. Action item owner and dueAt are inferred values with confidence; omit them when not supported.",
          },
          { role: "user", content: `Title: ${title}\nEvidence segments: ${JSON.stringify(evidenceSegments ?? [])}\nTranscript:\n${text}` },
        ],
        response_format: { type: "json_object" },
        temperature: 0.1,
      }),
    });
    if (!response.ok) throw new Error(`AI provider returned ${response.status}`);
    const json = await response.json() as any;
    const content = json.choices?.[0]?.message?.content;
    if (typeof content !== "string") throw new Error("AI provider returned no structured content");
    const parsed = analysisSchema.parse(JSON.parse(content));
    const fallbackMeeting = await this.fallback.analyzeSource(text, title, evidenceSegments);
    return { ...parsed, meeting: parsed.meeting ?? fallbackMeeting.meeting } as Analysis;
  }

  async answerQuestion(question: string, context: string) {
    if (!(config.llmBaseUrl && config.llmApiKey && config.llmMode === "real")) return this.fallback.answerQuestion(question, context);
    const response = await fetch(`${config.llmBaseUrl.replace(/\/$/, "")}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${config.llmApiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: config.llmModel, messages: [{ role: "system", content: "Answer only from the supplied personal-memory evidence. If it is insufficient, say so." }, { role: "user", content: `Question: ${question}\nEvidence:\n${context}` }], temperature: 0.1 }),
    });
    if (!response.ok) throw new Error(`AI provider returned ${response.status}`);
    const json = await response.json() as any;
    return String(json.choices?.[0]?.message?.content ?? "I don't have enough evidence in your memories to answer that confidently.");
  }
}

export const aiProvider: AIProvider = config.llmMode === "real" ? new OpenAICompatibleProvider() : new MockAIProvider();
export const transcriptionProvider: TranscriptionProvider | undefined = config.transcriptionMode !== "disabled" && config.transcriptionApiKey && config.transcriptionBaseUrl && config.transcriptionModel
  ? new OpenAICompatibleTranscriptionProvider()
  : undefined;
