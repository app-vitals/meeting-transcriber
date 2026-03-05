/**
 * Record audio from microphone and speaker.
 *
 * macOS 13+: speaker audio is captured via ScreenCaptureKit (system-audio-capture),
 *            requiring only a Screen Recording permission prompt — no BlackHole needed.
 *
 * macOS 12:  falls back to SoX rec + BlackHole 2ch (original behaviour).
 *
 * Mic is always captured via SoX rec against the default system input.
 *
 * Outputs WAV files to the recordings/ directory.
 */

import { spawn } from "child_process";
import { join, dirname } from "path";
import { mkdirSync, readdirSync, unlinkSync, statSync, existsSync } from "fs";
import { fileURLToPath } from "url";
import { homedir } from "os";

const RECORDINGS_DIR = join(homedir(), "recordings");

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

// ---------------------------------------------------------------------------
// macOS version detection
// ---------------------------------------------------------------------------

/** Returns true when running on macOS 13 (Ventura) or later. */
export function isMacOS13OrLater(): boolean {
  try {
    const result = Bun.spawnSync(["sw_vers", "-productVersion"], { stderr: "ignore" });
    const version = new TextDecoder().decode(result.stdout).trim();
    const [major] = version.split(".").map(Number);
    return major >= 13;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// SoX-based recording (mic default, or BlackHole for speaker on macOS 12)
// ---------------------------------------------------------------------------

/**
 * Start SoX `rec` capturing from an audio device.
 * @param audiodev - AUDIODEV value to select device, or undefined for system default input
 */
function startSoxRecording(prefix: string, audiodev: string | undefined, sessionTimestamp: string): Recording {
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

// ---------------------------------------------------------------------------
// ScreenCaptureKit-based speaker recording (macOS 13+)
// ---------------------------------------------------------------------------

/** Path to the compiled system-audio-capture binary (sits next to this source file). */
function systemAudioCaptureBin(): string {
  // In production (bun compiled binary) process.execPath points to the binary itself,
  // whose parent dir is the repo root where `src/system-audio-capture` lives.
  // In dev (bun run src/index.ts) __dirname works too.
  const candidates = [
    join(process.cwd(), "src", "system-audio-capture"),
    join(dirname(fileURLToPath(import.meta.url)), "system-audio-capture"),
  ];
  return candidates.find(existsSync) ?? candidates[0];
}

/**
 * Start recording system audio via ScreenCaptureKit.
 * Requires Screen Recording permission (macOS 13+).
 */
function startSCKitSpeakerRecording(sessionTimestamp: string): Recording {
  mkdirSync(RECORDINGS_DIR, { recursive: true });

  const filePath = join(RECORDINGS_DIR, `speaker_${sessionTimestamp}.wav`);
  const bin = systemAudioCaptureBin();

  const proc = spawn(bin, [filePath], {
    stdio: ["ignore", "ignore", "pipe"],
  });

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
      proc.kill("SIGTERM");
      const code = await exited;
      if (code === 0 || code === null) {
        return filePath;
      }
      throw new Error(
        `system-audio-capture exited with code ${code}\n${stderrOutput.slice(-500)}`,
      );
    },
  };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Start recording from the default system input (microphone).
 */
export function startMicRecording(sessionTimestamp: string): Recording {
  return startSoxRecording("mic", undefined, sessionTimestamp);
}

/**
 * Start recording system/speaker audio.
 *
 * On macOS 13+: uses ScreenCaptureKit (system-audio-capture binary) — no BlackHole needed.
 * On macOS 12:  uses SoX rec via BlackHole 2ch.
 */
export function startSpeakerRecording(sessionTimestamp: string): Recording {
  if (isMacOS13OrLater()) {
    return startSCKitSpeakerRecording(sessionTimestamp);
  }
  return startSoxRecording("speaker", "BlackHole 2ch", sessionTimestamp);
}

// ---------------------------------------------------------------------------
// Cleanup
// ---------------------------------------------------------------------------

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
