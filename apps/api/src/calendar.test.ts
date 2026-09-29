import { describe, expect, it } from "vitest";
import { extractCalendarCandidates } from "./calendar.js";
import type { TranscriptSegment } from "./types.js";

const segment = (id: string, segmentIndex: number, text: string, startMs: number): TranscriptSegment => ({
  id,
  sourceId: "source-1",
  segmentIndex,
  text,
  startMs,
  endMs: startMs + 2_000,
  createdAt: new Date(0).toISOString(),
});

describe("calendar candidate extraction", () => {
  it("keeps an appointment as a confirmation-required candidate when the year is missing or the recording is ambiguous", () => {
    const candidates = extractCalendarCandidates("source-1", "Doctor visit local tracer", [
      segment("date", 0, "The follow-up is November 10th.", 1_100_000),
      segment("context", 1, "We're going to be out of town that week.", 1_140_000),
      segment("other-date", 2, "December 2nd.", 1_150_000),
      segment("rejected", 3, "Yeah, that's too far.", 1_155_000),
      segment("time", 4, "10th, 8th, 10.45 AM, I think.", 1_180_000),
      segment("verify", 5, "Need to verify.", 1_185_000),
    ]);

    expect(candidates).toHaveLength(1);
    expect(candidates[0]).toMatchObject({
      title: "Doctor follow-up",
      dateText: "November 10",
      timeText: "10:45 AM",
      datePrecision: "month_day",
      state: "generated",
      needsConfirmation: true,
    });
    expect(candidates[0]?.evidenceRefs.map((ref) => ref.segmentId)).toEqual(["date", "time", "context"]);
  });
});
