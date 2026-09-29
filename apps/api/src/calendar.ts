import type { CalendarCandidate, EvidenceRef, TranscriptSegment } from "./types.js";

const months = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
] as const;

const datePattern = new RegExp(
  `\\b(${months.join("|")})\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*,?\\s*(\\d{4}))?`,
  "gi",
);
const timePattern = /\b(\d{1,2})\s*(?:[:.]|\s)\s*(\d{2})\s*(AM|PM)\b/i;
const shortTimePattern = /\b(\d{1,2})\s*(AM|PM)\b/i;

function nearbySegments(segments: TranscriptSegment[], index: number): TranscriptSegment[] {
  const anchor = segments[index];
  if (!anchor || anchor.startMs === undefined) {
    return segments.slice(Math.max(0, index - 6), Math.min(segments.length, index + 7));
  }
  const anchorStart = anchor.startMs;
  return segments.filter((segment) => Math.abs((segment.startMs ?? anchorStart) - anchorStart) <= 180_000);
}

function contextFor(segments: TranscriptSegment[], index: number): string {
  return nearbySegments(segments, index).map((segment) => segment.text).join(" ");
}

function normalizeTime(context: string): string | undefined {
  const detailed = context.match(timePattern);
  if (detailed) return `${Number(detailed[1])}:${detailed[2]} ${detailed[3].toUpperCase()}`;
  const short = context.match(shortTimePattern);
  return short ? `${Number(short[1])}:00 ${short[2].toUpperCase()}` : undefined;
}

function evidenceFor(sourceId: string, segments: TranscriptSegment[], dateText: string, context: string): EvidenceRef[] {
  const lowerDate = dateText.toLowerCase();
  const lowerContext = context.toLowerCase();
  const ranked = segments
    .map((segment, index) => {
      const text = segment.text.toLowerCase();
      const score = (text.includes(lowerDate) ? 3 : 0)
        + (/\b\d{1,2}\s*(?:[:.]|\s)\s*\d{2}\s*(?:am|pm)\b/i.test(text) ? 2 : 0)
        + (lowerContext.includes(text) && /\b(?:follow[- ]?up|verify|vacation|waitlist|out of town)\b/i.test(text) ? 1 : 0);
      return { segment, index, score };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score || a.index - b.index);
  const selected: typeof ranked = [];
  const select = (predicate: (item: (typeof ranked)[number]) => boolean) => {
    const item = ranked.find((candidate) => !selected.includes(candidate) && predicate(candidate));
    if (item) selected.push(item);
  };
  select((item) => item.segment.text.toLowerCase().includes(lowerDate));
  select((item) => /\b\d{1,2}\s*(?:[:.]|\s)\s*\d{2}\s*(?:am|pm)\b/i.test(item.segment.text));
  select((item) => /\b(?:verify|vacation|waitlist|out of town)\b/i.test(item.segment.text));
  ranked.forEach((item) => {
    if (selected.length < 3 && !selected.includes(item)) selected.push(item);
  });
  return selected
    .slice(0, 3)
    .map(({ segment }) => ({
      sourceId,
      segmentId: segment.id,
      startMs: segment.startMs,
      endMs: segment.endMs,
      quote: segment.text.trim(),
    }));
}

export function extractCalendarCandidates(sourceId: string, sourceTitle: string, segments: TranscriptSegment[]): CalendarCandidate[] {
  const candidates: CalendarCandidate[] = [];
  const seen = new Set<string>();

  segments.forEach((segment, index) => {
    for (const match of segment.text.matchAll(datePattern)) {
      const month = match[1];
      const day = match[2];
      const year = match[3];
      if (!month || !day) continue;

      const dateText = `${month} ${Number(day)}${year ? `, ${year}` : ""}`;
      const context = contextFor(segments, index);
      const timeText = normalizeTime(context);
      const contextLower = context.toLowerCase();
      const rejected = segments.slice(index, index + 4).some((candidate) => (
        candidate.startMs !== undefined &&
        segment.startMs !== undefined &&
        candidate.startMs - segment.startMs <= 30_000 &&
        /\b(?:too far|not available|can't|cannot)\b/i.test(candidate.text)
      ));
      if (rejected) continue;
      const key = dateText.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);

      const ambiguous = /\b(?:verify|waitlist|out of town|vacation|i think|reschedul)/i.test(contextLower);
      const title = /\b(?:follow[- ]?up|doctor|appointment|clinic|visit)\b/i.test(`${sourceTitle} ${context}`)
        ? "Doctor follow-up"
        : "Follow-up";
      const confidence = ambiguous ? 0.82 : timeText ? 0.9 : 0.68;
      candidates.push({
        id: crypto.randomUUID(),
        title,
        dateText,
        timeText,
        datePrecision: year ? "full_date" : "month_day",
        confidence,
        state: "generated",
        needsConfirmation: !year || !timeText || ambiguous,
        evidenceRefs: evidenceFor(sourceId, segments, `${month} ${day}`, context),
      });
    }
  });

  return candidates;
}
