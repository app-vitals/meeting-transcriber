#!/usr/bin/env bun
/**
 * /distill — Structured context extraction from meeting transcripts.
 *
 * Reads the N most recent transcript files, calls the Claude API to extract
 * goals, decisions, action items, and open questions, then writes/updates
 * .distill/{goals,decisions,actions,open-questions}.md.
 *
 * Idempotent: already-processed transcripts are skipped (tracked in
 * .distill/.processed).
 *
 * Usage:
 *   bun plugins/distill/distill.ts [--count N] [--all] [--force]
 *
 * Options:
 *   --count N   Process the N most recent transcripts (default: 5)
 *   --all       Process all transcripts regardless of .processed list
 *   --force     Re-process even transcripts already in .processed list
 */

import Anthropic from "@anthropic-ai/sdk";
import { readFileSync, existsSync, readdirSync } from "fs";
import { join, resolve, basename } from "path";
import { DISTILL_SYSTEM_PROMPT, DISTILL_USER_PREFIX } from "./prompts.ts";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const DEFAULT_COUNT = 5;
const DEFAULT_MODEL = "claude-sonnet-4-6";
const TRANSCRIPTS_DIR = resolve(process.env.HOME ?? "~", "transcripts");
const DISTILL_DIR = resolve(process.cwd(), ".distill");
const PROCESSED_FILE = join(DISTILL_DIR, ".processed");

const OUTPUT_FILES = {
  goals: join(DISTILL_DIR, "goals.md"),
  decisions: join(DISTILL_DIR, "decisions.md"),
  actions: join(DISTILL_DIR, "actions.md"),
  openQuestions: join(DISTILL_DIR, "open-questions.md"),
} as const;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface DistillResult {
  goals: string[];
  decisions: string[];
  actions: string[];
  openQuestions: string[];
}

// ---------------------------------------------------------------------------
// Env / secrets loading
// ---------------------------------------------------------------------------

function loadSecrets(): void {
  const secretsPath = resolve(process.env.HOME ?? "~", ".openclaw/workspace/.secrets.env");
  if (!existsSync(secretsPath)) return;
  try {
    const text = readFileSync(secretsPath, "utf8");
    for (const line of text.split("\n")) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith("#")) continue;
      const eq = trimmed.indexOf("=");
      if (eq === -1) continue;
      const key = trimmed.slice(0, eq).trim();
      const value = trimmed.slice(eq + 1).trim();
      if (!process.env[key]) {
        process.env[key] = value;
      }
    }
  } catch {
    // ignore unreadable secrets
  }
}

function getApiKey(): string {
  // Project uses ANTHROPIC_API_KEY; secrets.env may have CLAUDE_CODE_PI
  const key = process.env.ANTHROPIC_API_KEY ?? process.env.CLAUDE_CODE_PI;
  if (!key) {
    console.error("[distill] ANTHROPIC_API_KEY not set. Set it in env or .secrets.env.");
    process.exit(1);
  }
  return key;
}

// ---------------------------------------------------------------------------
// Transcript discovery
// ---------------------------------------------------------------------------

function findTranscripts(count: number, processAll: boolean): string[] {
  if (!existsSync(TRANSCRIPTS_DIR)) {
    console.warn(`[distill] Transcripts directory not found: ${TRANSCRIPTS_DIR}`);
    return [];
  }

  const files = readdirSync(TRANSCRIPTS_DIR)
    .filter((f) => f.endsWith(".md"))
    .map((f) => ({
      name: f,
      path: join(TRANSCRIPTS_DIR, f),
      mtime: (() => {
        try {
          return Bun.file(join(TRANSCRIPTS_DIR, f)).size; // fallback sort key
        } catch {
          return 0;
        }
      })(),
    }));

  // Sort by filename descending (filenames contain timestamps like YYYY-MM-DD_HH-MM-SS)
  files.sort((a, b) => b.name.localeCompare(a.name));

  const selected = processAll ? files : files.slice(0, count);
  return selected.map((f) => f.path);
}

// ---------------------------------------------------------------------------
// Processed tracking
// ---------------------------------------------------------------------------

function loadProcessed(): Set<string> {
  if (!existsSync(PROCESSED_FILE)) return new Set();
  try {
    return new Set(
      readFileSync(PROCESSED_FILE, "utf8")
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean),
    );
  } catch {
    return new Set();
  }
}

async function markProcessed(filenames: string[]): Promise<void> {
  const existing = loadProcessed();
  for (const f of filenames) existing.add(f);
  await Bun.write(PROCESSED_FILE, [...existing].join("\n") + "\n");
}

// ---------------------------------------------------------------------------
// Claude API
// ---------------------------------------------------------------------------

async function extractContext(transcriptTexts: string[], apiKey: string): Promise<DistillResult> {
  const model = process.env.CLAUDE_MODEL ?? DEFAULT_MODEL;
  const client = new Anthropic({ apiKey });

  const userContent = DISTILL_USER_PREFIX + transcriptTexts.join("\n\n---\n\n");

  const response = await client.messages.create({
    model,
    max_tokens: 2048,
    system: DISTILL_SYSTEM_PROMPT,
    messages: [{ role: "user", content: userContent }],
  });

  const usage = response.usage;
  console.log(
    `[distill] ${model} — input: ${usage.input_tokens} tokens, output: ${usage.output_tokens} tokens`,
  );

  const block = response.content[0];
  if (block?.type !== "text") {
    throw new Error(`Unexpected response type: ${block?.type}`);
  }

  return parseResult(block.text);
}

function parseResult(text: string): DistillResult {
  const cleaned = text.replace(/^```(?:json)?\n?/m, "").replace(/```$/m, "").trim();
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    throw new Error(`Could not parse JSON from API response:\n${cleaned.slice(0, 300)}`);
  }

  if (typeof parsed !== "object" || parsed === null) throw new Error("Expected JSON object");
  const obj = parsed as Record<string, unknown>;

  return {
    goals: toStringArray(obj.goals),
    decisions: toStringArray(obj.decisions),
    actions: toStringArray(obj.actions),
    openQuestions: toStringArray(obj.openQuestions),
  };
}

function toStringArray(val: unknown): string[] {
  if (!Array.isArray(val)) return [];
  return val.map(String).map((s) => s.trim()).filter(Boolean);
}

// ---------------------------------------------------------------------------
// Output file management
// ---------------------------------------------------------------------------

const FILE_HEADERS: Record<keyof typeof OUTPUT_FILES, string> = {
  goals: "# Project Goals\n\n_Goals and objectives extracted from meeting transcripts._\n",
  decisions: "# Decisions\n\n_Concrete decisions made during meetings._\n",
  actions: "# Action Items\n\n_Tasks and next steps from meetings._\n",
  openQuestions: "# Open Questions\n\n_Questions raised but not yet resolved._\n",
};

async function ensureDistillDir(): Promise<void> {
  await Bun.write(join(DISTILL_DIR, ".gitkeep"), "");
}

async function readOutputFile(key: keyof typeof OUTPUT_FILES): Promise<string> {
  const path = OUTPUT_FILES[key];
  if (!existsSync(path)) return "";
  try {
    return await Bun.file(path).text();
  } catch {
    return "";
  }
}

/**
 * Append new items to a .distill/*.md file, skipping duplicates.
 * Items are stored as bullet list entries. Comparison is case-insensitive trim.
 */
async function appendItems(
  key: keyof typeof OUTPUT_FILES,
  items: string[],
  sourceNote: string,
): Promise<number> {
  if (items.length === 0) return 0;

  const existing = await readOutputFile(key);
  const isNew = existing.length === 0;

  // Extract existing bullet text for dedup
  const existingItems = new Set(
    existing
      .split("\n")
      .filter((l) => l.startsWith("- "))
      .map((l) => l.slice(2).trim().toLowerCase()),
  );

  const newItems = items.filter((item) => !existingItems.has(item.toLowerCase()));
  if (newItems.length === 0) return 0;

  const section = [
    `\n<!-- distilled: ${sourceNote} -->\n`,
    ...newItems.map((item) => `- ${item}`),
    "",
  ].join("\n");

  const header = isNew ? FILE_HEADERS[key] : "";
  const updated = (isNew ? header : existing.trimEnd()) + section;
  await Bun.write(OUTPUT_FILES[key], updated);
  return newItems.length;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  loadSecrets();

  // Parse args
  const args = process.argv.slice(2);
  const countIdx = args.indexOf("--count");
  const count = countIdx !== -1 ? parseInt(args[countIdx + 1] ?? String(DEFAULT_COUNT), 10) : DEFAULT_COUNT;
  const processAll = args.includes("--all");
  const force = args.includes("--force");

  const apiKey = getApiKey();
  await ensureDistillDir();

  // Find transcripts
  const allPaths = findTranscripts(count, processAll);
  if (allPaths.length === 0) {
    console.log("[distill] No transcripts found.");
    return;
  }

  // Filter already-processed unless --force
  const processed = loadProcessed();
  const toProcess = force
    ? allPaths
    : allPaths.filter((p) => !processed.has(basename(p)));

  if (toProcess.length === 0) {
    console.log(`[distill] All ${allPaths.length} transcript(s) already processed. Use --force to re-run.`);
    return;
  }

  console.log(`[distill] Processing ${toProcess.length} transcript(s)...`);

  // Read transcript content
  const texts: string[] = [];
  for (const p of toProcess) {
    try {
      const text = readFileSync(p, "utf8");
      if (text.trim().length < 50) {
        console.warn(`[distill] Skipping short/empty transcript: ${basename(p)}`);
        continue;
      }
      texts.push(`## ${basename(p)}\n\n${text}`);
    } catch (err) {
      console.warn(`[distill] Could not read ${basename(p)}: ${err}`);
    }
  }

  if (texts.length === 0) {
    console.log("[distill] No readable transcript content.");
    return;
  }

  // Call Claude
  let result: DistillResult;
  try {
    result = await extractContext(texts, apiKey);
  } catch (err) {
    console.error("[distill] API extraction failed:", err instanceof Error ? err.message : err);
    process.exit(1);
  }

  // Write outputs
  const sourceNote = `${new Date().toISOString().slice(0, 10)} from ${toProcess.map(basename).join(", ")}`;

  const [g, d, a, q] = await Promise.all([
    appendItems("goals", result.goals, sourceNote),
    appendItems("decisions", result.decisions, sourceNote),
    appendItems("actions", result.actions, sourceNote),
    appendItems("openQuestions", result.openQuestions, sourceNote),
  ]);

  // Mark processed
  await markProcessed(toProcess.map(basename));

  console.log(`[distill] Done.`);
  console.log(`  goals: +${g}  decisions: +${d}  actions: +${a}  open questions: +${q}`);
  console.log(`  Output: ${DISTILL_DIR}`);
}

main();
