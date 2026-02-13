import { readdirSync, readFileSync } from "fs";
import { join } from "path";

interface Transcript {
  date: Date;
  duration: string;
  filePath: string;
}

function parseFilename(filename: string): Date | null {
  // 2026-02-13T14-30-00.md → Date (UTC)
  const match = filename.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})\.md$/);
  if (!match) return null;
  const [, y, mo, d, h, mi, s] = match;
  return new Date(Date.UTC(+y, +mo - 1, +d, +h, +mi, +s));
}

function extractDuration(filePath: string): string {
  try {
    const content = readFileSync(filePath, "utf-8");
    const match = content.match(/^# Meeting Transcript — .+ \(([^)]+)\)/m);
    return match ? match[1] : "?";
  } catch {
    return "?";
  }
}

function formatTime(date: Date, timeZone: string): string {
  return date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    timeZone,
    hour12: true,
  });
}

function startOfDayLocal(date: Date): Date {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

function printHelp(): void {
  console.log("Usage: mt list [filter]\n");
  console.log("Show transcripts, newest first. Default: 10 most recent.\n");
  console.log("Filters:");
  console.log("  today              Today's transcripts");
  console.log("  week               Last 7 days");
  console.log("  all                All transcripts");
  console.log("  N                  Last N days (e.g. mt list 3)");
  console.log("  YYYY-MM-DD         Single date");
  console.log("  YYYY-MM-DD YYYY-MM-DD  Date range");
}

export function listTranscripts(transcriptsDir: string, args: string[]): void {
  if (args[0] === "--help" || args[0] === "-h") {
    printHelp();
    return;
  }

  let files: string[];
  try {
    files = readdirSync(transcriptsDir).filter((f) => f.endsWith(".md")).sort();
  } catch {
    console.log("No transcripts found.");
    return;
  }

  const transcripts: Transcript[] = [];
  for (const f of files) {
    const date = parseFilename(f);
    if (!date) continue;
    transcripts.push({
      date,
      duration: extractDuration(join(transcriptsDir, f)),
      filePath: join(transcriptsDir, f),
    });
  }

  if (transcripts.length === 0) {
    console.log("No transcripts found.");
    return;
  }

  // Determine date filter
  const now = new Date();
  let from: Date;
  let to: Date = new Date(now.getTime() + 86400000); // tomorrow (include all of today)

  const arg0 = args[0];
  const arg1 = args[1];
  let limit = 0; // 0 = no limit

  if (!arg0) {
    // Default: 10 most recent
    from = new Date(0);
    limit = 10;
  } else if (arg0 === "today") {
    from = startOfDayLocal(now);
  } else if (arg0 === "week") {
    from = startOfDayLocal(new Date(now.getTime() - 6 * 86400000));
  } else if (arg0 === "all") {
    from = new Date(0);
  } else if (/^\d+$/.test(arg0)) {
    from = startOfDayLocal(new Date(now.getTime() - (+arg0 - 1) * 86400000));
  } else if (/^\d{4}-\d{2}-\d{2}$/.test(arg0)) {
    from = new Date(arg0 + "T00:00:00");
    if (arg1 && /^\d{4}-\d{2}-\d{2}$/.test(arg1)) {
      to = new Date(arg1 + "T23:59:59.999");
    } else {
      to = new Date(arg0 + "T23:59:59.999");
    }
  } else {
    console.log(`Unknown filter: ${arg0}`);
    console.log("Usage: mt list [today | week | all | N days | YYYY-MM-DD [YYYY-MM-DD]]");
    return;
  }

  const filtered = transcripts.filter((t) => t.date >= from && t.date <= to);

  if (filtered.length === 0) {
    console.log("No transcripts found.");
    return;
  }

  const localTz = Intl.DateTimeFormat().resolvedOptions().timeZone;

  // Sort newest first
  filtered.sort((a, b) => b.date.getTime() - a.date.getTime());

  // Apply limit
  const results = limit > 0 ? filtered.slice(0, limit) : filtered;

  for (const t of results) {
    const dateStr = t.date.toLocaleDateString("en-CA", { timeZone: localTz }); // YYYY-MM-DD
    const localTime = formatTime(t.date, localTz);
    const tz = t.date.toLocaleTimeString("en-US", { timeZone: localTz, timeZoneName: "short" }).split(" ").pop();

    console.log(
      `${dateStr}  ${localTime.padStart(8)} (${tz})  ${t.filePath}  (${t.duration})`
    );
  }
}
