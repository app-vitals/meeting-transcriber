#!/usr/bin/env bun
/**
 * transcripts.ts — Fetch meeting transcripts by natural language time query.
 *
 * Usage:
 *   bun plugins/meeting-transcripts/transcripts.ts [query]
 *
 * Query examples:
 *   latest          Most recent transcript (default)
 *   today           All transcripts from today
 *   yesterday       All transcripts from yesterday
 *   9am             Transcript closest to 9am today
 *   Monday          All transcripts from the most recent Monday
 *   last Friday     All transcripts from last Friday
 *   2026-01-15      All transcripts from that date
 *
 * Output:
 *   - Single match: prints full transcript content
 *   - Multiple matches: prints list with date/time, filename, and first 3 lines
 *   - No match: prints helpful error with available date range
 */

import { readdirSync, statSync, existsSync, readFileSync } from "fs";
import { join, resolve, basename } from "path";
import { parseTimeQuery, parseTranscriptDate, type DateRange } from "./time-parser.ts";

const TRANSCRIPTS_DIR = resolve(process.env.HOME ?? "~", "transcripts");
const SNIPPET_LINES = 3;

// ---------------------------------------------------------------------------
// Transcript discovery
// ---------------------------------------------------------------------------

interface TranscriptEntry {
  filename: string;
  path: string;
  date: Date;
  mtime: Date;
}

function loadTranscripts(): TranscriptEntry[] {
  if (!existsSync(TRANSCRIPTS_DIR)) return [];

  const entries: TranscriptEntry[] = [];
  for (const filename of readdirSync(TRANSCRIPTS_DIR)) {
    if (!filename.endsWith(".md")) continue;
    const path = join(TRANSCRIPTS_DIR, filename);
    const date = parseTranscriptDate(filename);
    if (!date) continue;
    let mtime: Date;
    try {
      mtime = statSync(path).mtime;
    } catch {
      mtime = date;
    }
    entries.push({ filename, path, date, mtime });
  }

  // Sort newest first
  entries.sort((a, b) => b.date.getTime() - a.date.getTime());
  return entries;
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

function matchTranscripts(
  entries: TranscriptEntry[],
  range: DateRange | null,
): TranscriptEntry[] {
  if (range === null) {
    // Latest by mtime
    if (entries.length === 0) return [];
    const latest = entries.reduce((a, b) => (a.mtime > b.mtime ? a : b));
    return [latest];
  }

  const inRange = entries.filter(
    (e) => e.date >= range.start && e.date <= range.end,
  );

  if (range.closestTo && inRange.length > 1) {
    // Return only the single closest entry
    const target = range.closestTo.getTime();
    inRange.sort((a, b) => Math.abs(a.date.getTime() - target) - Math.abs(b.date.getTime() - target));
    return [inRange[0]];
  }

  return inRange;
}

// ---------------------------------------------------------------------------
// Output formatting
// ---------------------------------------------------------------------------

function formatDate(d: Date): string {
  return d.toLocaleString("en-US", {
    weekday: "short",
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function snippet(content: string, lines: number): string {
  return content
    .split("\n")
    .filter((l) => l.trim().length > 0)
    .slice(0, lines)
    .join("\n");
}

function availableDateRange(entries: TranscriptEntry[]): string {
  if (entries.length === 0) return "no transcripts found";
  const oldest = entries[entries.length - 1];
  const newest = entries[0];
  if (oldest === newest) return formatDate(newest.date);
  return `${formatDate(oldest.date)} → ${formatDate(newest.date)}`;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  const query = process.argv.slice(2).join(" ").trim() || "latest";

  // Parse time query
  let range: DateRange | null;
  try {
    range = parseTimeQuery(query);
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    process.exit(1);
  }

  // Load all transcripts
  const entries = loadTranscripts();

  if (entries.length === 0) {
    console.error(`No transcripts found in ${TRANSCRIPTS_DIR}`);
    console.error("Run the meeting transcriber to generate transcripts first.");
    process.exit(1);
  }

  // Match
  const matches = matchTranscripts(entries, range);

  if (matches.length === 0) {
    const rangeDesc = range
      ? `${formatDate(range.start)} – ${formatDate(range.end)}`
      : "latest";
    console.error(`No transcripts found for: ${query} (searched: ${rangeDesc})`);
    console.error(`Available range: ${availableDateRange(entries)}`);
    console.error(`Try: latest, today, yesterday, a weekday name, or YYYY-MM-DD`);
    process.exit(1);
  }

  if (matches.length === 1) {
    // Single match — print full content
    const entry = matches[0];
    let content: string;
    try {
      content = readFileSync(entry.path, "utf8");
    } catch (err) {
      console.error(`Could not read ${entry.path}: ${err}`);
      process.exit(1);
    }
    console.log(`# ${entry.filename}\n# ${formatDate(entry.date)}\n`);
    console.log(content);
    return;
  }

  // Multiple matches — list with snippets
  console.log(`Found ${matches.length} transcripts matching "${query}":\n`);
  for (const entry of matches) {
    let content = "";
    try {
      content = readFileSync(entry.path, "utf8");
    } catch {
      // skip unreadable
    }
    const preview = snippet(content, SNIPPET_LINES);
    console.log(`## ${entry.filename}`);
    console.log(`   ${formatDate(entry.date)}`);
    if (preview) {
      console.log(`   ${preview.split("\n").join("\n   ")}`);
    }
    console.log();
  }

  console.log(
    `To read a specific transcript, run:\n  bun plugins/meeting-transcripts/transcripts.ts <YYYY-MM-DD>`,
  );
}

main();
