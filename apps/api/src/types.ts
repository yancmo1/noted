export type SourceType = "note" | "voice" | "file" | "url" | "image";
export type ProcessingStatus = "pending" | "processing" | "ready" | "partial" | "failed";
export type MemoryType = "fact" | "decision" | "idea" | "task" | "question" | "preference" | "reference" | "observation" | "event";
export type LoopStatus = "open" | "resolved" | "dismissed";
export type EntityType = "person" | "project" | "organization" | "product" | "place" | "topic" | "technology" | "document";
export type TranscriptStatus = "not_applicable" | "pending" | "processing" | "ready" | "partial" | "failed";
export type ConsentMode = "private_thought" | "conversation" | "meeting";
export type RecordingStatus = "capturing" | "uploaded" | "processing" | "ready" | "partial" | "failed" | "cancelled";

export interface EvidenceRef { sourceId:string; segmentId?:string; startMs?:number; endMs?:number; quote?:string; }

export interface Source { id:string; type:SourceType; title:string; originalText:string; extractedText:string; sourceUrl?:string; filePath?:string; mimeType?:string; createdAt:string; updatedAt:string; capturedAt:string; processingStatus:ProcessingStatus; processingError?:string; metadata:Record<string, unknown>; summary?:string; transcriptText?:string; transcriptStatus?:TranscriptStatus; durationMs?:number; audioMimeType?:string; consentMode?:ConsentMode; consentAcknowledged?:boolean; recordingSessionId?:string; processingVersion?:number; }
export interface Memory { id:string; sourceId:string; memoryType:MemoryType; content:string; summary:string; importance:number; confidence:number; occurredAt?:string; createdAt:string; supersededBy?:string; status:"active"|"dismissed"; metadata:Record<string, unknown>; evidenceRefs?:EvidenceRef[]; }
export interface Entity { id:string; entityType:EntityType; canonicalName:string; description:string; createdAt:string; updatedAt:string; }
export interface Relationship { id:string; fromType:string; fromId:string; relationshipType:string; toType:string; toId:string; confidence:number; sourceId:string; createdAt:string; }
export interface OpenLoop { id:string; memoryId:string; description:string; status:LoopStatus; dueAt?:string; confidence:number; createdAt:string; resolvedAt?:string; evidenceRefs?:EvidenceRef[]; }
export interface Chunk { id:string; sourceId:string; chunkIndex:number; text:string; createdAt:string; }
export interface ProcessingJob { id:string; sourceId:string; status:string; attempts:number; error?:string; createdAt:string; updatedAt:string; }
export interface RecordingSession { id:string; sourceId:string; status:RecordingStatus; startedAt:string; endedAt?:string; durationMs?:number; mimeType?:string; client:"web"|"native"|"hardware"; consentMode:ConsentMode; consentAcknowledged:boolean; metadata:Record<string, unknown>; }
export interface TranscriptWord { word:string; startMs?:number; endMs?:number; confidence?:number; }
export interface TranscriptSegment { id:string; sourceId:string; segmentIndex:number; startMs?:number; endMs?:number; text:string; speaker?:string; confidence?:number; words?:TranscriptWord[]; chunkIndex?:number; chunkStartMs?:number; createdAt:string; }
