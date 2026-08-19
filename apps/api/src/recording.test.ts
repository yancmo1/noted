import { describe,expect,it } from "vitest";
import { FixtureTranscriptionProvider } from "./ai.js";
import { processSource } from "./processor.js";
import { store } from "./db.js";

describe("transcript analysis",()=>{
  it("maps fixture segments into evidence-backed memories and repairs chunk boundaries",async()=>{
    const source=store.createSource({type:"voice",title:"Training conversation",originalText:"",extractedText:"",transcriptText:"Bill said the training cohort will start next month. I decided to send the updated schedule on Friday. I still need to ask Bill for the final attendee list.",transcriptStatus:"ready"});
    const segments=store.replaceTranscript(source.id,[{segmentIndex:0,startMs:0,endMs:4000,text:"Bill said the training cohort will start next month."},{segmentIndex:1,startMs:4000,endMs:8000,text:"I decided to send the updated schedule on Friday."},{segmentIndex:2,startMs:8000,endMs:12000,text:"I still need to ask Bill for the final attendee list."}]);
    await processSource(source.id);
    const processed=store.getSource(source.id)!;
    expect(processed.summary).toMatch(/Bill said/);
    expect(processed.meetingBrief?.schemaVersion).toBe(1);
    expect(processed.meetingBrief?.keyPoints.length).toBeGreaterThan(0);
    expect(processed.meetingBrief?.decisions.length).toBeGreaterThan(0);
    expect(processed.meetingBrief?.actionItems.length).toBeGreaterThan(0);
    expect(processed.meetingBrief?.actionItems[0].evidenceRefs[0]?.segmentId).toBeTruthy();
    expect(segments).toHaveLength(3);
    expect(store.transcriptForSource(source.id)).toHaveLength(3);
    const memories=store.memoriesForSource(source.id);
    expect(memories.some(m=>m.memoryType==="decision")).toBe(true);
    expect(memories.some(m=>m.evidenceRefs?.some(e=>e.startMs===4000))).toBe(true);
    expect(store.search("training cohort").some(r=>r.sourceId===source.id)).toBe(true);
    store.deleteSource(source.id);
  });
  it("normalizes an explicit fixture without pretending arbitrary bytes are speech",async()=>{
    const result=await new FixtureTranscriptionProvider({text:"fixture transcript",segments:[{startMs:100,text:"fixture transcript"}]}).transcribe({filePath:"not-used",sourceId:"fixture"});
    expect(result.text).toBe("fixture transcript");
    expect(result.segments[0].startMs).toBe(100);
  });
});
