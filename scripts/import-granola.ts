/**
 * Import all Granola meeting transcripts into the transcripts/ directory.
 *
 * Reads the OAuth token from ~/.mcp-auth and calls the Granola MCP server
 * directly over HTTP (JSON-RPC) to fetch meeting lists and transcripts.
 *
 * Usage: bun scripts/import-granola.ts
 */

import { mkdirSync, readdirSync } from "fs";
import { join } from "path";

const TRANSCRIPTS_DIR = join(process.cwd(), "transcripts");
const MCP_URL = "https://mcp.granola.ai/mcp";
const TOKEN_ENDPOINT = "https://mcp-auth.granola.ai/oauth2/token";
const TOKEN_DIR = join(
  process.env.HOME!,
  ".mcp-auth/mcp-remote-0.1.37",
);

// Find the most recent token file and return its path + contents
function findTokenFile(): { path: string; prefix: string } {
  const files = readdirSync(TOKEN_DIR).filter((f) =>
    f.endsWith("_tokens.json"),
  );
  const sorted = files
    .map((f) => ({
      name: f,
      path: join(TOKEN_DIR, f),
      mtime: Bun.file(join(TOKEN_DIR, f)).lastModified,
    }))
    .sort((a, b) => b.mtime - a.mtime);

  if (sorted.length === 0) {
    throw new Error("No token files found in " + TOKEN_DIR);
  }

  const prefix = sorted[0].name.replace("_tokens.json", "");
  return { path: sorted[0].path, prefix };
}

function loadTokens(path: string): { access_token: string; refresh_token: string } {
  return JSON.parse(require("fs").readFileSync(path, "utf-8"));
}

async function refreshAccessToken(tokenFilePath: string, prefix: string): Promise<string> {
  const tokens = loadTokens(tokenFilePath);
  const clientInfo = JSON.parse(
    require("fs").readFileSync(join(TOKEN_DIR, `${prefix}_client_info.json`), "utf-8"),
  );

  const res = await fetch(TOKEN_ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: tokens.refresh_token,
      client_id: clientInfo.client_id,
    }),
  });

  if (!res.ok) {
    throw new Error(`Token refresh failed: ${res.status} ${await res.text()}`);
  }

  const newTokens = await res.json();
  // Persist refreshed tokens
  await Bun.write(tokenFilePath, JSON.stringify(newTokens, null, 2));
  console.log("Refreshed OAuth token");
  return newTokens.access_token;
}

let requestId = 0;
let currentToken = "";
let tokenFilePath = "";
let tokenPrefix = "";

async function mcpCall(
  method: string,
  params: Record<string, unknown>,
): Promise<unknown> {
  requestId++;
  const res = await fetch(MCP_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${currentToken}`,
      "Content-Type": "application/json",
      Accept: "application/json, text/event-stream",
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: requestId,
      method,
      params,
    }),
  });

  const text = await res.text();

  // Handle expired/invalid token — refresh and retry
  if (text.includes("Session expired") || text.includes("sign in again") || text.includes("Unauthorized")) {
    currentToken = await refreshAccessToken(tokenFilePath, tokenPrefix);
    return mcpCall(method, params);
  }

  // Response is SSE format: "event: message\ndata: {...}"
  const dataLine = text
    .split("\n")
    .find((l) => l.startsWith("data: "));
  if (!dataLine) throw new Error("No data in response: " + text.slice(0, 200));

  const parsed = JSON.parse(dataLine.slice(6));
  if (parsed.error) throw new Error(parsed.error.message);
  return parsed.result;
}

interface Meeting {
  id: string;
  title: string;
  date: string;
}

async function listMeetings(
  timeRange: string,
  customStart?: string,
  customEnd?: string,
): Promise<Meeting[]> {
  const args: Record<string, string> = { time_range: timeRange };
  if (customStart) args.custom_start = customStart;
  if (customEnd) args.custom_end = customEnd;

  const result = (await mcpCall("tools/call", {
    name: "list_meetings",
    arguments: args,
  })) as { content: { text: string }[] };

  const text = result.content[0].text;
  // Parse meeting data from XML-like response
  const meetings: Meeting[] = [];
  const regex =
    /meeting id="([^"]+)" title="([^"]+)" date="([^"]+)"/g;
  let match;
  while ((match = regex.exec(text)) !== null) {
    meetings.push({ id: match[1], title: match[2], date: match[3] });
  }
  return meetings;
}

async function getTranscript(
  meetingId: string,
  retries = 3,
): Promise<{ id: string; title: string; transcript: string } | null> {
  for (let attempt = 0; attempt < retries; attempt++) {
    try {
      const result = (await mcpCall("tools/call", {
        name: "get_meeting_transcript",
        arguments: { meeting_id: meetingId },
      })) as { content: { text: string }[] };

      const text = result.content[0].text;
      if (text.startsWith("Rate")) {
        // Rate limited - wait and retry
        const wait = 600000; // 10 min cooldown on rate limit
        console.error(`  Rate limited, waiting 10 min...`);
        await Bun.sleep(wait);
        continue;
      }
      return JSON.parse(text);
    } catch (err: any) {
      if (err.message?.includes("Rate") || err.message?.includes("429")) {
        const wait = 600000; // 10 min cooldown on rate limit
        console.error(`  Rate limited, waiting 10 min...`);
        await Bun.sleep(wait);
        continue;
      }
      console.error(`  Failed ${meetingId}:`, err.message || err);
      return null;
    }
  }
  console.error(`  Gave up on ${meetingId} after ${retries} retries`);
  return null;
}

function dateToTimestamp(dateStr: string): string {
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return dateStr.replace(/[^a-zA-Z0-9-]/g, "-");
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}-${pad(d.getMinutes())}-${pad(d.getSeconds())}`;
}

function dateToDisplay(dateStr: string): string {
  const d = new Date(dateStr);
  if (isNaN(d.getTime())) return dateStr;
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function convertTranscript(raw: string): string {
  // Raw format: " Me: text  Them: text  Me: text"
  // Split on double-space before speaker markers
  const parts = raw
    .trim()
    .split(/\s{2,}(?=(?:Me|Them):)/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0)
    .map((p) => {
      if (p.startsWith("Me: ")) return `**You:** ${p.slice(4)}`;
      if (p.startsWith("Them: ")) return `**Them:** ${p.slice(6)}`;
      return p;
    });
  return parts.join("\n\n");
}

// --- Main ---

mkdirSync(TRANSCRIPTS_DIR, { recursive: true });

const tokenFile = findTokenFile();
tokenFilePath = tokenFile.path;
tokenPrefix = tokenFile.prefix;
const tokens = loadTokens(tokenFilePath);
currentToken = tokens.access_token;
console.log("Loaded OAuth token");

// Initialize MCP session
await mcpCall("initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "import-granola", version: "1.0" },
});
console.log("MCP session initialized");
await Bun.sleep(1000);

// Fetch all meetings in two ranges
console.log("Fetching meeting lists...");
const recent = await listMeetings("last_30_days");
await Bun.sleep(1000);
const older = await listMeetings("custom", "2024-01-01", "2026-01-19");

// Dedupe by ID
const seen = new Set<string>();
const allMeetings: Meeting[] = [];
for (const m of [...recent, ...older]) {
  if (!seen.has(m.id)) {
    seen.add(m.id);
    allMeetings.push(m);
  }
}

// Sort newest first
allMeetings.sort(
  (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
);

console.log(`Found ${allMeetings.length} meetings`);

// Cooldown before starting transcript fetches
await Bun.sleep(1000);

// Check which transcripts already exist
const existing = new Set(
  readdirSync(TRANSCRIPTS_DIR).filter((f) => f.endsWith(".md")),
);

let written = 0;
let skipped = 0;
let failed = 0;

// Process sequentially with 250ms delay (5 req/s sustained limit)
for (let i = 0; i < allMeetings.length; i++) {
  const meeting = allMeetings[i];
  const timestamp = dateToTimestamp(meeting.date);
  const filename = `${timestamp}.md`;
  const count = written + skipped + failed + 1;

  // Skip if file already exists (from local recording or previous import)
  if (existing.has(filename)) {
    skipped++;
    continue;
  }

  const data = await getTranscript(meeting.id);
  if (!data || !data.transcript) {
    failed++;
    continue;
  }

  const displayDate = dateToDisplay(meeting.date);
  const body = convertTranscript(data.transcript);
  const title = data.title || meeting.title;
  const md = `# ${title} — ${displayDate}\n\n${body}\n`;

  const filePath = join(TRANSCRIPTS_DIR, `${filename}`);
  await Bun.write(filePath, md);
  existing.add(filename);
  written++;
  console.log(`  [${count}/${allMeetings.length}] ${title}`);

  // Granola MCP has strict transcript rate limits — 1 per minute
  await Bun.sleep(60000);
}

console.log(
  `\nDone! Written: ${written}, Skipped (existing): ${skipped}, Failed: ${failed}`,
);
