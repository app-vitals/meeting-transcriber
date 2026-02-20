/**
 * Transcribe audio files using whisper.cpp (whisper-cli).
 *
 * Downloads the model on first run, then transcribes WAV files
 * and returns timestamped segments.
 */

import { join } from "path";
import { existsSync, mkdirSync, unlinkSync } from "fs";
import { tmpdir } from "os";

const MODELS_DIR = join(process.cwd(), "models");
const MODEL_NAME = "ggml-large-v3-turbo.bin";
const MODEL_PATH = join(MODELS_DIR, MODEL_NAME);
const MODEL_URL = `https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}`;

const VAD_MODEL_NAME = "ggml-silero-v5.1.2.bin";
const VAD_MODEL_PATH = join(MODELS_DIR, VAD_MODEL_NAME);
const VAD_MODEL_URL = `https://huggingface.co/ggml-org/whisper-vad/resolve/main/${VAD_MODEL_NAME}`;

export interface Segment {
  start: number;   // seconds
  end: number;     // seconds
  text: string;
}

async function downloadModel(name: string, path: string, url: string): Promise<void> {
  console.log(`[transcribe] Downloading ${name}...`);
  mkdirSync(MODELS_DIR, { recursive: true });
  const proc = Bun.spawn(
    ["curl", "-L", "--progress-bar", "-o", path, url],
    { stdout: "inherit", stderr: "inherit" },
  );
  const code = await proc.exited;
  if (code !== 0) throw new Error(`Failed to download ${name} (exit code ${code})`);
  console.log(`[transcribe] Saved to ${path}`);
}

/** Download whisper and VAD models if not already cached. */
export async function ensureModel(): Promise<void> {
  await Promise.all([
    existsSync(MODEL_PATH) || downloadModel(MODEL_NAME, MODEL_PATH, MODEL_URL),
    existsSync(VAD_MODEL_PATH) || downloadModel(VAD_MODEL_NAME, VAD_MODEL_PATH, VAD_MODEL_URL),
  ]);
}

/** Transcribe a WAV file and return timestamped segments. */
export async function transcribe(wavPath: string, { vad = false }: { vad?: boolean } = {}): Promise<Segment[]> {
  const baseName = wavPath.replace(/.*\//, "").replace(/\.wav$/, "");
  const outputBase = join(tmpdir(), `whisper-${baseName}`);

  const args = [
    "whisper-cli",
    "-m", MODEL_PATH,
    "-f", wavPath,
    "-oj",              // output JSON
    "--no-prints",      // suppress progress output
    "-of", outputBase,  // output file path (without extension)
  ];

  if (vad) {
    args.push("--vad", "--vad-model", VAD_MODEL_PATH);
  }

  const proc = Bun.spawn(args, { stdout: "ignore", stderr: "pipe" });

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
