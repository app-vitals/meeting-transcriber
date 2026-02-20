/**
 * Re-run the merge algorithm on all cached transcriptions.
 *
 * Reads mic/speaker JSON from eval-cache/ (created by eval-merge.ts)
 * and writes updated transcript files to transcripts/.
 *
 * Usage:
 *   bun scripts/remerge.ts              # all cached sessions
 *   bun scripts/remerge.ts 2026-02-20   # specific session
 */

import { join } from "path";
import { existsSync } from "fs";
import { mergeTranscripts } from "../src/merge.ts";

const CACHE_DIR = join(process.cwd(), "eval-cache");

const args = process.argv.slice(2).filter((a) => !a.startsWith("--"));

const files = Array.from(new Bun.Glob("mic_*.json").scanSync(CACHE_DIR)).sort();

for (const f of files) {
  const ts = f.replace(/^mic_/, "").replace(/\.json$/, "");

  // Filter to specified sessions if args provided
  if (args.length > 0 && !args.some((a) => ts.includes(a))) continue;

  const speakerPath = join(CACHE_DIR, `speaker_${ts}.json`);
  if (!existsSync(speakerPath)) {
    console.log(`SKIP ${ts} — no speaker cache`);
    continue;
  }

  const micSegs = await Bun.file(join(CACHE_DIR, f)).json();
  const speakerSegs = await Bun.file(speakerPath).json();
  const path = await mergeTranscripts(micSegs, speakerSegs, ts);
  console.log(`Written: ${path}`);
}
