import { describe,expect,it } from "vitest";
import fs from "node:fs/promises";
import path from "node:path";
import { config } from "./config.js";
import { MockAIProvider, OpenAICompatibleTranscriptionProvider } from "./ai.js";

describe("mock AI",()=>{
  it("extracts decisions, entities, and open loops",async()=>{const r=await new MockAIProvider().analyzeSource("I decided that Project Atlas will use PostgreSQL instead of SQLite. I still need to migrate the old records this weekend.","Atlas note");expect(r.memories.some(x=>x.type==="decision"&&/PostgreSQL/.test(x.content))).toBe(true);expect(r.openLoops[0].description).toMatch(/migrate/);expect(r.entities.some(x=>x.name.includes("Atlas"))).toBe(true);});
  it("answers with grounded context",async()=>{const r=await new MockAIProvider().answerQuestion("What database did I choose?","- I decided to use PostgreSQL for Atlas");expect(r).toMatch(/PostgreSQL/);});
  it("requests Groq verbose JSON with segment and word timestamps",async()=>{const filePath=path.join(config.dataDir,"uploads","provider-payload-test.webm");await fs.writeFile(filePath,"audio");const originalFetch=globalThis.fetch;let requestBody:FormData|undefined;globalThis.fetch=async(_input,init)=>{requestBody=init?.body as FormData;return new Response(JSON.stringify({text:"Hello world",language:"en",segments:[{start:1.2,end:2.4,text:"Hello world"}],words:[{word:"Hello",start:1.2,end:1.7},{word:"world",start:1.8,end:2.4}]}),{status:200,headers:{"content-type":"application/json"}});};try{const result=await new OpenAICompatibleTranscriptionProvider({baseUrl:"https://api.groq.com/openai/v1",apiKey:"test-key",model:"whisper-large-v3-turbo"}).transcribe({filePath,sourceId:"provider-test",mimeType:"audio/webm"});expect(requestBody?.get("model")).toBe("whisper-large-v3-turbo");expect(requestBody?.get("response_format")).toBe("verbose_json");expect(requestBody?.getAll("timestamp_granularities[]")).toEqual(["segment","word"]);expect(result.segments[0].startMs).toBe(1200);expect(result.segments[0].words?.[1].endMs).toBe(2400);}finally{globalThis.fetch=originalFetch;await fs.rm(filePath,{force:true});}});
});
