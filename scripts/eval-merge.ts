/**
 * Evaluate merge quality by transcribing WAV files and showing raw segments
 * alongside the merged result. Caches transcriptions to JSON so you can
 * iterate on the merge algorithm without re-running whisper.
 *
 * Usage:
 *   bun scripts/eval-merge.ts [timestamp]           # one session
 *   bun scripts/eval-merge.ts                       # all sessions with WAVs
 *   bun scripts/eval-merge.ts --retranscribe [ts]   # force re-transcribe
 */

import { join } from "path";
import { existsSync, mkdirSync } from "fs";
import { transcribe, ensureModel } from "../src/transcribe.ts";
import { mergeTranscripts } from "../src/merge.ts";
import type { Segment } from "../src/transcribe.ts";

const RECORDINGS_DIR = join(process.cwd(), "recordings");
const CACHE_DIR = join(process.cwd(), "eval-cache");
const TRANSCRIPTS_DIR = join(process.cwd(), "transcripts");

mkdirSync(CACHE_DIR, { recursive: true });

function cachePathFor(ts: string, channel: "mic" | "speaker"): string {
  return join(CACHE_DIR, `${channel}_${ts}.json`);
}

async function getSegments(ts: string, channel: "mic" | "speaker", forceRetranscribe = false): Promise<Segment[]> {
  const cachePath = cachePathFor(ts, channel);
  if (!forceRetranscribe && existsSync(cachePath)) {
    return await Bun.file(cachePath).json();
  }
  const wavPath = join(RECORDINGS_DIR, `${channel}_${ts}.wav`);
  if (!existsSync(wavPath)) {
    throw new Error(`WAV not found: ${wavPath}`);
  }
  console.log(`  Transcribing ${channel}_${ts}.wav${channel === "speaker" ? " (VAD)" : ""}...`);
  const segments = await transcribe(wavPath, { vad: channel === "speaker" });
  await Bun.write(cachePath, JSON.stringify(segments, null, 2));
  return segments;
}

function fmt(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** Show segments as a compact timeline */
function showSegments(segments: Segment[], label: string) {
  console.log(`\n--- ${label} (${segments.length} segments) ---`);
  for (const seg of segments) {
    console.log(`  [${fmt(seg.start)}-${fmt(seg.end)}] ${seg.text}`);
  }
}

/**
 * Evaluate timestamp-based merge approach:
 * Any mic segment that temporally overlaps a speaker segment → Them.
 * Others → You.
 */
function evalTimestampMerge(micSegs: Segment[], speakerSegs: Segment[]): void {
  console.log("\n=== TIMESTAMP-BASED MERGE PREVIEW ===");

  type Labeled = { start: number; end: number; text: string; speaker: "You" | "Them" };
  const labeled: Labeled[] = [];

  for (const mic of micSegs) {
    const overlaps = speakerSegs.some(
      (sp) => sp.start < mic.end && sp.end > mic.start
    );
    labeled.push({ ...mic, speaker: overlaps ? "Them" : "You" });
  }

  // Merge consecutive same-speaker segments
  const runs: { speaker: "You" | "Them"; text: string; start: number; end: number }[] = [];
  for (const seg of labeled) {
    const prev = runs[runs.length - 1];
    if (prev && prev.speaker === seg.speaker) {
      prev.text += " " + seg.text;
      prev.end = seg.end;
    } else {
      runs.push({ ...seg });
    }
  }

  for (const run of runs) {
    const duration = run.end - run.start;
    const preview = run.text.slice(0, 120) + (run.text.length > 120 ? "..." : "");
    console.log(`\n[${fmt(run.start)}-${fmt(run.end)} ${duration.toFixed(0)}s] **${run.speaker}:** ${preview}`);
  }
}

/** Show current merged transcript */
async function showCurrentTranscript(ts: string): Promise<void> {
  const path = join(TRANSCRIPTS_DIR, `${ts}.md`);
  if (!existsSync(path)) {
    console.log("\n(no existing transcript)");
    return;
  }
  const content = await Bun.file(path).text();
  const lines = content.split("\n").filter((l) => l.startsWith("**"));
  console.log(`\n=== CURRENT TRANSCRIPT (${lines.length} turns) ===`);
  for (const line of lines.slice(0, 30)) {
    const preview = line.slice(0, 140) + (line.length > 140 ? "..." : "");
    console.log(preview);
  }
  if (lines.length > 30) console.log(`  ... (${lines.length - 30} more turns)`);
}

async function evalSession(ts: string, forceRetranscribe: boolean) {
  console.log(`\n${"=".repeat(70)}`);
  console.log(`SESSION: ${ts}`);
  console.log("=".repeat(70));

  let micSegs: Segment[], speakerSegs: Segment[];
  try {
    [micSegs, speakerSegs] = await Promise.all([
      getSegments(ts, "mic", forceRetranscribe),
      getSegments(ts, "speaker", forceRetranscribe),
    ]);
  } catch (e: any) {
    console.log(`  SKIP: ${e.message}`);
    return;
  }

  console.log(`  Mic: ${micSegs.length} segments, Speaker: ${speakerSegs.length} segments`);

  await showCurrentTranscript(ts);
  showSegments(micSegs, "MIC RAW");
  showSegments(speakerSegs, "SPEAKER RAW");
  evalTimestampMerge(micSegs, speakerSegs);
  await evalNewMerge(ts, micSegs, speakerSegs);
}

/** Run the updated merge algorithm and show turns */
async function evalNewMerge(ts: string, micSegs: Segment[], speakerSegs: Segment[]): Promise<void> {
  console.log("\n=== NEW MERGE PREVIEW ===");
  const tmpTs = `eval-tmp-${ts}`;
  const path = await mergeTranscripts(micSegs, speakerSegs, tmpTs);
  const content = await Bun.file(path).text();
  // Clean up temp file
  try { Bun.file(path); } catch {}
  const lines = content.split("\n").filter((l) => l.startsWith("**") || l.startsWith("*["));
  for (const line of lines.slice(0, 40)) {
    const preview = line.slice(0, 150) + (line.length > 150 ? "..." : "");
    console.log(preview);
  }
  if (lines.length > 40) console.log(`  ... (${lines.length - 40} more turns)`);
  // Remove the temp transcript
  const { unlinkSync } = await import("fs");
  try { unlinkSync(path); } catch {}
}

// --- main ---
const args = process.argv.slice(2);
const forceRetranscribe = args.includes("--retranscribe");
const tsArgs = args.filter((a) => !a.startsWith("--"));

await ensureModel();

const sessions: string[] = [];
if (tsArgs.length > 0) {
  sessions.push(...tsArgs);
} else {
  // Find all sessions that have both mic and speaker WAVs
  const files = Array.from(
    new Bun.Glob("mic_*.wav").scanSync(RECORDINGS_DIR)
  );
  for (const f of files.sort()) {
    const ts = f.replace(/^mic_/, "").replace(/\.wav$/, "");
    const speakerPath = join(RECORDINGS_DIR, `speaker_${ts}.wav`);
    if (existsSync(speakerPath)) sessions.push(ts);
  }
}

for (const ts of sessions) {
  await evalSession(ts, forceRetranscribe);
}

console.log("\nDone. Transcription cache:", CACHE_DIR);
