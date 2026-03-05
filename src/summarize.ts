/**
 * AI-powered meeting summarization via Claude API.
 *
 * Reads the transcript file produced by merge.ts and prepends a
 * structured ## Summary section containing a TL;DR, action items
 * (as checkboxes), and key decisions.
 *
 * Requires ANTHROPIC_API_KEY env var. Fails silently if the key is
 * missing or the API call fails — the raw transcript is always kept.
 */

import Anthropic from "@anthropic-ai/sdk";
import { readFileSync } from "fs";

const DEFAULT_MODEL = "claude-sonnet-4-6";

const SYSTEM_PROMPT = `You are an expert meeting summarizer. Given a meeting transcript, extract the following in JSON format:

{
  "tldr": "A 2-4 sentence paragraph summarizing the main topic and outcome of the meeting.",
  "actionItems": ["Action item 1 (owner if mentioned)", "Action item 2", ...],
  "keyDecisions": ["Decision 1", "Decision 2", ...],
  "participants": ["Name or role 1", "Name or role 2", ...]
}

Rules:
- tldr: concise but complete; include the core topic, key outcome, and any next steps.
- actionItems: specific tasks with clear ownership where possible. Omit vague or implied items.
- keyDecisions: concrete decisions made during the meeting. Omit discussion points that didn't resolve.
- participants: infer names or roles from context clues in the transcript (e.g. "John said", "the PM mentioned"). Use "You" and "Them" if no names are apparent.
- Return ONLY valid JSON — no markdown fences, no explanation.`;

interface SummaryResult {
  tldr: string;
  actionItems: string[];
  keyDecisions: string[];
  participants: string[];
}

function parseSummary(text: string): SummaryResult | null {
  try {
    // Strip markdown code fences if the model adds them despite instructions
    const cleaned = text.replace(/^```(?:json)?\n?/m, "").replace(/```$/m, "").trim();
    const parsed = JSON.parse(cleaned);

    if (typeof parsed.tldr !== "string") return null;
    if (!Array.isArray(parsed.actionItems)) return null;
    if (!Array.isArray(parsed.keyDecisions)) return null;
    if (!Array.isArray(parsed.participants)) return null;

    return {
      tldr: String(parsed.tldr).trim(),
      actionItems: parsed.actionItems.map(String),
      keyDecisions: parsed.keyDecisions.map(String),
      participants: parsed.participants.map(String),
    };
  } catch {
    return null;
  }
}

function formatSummarySection(summary: SummaryResult): string {
  const lines: string[] = ["## Summary", ""];

  lines.push(summary.tldr, "");

  if (summary.actionItems.length > 0) {
    lines.push("### Action Items", "");
    for (const item of summary.actionItems) {
      lines.push(`- [ ] ${item}`);
    }
    lines.push("");
  }

  if (summary.keyDecisions.length > 0) {
    lines.push("### Key Decisions", "");
    for (const decision of summary.keyDecisions) {
      lines.push(`- ${decision}`);
    }
    lines.push("");
  }

  if (summary.participants.length > 0) {
    lines.push(`**Participants:** ${summary.participants.join(", ")}`, "");
  }

  lines.push("---", "");

  return lines.join("\n");
}

/**
 * Generate an AI summary and prepend it to the transcript file.
 * Silently skips if ANTHROPIC_API_KEY is unset or the API call fails.
 */
export async function summarizeTranscript(transcriptPath: string): Promise<void> {
  if (process.env.AI_ENABLED === "0") {
    console.log("[summarize] AI summaries disabled — skipping");
    return;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.warn("[summarize] ANTHROPIC_API_KEY not set — skipping AI summary");
    return;
  }

  let transcriptText: string;
  try {
    transcriptText = readFileSync(transcriptPath, "utf8");
  } catch (err) {
    console.error("[summarize] Could not read transcript file:", err);
    return;
  }

  if (transcriptText.trim().length < 100) {
    console.warn("[summarize] Transcript too short — skipping AI summary");
    return;
  }

  let summary: SummaryResult | null = null;
  try {
    const model = process.env.CLAUDE_MODEL || DEFAULT_MODEL;
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model,
      max_tokens: 1024,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: transcriptText }],
    });

    const usage = response.usage;
    console.log(
      `[summarize] ${model} — input: ${usage.input_tokens} tokens, output: ${usage.output_tokens} tokens`,
    );

    const block = response.content[0];
    if (block?.type !== "text") {
      console.warn("[summarize] Unexpected response type:", block?.type);
      return;
    }

    summary = parseSummary(block.text);
    if (!summary) {
      console.warn("[summarize] Could not parse summary JSON — skipping");
      return;
    }
  } catch (err) {
    console.error("[summarize] API call failed:", err instanceof Error ? err.message : err);
    return;
  }

  const summarySection = formatSummarySection(summary);
  const updated = summarySection + transcriptText;
  await Bun.write(transcriptPath, updated);
  console.log("[summarize] Summary prepended to transcript");
}
