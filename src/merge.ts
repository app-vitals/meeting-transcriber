/**
 * Merge mic and speaker transcripts into a labeled conversation.
 *
 * The mic records everything (user voice + speaker bleed). The speaker
 * recording captures only the other participants. We flatten both into
 * plain text, then walk the mic text looking for runs that match the
 * speaker text: match = Them, no match = You.
 */

import { join } from "path";
import { mkdirSync } from "fs";
import type { Segment } from "./transcribe.ts";

const TRANSCRIPTS_DIR = join(process.cwd(), "transcripts");

/**
 * Normalize text for comparison: lowercase, replace hyphens with spaces,
 * strip punctuation, collapse whitespace, and remove filler words.
 * Hyphens become spaces so "end-to-end" matches "end to end".
 * Fillers ("uh", "um") are stripped so mic and speaker transcriptions
 * of the same speech match even when whisper inserts fillers differently.
 */
const FILLERS = new Set(["uh", "um"]);

function normalize(text: string): string {
  return text
    .toLowerCase()
    .replace(/-/g, " ")
    .replace(/[^\w\s]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .split(" ")
    .filter((w) => w && !FILLERS.has(w))
    .join(" ");
}

/**
 * Return true if the speaker channel captured no real speech.
 * With VAD-filtered transcription, this is simply a zero-segment check.
 */
function isSpeakerDead(segments: Segment[]): boolean {
  return segments.length === 0;
}

/**
 * Remove mic hallucinations: whisper sometimes repeats an 8+ word phrase
 * multiple times in a row when the mic input is silence or very quiet.
 * Detect any 8-gram that appears 3+ times within a 120-word window and
 * remove all words from the first repeat onward, up to the end of the loop.
 */
function removeMicHallucinations(words: string[]): string[] {
  const NGRAM = 8;
  const MIN_REPEATS = 3;
  const WINDOW = 120;

  let i = 0;
  const result: string[] = [];

  while (i < words.length) {
    // Look ahead for a repeated NGRAM starting at position i
    if (i + NGRAM <= words.length) {
      const candidate = words.slice(i, i + NGRAM).join(" ");
      let count = 1;
      let j = i + NGRAM;
      // Count overlapping occurrences within WINDOW words
      while (j + NGRAM <= Math.min(i + WINDOW, words.length)) {
        if (words.slice(j, j + NGRAM).join(" ") === candidate) {
          count++;
          j += NGRAM;
        } else {
          j++;
        }
      }
      if (count >= MIN_REPEATS) {
        // Skip all words up through the last occurrence of this repeated phrase
        i = j;
        continue;
      }
    }
    result.push(words[i]);
    i++;
  }

  return result;
}

/** Minimum consecutive word match to count as speaker text. */
const RUN_LENGTH = 5;

type Run = { speaker: "You" | "Them"; text: string };

/**
 * Walk mic words and label each as You or Them by checking for RUN_LENGTH-word
 * consecutive runs in the speaker text. Returns labeled runs of text.
 */
function labelWords(micWords: string[], speakerText: string): Run[] {
  if (micWords.length === 0) return [];

  const isThem = new Array(micWords.length).fill(false);

  // Mark words that are part of a matching run
  for (let i = 0; i <= micWords.length - RUN_LENGTH; i++) {
    const run = micWords.slice(i, i + RUN_LENGTH).join(" ");
    if (speakerText.includes(run)) {
      for (let j = i; j < i + RUN_LENGTH; j++) {
        isThem[j] = true;
      }
    }
  }

  // Group consecutive words with the same label into runs
  const runs: Run[] = [];
  let currentSpeaker: "You" | "Them" = isThem[0] ? "Them" : "You";
  let currentWords: string[] = [];

  for (let i = 0; i < micWords.length; i++) {
    const speaker = isThem[i] ? "Them" : "You";
    if (speaker !== currentSpeaker) {
      if (currentWords.length > 0) {
        runs.push({ speaker: currentSpeaker, text: currentWords.join(" ") });
      }
      currentSpeaker = speaker;
      currentWords = [];
    }
    currentWords.push(micWords[i]);
  }
  if (currentWords.length > 0) {
    runs.push({ speaker: currentSpeaker, text: currentWords.join(" ") });
  }

  // Absorb short You gaps between Them runs caused by transcription
  // differences, backchannels, or sentence completions.
  //
  // A "You" run of ≤ MIN_GAP_WORDS sandwiched between two Them runs is
  // almost certainly noise: a misattributed word, a backchannel ("yeah",
  // "okay"), or a whisper transcription difference — not a real speaker
  // change. Absorb it unconditionally into the preceding Them run.
  const MIN_GAP_WORDS = 7;

  const merged: Run[] = [runs[0]];
  for (let i = 1; i < runs.length; i++) {
    const prev = merged[merged.length - 1];
    const curr = runs[i];
    const next = runs[i + 1];

    if (next && curr.speaker === "You" && prev.speaker === "Them" && next.speaker === "Them") {
      const youWordCount = curr.text.split(" ").filter((w) => w).length;
      if (youWordCount <= MIN_GAP_WORDS) {
        prev.text += " " + curr.text;
      } else {
        merged.push(curr);
      }
    } else {
      merged.push(curr);
    }
  }

  // Merge consecutive same-speaker runs created by absorption
  const final: Run[] = [merged[0]];
  for (let i = 1; i < merged.length; i++) {
    const prev = final[final.length - 1];
    if (merged[i].speaker === prev.speaker) {
      prev.text += " " + merged[i].text;
    } else {
      final.push(merged[i]);
    }
  }

  return final;
}

/** Format duration in seconds as Xm Ys. */
function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  if (m === 0) return `${s}s`;
  return `${m}m ${s}s`;
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

  const speakerDead = isSpeakerDead(speakerSegments);

  const micText = micSegments.map((s) => s.text).join(" ").trim();
  const micWords = removeMicHallucinations(micText.split(/\s+/));

  // Calculate total duration
  const lastSeg = micSegments[micSegments.length - 1];
  const duration = lastSeg ? lastSeg.end : 0;

  // Format timestamp for display: 2026-02-13T19-25-11 → 2026-02-13 19:25
  const displayDate = sessionTimestamp
    .replace("T", " ")
    .replace(/-(\d{2})-(\d{2})$/, ":$1");

  let md = `# Meeting Transcript — ${displayDate} (${formatDuration(duration)})\n\n`;

  if (speakerDead) {
    // No speaker audio captured — can't diarize, output raw transcript
    md += `*[Speaker separation unavailable — only mic audio captured]*\n\n`;
    md += micWords.join(" ") + "\n";
  } else {
    const normalizedMicWords = normalize(micWords.join(" ")).split(" ");
    const speakerText = normalize(speakerSegments.map((s) => s.text).join(" "));

    const runs = labelWords(normalizedMicWords, speakerText);

    // Map normalized runs back to original-case words
    let wordIndex = 0;
    const labeledRuns = runs.map((run) => {
      const count = run.text.split(" ").length;
      const original = micWords.slice(wordIndex, wordIndex + count).join(" ");
      wordIndex += count;
      return { speaker: run.speaker, text: original };
    });

    for (const run of labeledRuns) {
      md += `**${run.speaker}:** ${run.text}\n\n`;
    }
  }

  const filePath = join(TRANSCRIPTS_DIR, `${sessionTimestamp}.md`);
  await Bun.write(filePath, md);
  return filePath;
}
