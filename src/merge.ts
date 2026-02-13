/**
 * Merge mic and speaker transcripts into a single labeled timeline.
 *
 * Speaker segments are the clean reference. Mic segments that are just
 * speaker bleed (similar text at similar times) are filtered out.
 * Remaining mic segments are labeled as You, speaker segments as Them.
 */

import { join } from "path";
import { mkdirSync } from "fs";
import type { Segment } from "./transcribe.ts";

const TRANSCRIPTS_DIR = join(import.meta.dir, "..", "transcripts");

interface LabeledSegment extends Segment {
  speaker: "You" | "Them";
}

/** Format seconds as MM:SS. */
function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

/** Normalize text for comparison: lowercase, collapse whitespace, strip punctuation. */
function normalize(text: string): string {
  return text.toLowerCase().replace(/[^\w\s]/g, "").replace(/\s+/g, " ").trim();
}

/**
 * Check if two strings are similar enough to be the same speech.
 * Uses word overlap ratio — if most words match, it's a duplicate.
 */
function isSimilar(a: string, b: string): boolean {
  const wordsA = normalize(a).split(" ");
  const wordsB = new Set(normalize(b).split(" "));
  if (wordsA.length === 0) return true;

  const matchCount = wordsA.filter((w) => wordsB.has(w)).length;
  return matchCount / wordsA.length >= 0.6;
}

/**
 * Check if a mic segment is speaker bleed by finding a similar speaker segment
 * within a time window.
 */
function isBleed(micSeg: Segment, speakerSegments: Segment[]): boolean {
  const TIME_WINDOW = 15; // seconds of tolerance for time alignment
  return speakerSegments.some(
    (sp) =>
      Math.abs(micSeg.start - sp.start) < TIME_WINDOW &&
      isSimilar(micSeg.text, sp.text),
  );
}

/**
 * Merge mic and speaker segments into a labeled markdown transcript.
 * Returns the path to the written file.
 */
export async function mergeTranscripts(
  micSegments: Segment[],
  speakerSegments: Segment[],
  sessionTimestamp: string,
): Promise<string> {
  mkdirSync(TRANSCRIPTS_DIR, { recursive: true });

  // Filter out mic segments that are speaker bleed
  const uniqueMic = micSegments.filter((seg) => !isBleed(seg, speakerSegments));

  const labeled: LabeledSegment[] = [
    ...uniqueMic.map((s) => ({ ...s, speaker: "You" as const })),
    ...speakerSegments.map((s) => ({ ...s, speaker: "Them" as const })),
  ];

  labeled.sort((a, b) => a.start - b.start);

  // Format timestamp for display: 2026-02-13T19-25-11 → 2026-02-13 19:25
  const displayDate = sessionTimestamp
    .replace("T", " ")
    .replace(/-(\d{2})-(\d{2})$/, ":$1");

  let md = `# Meeting Transcript — ${displayDate}\n\n`;

  for (const seg of labeled) {
    md += `[${formatTime(seg.start)}] **${seg.speaker}:** ${seg.text}\n\n`;
  }

  const filePath = join(TRANSCRIPTS_DIR, `${sessionTimestamp}.md`);
  await Bun.write(filePath, md);
  return filePath;
}
