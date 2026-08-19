import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { config } from "./config.js";
import type { TranscriptionInput, TranscriptionProvider, TranscriptionResult } from "./ai.js";
import type { TranscriptWord } from "./types.js";

const execFileAsync=promisify(execFile);
const MIN_CHUNK_MS=30_000;

export interface TranscriptionChunkResult { result:TranscriptionResult; offsetMs:number; chunkIndex:number; }
export interface TranscriptionChunkingOptions { maxBytes?:number; chunkSeconds?:number; }

export function offsetTranscriptionResult(result:TranscriptionResult,offsetMs:number,chunkIndex:number):TranscriptionResult {const offset=(value:number|undefined)=>value===undefined?undefined:value+offsetMs;const words=(items:TranscriptWord[]|undefined)=>items?.map(word=>({...word,startMs:offset(word.startMs),endMs:offset(word.endMs)}));return {text:result.text,language:result.language,segments:result.segments.map(segment=>({...segment,startMs:offset(segment.startMs),endMs:offset(segment.endMs),words:words(segment.words),chunkIndex,chunkStartMs:offsetMs}))};}

export function mergeTranscriptionResults(results:TranscriptionChunkResult[]):TranscriptionResult {const ordered=results.flatMap(({result,offsetMs,chunkIndex})=>offsetTranscriptionResult(result,offsetMs,chunkIndex).segments).sort((a,b)=>{if(a.startMs===undefined&&b.startMs===undefined)return 0;if(a.startMs===undefined)return 1;if(b.startMs===undefined)return -1;return a.startMs-b.startMs;});return {text:results.map(x=>x.result.text.trim()).filter(Boolean).join(" ").trim(),language:results.find(x=>x.result.language)?.result.language,segments:ordered};}

async function probeDurationMs(filePath:string){try{const {stdout}=await execFileAsync(config.ffprobeBinary,["-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",filePath],{maxBuffer:1024*1024});const seconds=Number(String(stdout).trim());if(!Number.isFinite(seconds)||seconds<=0)throw new Error("ffprobe returned no usable duration");return Math.round(seconds*1000);}catch(error){const detail=error instanceof Error?error.message:"unknown ffprobe error";throw new Error(`Long recording transcription needs ffprobe to read audio duration: ${detail}`);}}

async function createAudioChunks(input:TranscriptionInput,durationMs:number,chunkDurationMs:number,tempDir:string){const chunks:{path:string;startMs:number;durationMs:number;index:number}[]=[];for(let startMs=0,index=0;startMs<durationMs;startMs+=chunkDurationMs,index+=1){const chunkDurationMsActual=Math.min(chunkDurationMs,durationMs-startMs);const output=path.join(tempDir,`chunk-${String(index).padStart(4,"0")}.webm`);try{await execFileAsync(config.ffmpegBinary,["-hide_banner","-loglevel","error","-ss",(startMs/1000).toFixed(3),"-i",input.filePath,"-t",(chunkDurationMsActual/1000).toFixed(3),"-vn","-map_metadata","-1","-c:a","libopus","-b:a","48k","-f","webm","-y",output],{maxBuffer:1024*1024});}catch(error){const detail=error instanceof Error?error.message:"unknown ffmpeg error";throw new Error(`Long recording transcription needs ffmpeg to create audio chunks: ${detail}`);}chunks.push({path:output,startMs,durationMs:chunkDurationMsActual,index});}return chunks;}

export async function transcribeWithChunking(provider:TranscriptionProvider,input:TranscriptionInput,options:TranscriptionChunkingOptions={}):Promise<TranscriptionResult>{const maxBytes=options.maxBytes??config.transcriptionMaxBytes;const stat=await fs.stat(input.filePath);const durationMs=input.durationMs??await probeDurationMs(input.filePath);const chunkDurationMs=Math.max(MIN_CHUNK_MS,Math.round((options.chunkSeconds??config.transcriptionChunkSeconds)*1000));const shouldChunk=stat.size>maxBytes||durationMs>chunkDurationMs;if(!shouldChunk)return provider.transcribe(input);const tempDir=await fs.mkdtemp(path.join(path.dirname(input.filePath),".transcription-"));try{const chunks=await createAudioChunks(input,durationMs,chunkDurationMs,tempDir);const results:TranscriptionChunkResult[]=[];for(const chunk of chunks){const result=await provider.transcribe({...input,filePath:chunk.path,mimeType:"audio/webm",durationMs:chunk.durationMs});results.push({result,offsetMs:chunk.startMs,chunkIndex:chunk.index});}return mergeTranscriptionResults(results);}finally{await fs.rm(tempDir,{recursive:true,force:true});}}
