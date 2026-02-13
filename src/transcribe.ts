/**
 * Transcribe audio files using whisper.cpp (whisper-cli).
 *
 * Downloads the model on first run, then transcribes WAV files
 * and returns timestamped segments.
 */

import { join } from "path";
import { existsSync, mkdirSync, unlinkSync } from "fs";
import { tmpdir } from "os";

const MODELS_DIR = join(import.meta.dir, "..", "models");
const MODEL_NAME = "ggml-large-v3-turbo.bin";
const MODEL_PATH = join(MODELS_DIR, MODEL_NAME);
const MODEL_URL = `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}`;

export interface Segment {
  start: number;   // seconds
  end: number;     // seconds
  text: string;
}

/** Download the whisper model if not already cached. */
export async function ensureModel(): Promise<void> {
  if (existsSync(MODEL_PATH)) return;

  console.log(`[transcribe] Downloading model ${MODEL_NAME}...`);
  mkdirSync(MODELS_DIR, { recursive: true });

  const proc = Bun.spawn(
    ["curl", "-L", "--progress-bar", "-o", MODEL_PATH, MODEL_URL],
    { stdout: "inherit", stderr: "inherit" },
  );
  const code = await proc.exited;
  if (code !== 0) {
    throw new Error(`Failed to download model (exit code ${code})`);
  }
  console.log(`[transcribe] Model saved to ${MODEL_PATH}`);
}

/** Transcribe a WAV file and return timestamped segments. */
export async function transcribe(wavPath: string): Promise<Segment[]> {
  const outputBase = join(tmpdir(), `whisper-${Date.now()}`);

  const proc = Bun.spawn(
    [
      "whisper-cli",
      "-m", MODEL_PATH,
      "-f", wavPath,
      "-oj",              // output JSON
      "--no-prints",      // suppress progress output
      "-of", outputBase,  // output file path (without extension)
    ],
    { stdout: "ignore", stderr: "pipe" },
  );

  const stderr = await new Response(proc.stderr).text();
  const code = await proc.exited;

  if (code !== 0) {
    throw new Error(`whisper-cli exited with code ${code}\n${stderr.slice(-500)}`);
  }

  const jsonPath = `${outputBase}.json`;
  const raw = await Bun.file(jsonPath).json();

  try { unlinkSync(jsonPath); } catch {}

  // offsets are in milliseconds
  const segments: Segment[] = raw.transcription.map((seg: any) => ({
    start: seg.offsets.from / 1000,
    end: seg.offsets.to / 1000,
    text: seg.text.trim(),
  }));

  return segments.filter((s) => s.text.length > 0);
}
