import fs from "node:fs";
import path from "node:path";
import { config } from "./config.js";
import type { Chunk, Entity, Memory, OpenLoop, ProcessingJob, RecordingSession, Relationship, Source, TranscriptSegment } from "./types.js";

export const STORAGE_VERSION = 2;
type State={storageVersion:number;sources:Source[];memories:Memory[];entities:Entity[];relationships:Relationship[];openLoops:OpenLoop[];chunks:Chunk[];jobs:ProcessingJob[];recordingSessions:RecordingSession[];transcriptSegments:TranscriptSegment[];[key:string]:unknown};
const file=path.join(config.dataDir,"memory-garden.json");
fs.mkdirSync(path.join(config.dataDir,"uploads"),{recursive:true});
const defaultState=():State=>({storageVersion:STORAGE_VERSION,sources:[],memories:[],entities:[],relationships:[],openLoops:[],chunks:[],jobs:[],recordingSessions:[],transcriptSegments:[]});
const objectValue=(raw:unknown):Record<string,unknown>=>raw&&typeof raw==="object"&&!Array.isArray(raw)?raw as Record<string,unknown>:{};
export function normalizeState(raw:unknown):State { const input=objectValue(raw); const out={...defaultState(),...input,storageVersion:STORAGE_VERSION}; out.sources=Array.isArray(input.sources)?(input.sources as Source[]).map(s=>({...s,metadata:s.metadata??{},transcriptStatus:s.transcriptStatus??(s.type==="voice"?"pending":"not_applicable")})):[]; out.memories=Array.isArray(input.memories)?input.memories:[];out.entities=Array.isArray(input.entities)?input.entities:[];out.relationships=Array.isArray(input.relationships)?input.relationships:[];out.openLoops=Array.isArray(input.openLoops)?input.openLoops:[];out.chunks=Array.isArray(input.chunks)?input.chunks:[];out.jobs=Array.isArray(input.jobs)?input.jobs:[];out.recordingSessions=Array.isArray(input.recordingSessions)?input.recordingSessions:[];out.transcriptSegments=Array.isArray(input.transcriptSegments)?input.transcriptSegments:[];return out; }
let state:State=defaultState();
try{if(fs.existsSync(file))state=normalizeState(JSON.parse(fs.readFileSync(file,"utf8")));}catch{state=defaultState();}
const save=()=>{const temp=`${file}.tmp`;fs.writeFileSync(temp,JSON.stringify(state,null,2));fs.renameSync(temp,file);};
const now=()=>new Date().toISOString();
export const store={
  createSource(input:Partial<Source>&{type:Source["type"];title:string}){const t=now();const s:Source={id:input.id??crypto.randomUUID(),type:input.type,title:input.title,originalText:input.originalText??"",extractedText:input.extractedText??"",sourceUrl:input.sourceUrl,filePath:input.filePath,mimeType:input.mimeType,createdAt:t,updatedAt:t,capturedAt:input.capturedAt??t,processingStatus:input.processingStatus??"pending",processingError:input.processingError,metadata:input.metadata??{},summary:input.summary,transcriptText:input.transcriptText,transcriptStatus:input.transcriptStatus??(input.type==="voice"?"pending":"not_applicable"),durationMs:input.durationMs,audioMimeType:input.audioMimeType,consentMode:input.consentMode,consentAcknowledged:input.consentAcknowledged,recordingSessionId:input.recordingSessionId,processingVersion:input.processingVersion??0};state.sources.push(s);save();return s;},
  getSource(id:string){return state.sources.find(x=>x.id===id);},
  findSourceByClientRecordingId(clientRecordingId:string){return state.sources.find(x=>x.type==="voice"&&x.metadata?.clientRecordingId===clientRecordingId);},
  listSources(limit=50,offset=0){return state.sources.slice().sort((a,b)=>b.capturedAt.localeCompare(a.capturedAt)).slice(offset,offset+limit);},
  updateSource(id:string,patch:Partial<Source>){const s=this.getSource(id);if(!s)return;Object.assign(s,patch,{updatedAt:now()});save();return s;},
  createRecordingSession(input:Omit<RecordingSession,"id">){const session:RecordingSession={...input,id:crypto.randomUUID()};state.recordingSessions.push(session);save();return session;},
  getRecordingSession(id:string){return state.recordingSessions.find(x=>x.id===id);},
  getRecordingSessionForSource(sourceId:string){return state.recordingSessions.find(x=>x.sourceId===sourceId);},
  updateRecordingSession(id:string,patch:Partial<RecordingSession>){const s=this.getRecordingSession(id);if(!s)return;Object.assign(s,patch);save();return s;},
  createJob(sourceId:string){const t=now();const j:ProcessingJob={id:crypto.randomUUID(),sourceId,status:"pending",attempts:0,createdAt:t,updatedAt:t};state.jobs.push(j);save();return j.id;},
  updateJob(id:string,status:string,error?:string){const j=state.jobs.find(x=>x.id===id);if(j){j.status=status;j.attempts+=1;j.error=error;j.updatedAt=now();save();}},
  pendingJobs(){return state.jobs.filter(j=>j.status==="pending"||j.status==="processing");},
  createMemory(input:Omit<Memory,"createdAt">&{createdAt?:string}){const m={...input,createdAt:input.createdAt??now()};state.memories.push(m);save();return m;},
  getMemory(id:string){return state.memories.find(x=>x.id===id);},
  listMemories(type?:string){return state.memories.filter(m=>m.status==="active"&&(!type||m.memoryType===type)).sort((a,b)=>b.createdAt.localeCompare(a.createdAt));},
  updateMemory(id:string,patch:Partial<Memory>){const m=this.getMemory(id);if(!m)return;Object.assign(m,patch);save();return m;},
  memoriesForSource(sourceId:string){return state.memories.filter(m=>m.sourceId===sourceId).sort((a,b)=>b.createdAt.localeCompare(a.createdAt));},
  clearDerived(sourceId:string){const ids=new Set(state.memories.filter(m=>m.sourceId===sourceId).map(m=>m.id));state.memories=state.memories.filter(m=>m.sourceId!==sourceId);state.openLoops=state.openLoops.filter(l=>!ids.has(l.memoryId));state.relationships=state.relationships.filter(r=>r.sourceId!==sourceId);state.chunks=state.chunks.filter(c=>c.sourceId!==sourceId);save();},
  findEntities(){return state.entities.slice().sort((a,b)=>b.updatedAt.localeCompare(a.updatedAt));},
  upsertEntity(type:Entity["entityType"],name:string,description=""){const canonical=name.trim().replace(/\s+/g," ");const old=state.entities.find(e=>e.entityType===type&&e.canonicalName.toLowerCase()===canonical.toLowerCase());if(old)return old;const t=now();const e:Entity={id:crypto.randomUUID(),entityType:type,canonicalName:canonical,description,createdAt:t,updatedAt:t};state.entities.push(e);save();return e;},
  entitiesForSource(sourceId:string){const ids=new Set(state.relationships.filter(r=>r.sourceId===sourceId&&r.toType==="entity").map(r=>r.toId));return state.entities.filter(e=>ids.has(e.id));},
  addRelationship(r:Omit<Relationship,"id"|"createdAt">){state.relationships.push({...r,id:crypto.randomUUID(),createdAt:now()});save();},
  addLoop(input:Omit<OpenLoop,"id"|"createdAt">&{createdAt?:string}){const x:OpenLoop={...input,id:crypto.randomUUID(),createdAt:input.createdAt??now()};state.openLoops.push(x);save();return x;},
  listLoops(status?:string){return state.openLoops.filter(l=>!status||l.status===status).sort((a,b)=>(a.status==="open"?0:1)-(b.status==="open"?0:1)||b.createdAt.localeCompare(a.createdAt));},
  getLoop(id:string){return state.openLoops.find(x=>x.id===id);},
  updateLoop(id:string,status:OpenLoop["status"]){const l=this.getLoop(id);if(!l)return;l.status=status;l.resolvedAt=status==="open"?undefined:now();save();return l;},
  replaceChunks(sourceId:string,parts:string[]){state.chunks=state.chunks.filter(c=>c.sourceId!==sourceId);const out=parts.map((text,i)=>({id:crypto.randomUUID(),sourceId,chunkIndex:i,text:text.trim(),createdAt:now()}));state.chunks.push(...out);save();return out;},
  transcriptForSource(sourceId:string){return state.transcriptSegments.filter(s=>s.sourceId===sourceId).sort((a,b)=>a.segmentIndex-b.segmentIndex);},
  replaceTranscript(sourceId:string,segments:Array<Omit<TranscriptSegment,"id"|"sourceId"|"createdAt">>){state.transcriptSegments=state.transcriptSegments.filter(s=>s.sourceId!==sourceId);const out=segments.map(s=>({...s,id:crypto.randomUUID(),sourceId,createdAt:now()}));state.transcriptSegments.push(...out);save();return out;},
  search(q:string,type?:string){const terms=q.toLowerCase().split(/\W+/).filter(Boolean);const sources=new Map(this.listSources(10000).map(s=>[s.id,s]));const entities=this.findEntities();return this.listMemories(type).map(m=>{const s=sources.get(m.sourceId);const related=entities.filter(e=>state.relationships.some(r=>r.sourceId===m.sourceId&&r.toId===e.id)).map(e=>e.canonicalName).join(" ");const hay=`${m.content} ${m.summary} ${s?.title??""} ${s?.transcriptText??""} ${related}`.toLowerCase();const score=terms.reduce((n,t)=>n+(hay.includes(t)?1:0),0);return {...m,source:s,score};}).filter(x=>x.score>0).sort((a,b)=>b.score-a.score||b.createdAt.localeCompare(a.createdAt)).slice(0,30);},
  recentSources(){return this.listSources(8);},
  resurfaced(){return this.listMemories().filter(m=>Date.now()-Date.parse(m.createdAt)>1000*60*60*24*2).slice(0,4);},
  deleteSource(id:string){const s=this.getSource(id);if(!s)return false;const memIds=new Set(state.memories.filter(m=>m.sourceId===id).map(m=>m.id));state.sources=state.sources.filter(x=>x.id!==id);state.memories=state.memories.filter(m=>m.sourceId!==id);state.openLoops=state.openLoops.filter(l=>!memIds.has(l.memoryId));state.relationships=state.relationships.filter(r=>r.sourceId!==id);state.chunks=state.chunks.filter(c=>c.sourceId!==id);state.jobs=state.jobs.filter(j=>j.sourceId!==id);state.recordingSessions=state.recordingSessions.filter(x=>x.sourceId!==id);state.transcriptSegments=state.transcriptSegments.filter(x=>x.sourceId!==id);try{if(s.filePath&&fs.existsSync(s.filePath))fs.unlinkSync(s.filePath);}catch{/* missing files are already deleted */}save();return true;},
  exportData(){return {storageVersion:STORAGE_VERSION,sources:this.listSources(10000),recordingSessions:state.recordingSessions,transcriptSegments:state.transcriptSegments,memories:state.memories,entities:this.findEntities(),openLoops:this.listLoops(),evidenceRefs:state.memories.flatMap(m=>m.evidenceRefs??[])};}
};
