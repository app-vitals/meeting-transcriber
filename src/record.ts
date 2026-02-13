/**
 * Record audio from microphone and speaker using SoX (rec).
 *
 * SoX uses CoreAudio directly, avoiding ffmpeg's avfoundation layer
 * which produces clicks/pops with virtual audio devices like BlackHole.
 *
 * Outputs WAV files to the recordings/ directory.
 */

import { spawn } from "child_process";
import { join } from "path";
import { mkdirSync, readdirSync, unlinkSync, statSync } from "fs";

const RECORDINGS_DIR = join(process.cwd(), "recordings");

export interface Recording {
  /** Path to the WAV file being recorded */
  filePath: string;
  /** Timestamp when recording started */
  startedAt: Date;
  /** Stop recording and return the file path */
  stop(): Promise<string>;
}

/** Create a shared session timestamp for pairing mic + speaker files. */
export function makeSessionTimestamp(): string {
  return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
}

/**
 * Start SoX `rec` capturing from an audio device.
 * @param audiodev - AUDIODEV value to select device, or undefined for system default input
 */
function startRecording(prefix: string, audiodev: string | undefined, sessionTimestamp: string): Recording {
  mkdirSync(RECORDINGS_DIR, { recursive: true });

  const filePath = join(RECORDINGS_DIR, `${prefix}_${sessionTimestamp}.wav`);

  const env = { ...process.env };
  if (audiodev) {
    env.AUDIODEV = audiodev;
  }

  const proc = spawn(
    "rec",
    [
      "-c", "1",
      "-b", "16",
      filePath,
      "rate", "16000",   // downsample to 16kHz (CoreAudio ignores -r flag)
    ],
    {
      env,
      stdio: ["pipe", "ignore", "pipe"],
    },
  );

  let stderrOutput = "";
  proc.stderr?.on("data", (chunk: Buffer) => {
    stderrOutput += chunk.toString();
  });

  const exited = new Promise<number | null>((resolve) => {
    proc.on("close", (code) => resolve(code));
  });

  return {
    filePath,
    startedAt: new Date(),
    stop: async () => {
      proc.kill("SIGINT");
      const code = await exited;
      if (code === 0 || code === null) {
        return filePath;
      }
      throw new Error(
        `rec (sox) exited with code ${code}\n${stderrOutput.slice(-500)}`,
      );
    },
  };
}

/**
 * Start recording from the default system input (microphone).
 */
export function startMicRecording(sessionTimestamp: string): Recording {
  return startRecording("mic", undefined, sessionTimestamp);
}

/**
 * Start recording system/speaker audio from BlackHole 2ch.
 */
export function startSpeakerRecording(sessionTimestamp: string): Recording {
  return startRecording("speaker", "BlackHole 2ch", sessionTimestamp);
}

/**
 * Delete WAV recordings older than maxAgeDays from the recordings directory.
 */
export function cleanOldRecordings(maxAgeDays: number): void {
  const cutoff = Date.now() - maxAgeDays * 24 * 60 * 60 * 1000;
  let files: string[];
  try {
    files = readdirSync(RECORDINGS_DIR);
  } catch {
    return; // directory doesn't exist yet
  }

  for (const file of files) {
    if (!file.endsWith(".wav")) continue;
    // Parse timestamp from filename: mic_YYYY-MM-DDTHH-MM-SS.wav or speaker_...
    const match = file.match(/_(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})\.wav$/);
    if (!match) continue;
    const timestamp = new Date(`${match[1]}T${match[2]}:${match[3]}:${match[4]}`).getTime();
    if (isNaN(timestamp) || timestamp >= cutoff) continue;
    const fullPath = join(RECORDINGS_DIR, file);
    try {
      unlinkSync(fullPath);
      console.log(`[cleanup] Deleted old recording: ${file}`);
    } catch (err) {
      console.error(`[cleanup] Failed to delete ${file}:`, err);
    }
  }
}
