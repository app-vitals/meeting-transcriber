/**
 * Record audio from the microphone using ffmpeg.
 *
 * Captures from a specific macOS audio input device by name via AVFoundation.
 * Outputs WAV files to the recordings/ directory.
 */

import { spawn } from "child_process";
import { join } from "path";
import { mkdirSync } from "fs";

const RECORDINGS_DIR = join(import.meta.dir, "..", "recordings");

export interface Recording {
  /** Path to the WAV file being recorded */
  filePath: string;
  /** Timestamp when recording started */
  startedAt: Date;
  /** Stop recording and return the file path */
  stop(): Promise<string>;
}

/**
 * Start recording from a specific microphone by name.
 * ffmpeg avfoundation accepts device names directly.
 */
export function startMicRecording(deviceName: string): Recording {
  mkdirSync(RECORDINGS_DIR, { recursive: true });

  const now = new Date();
  const timestamp = now.toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const filePath = join(RECORDINGS_DIR, `mic_${timestamp}.wav`);

  const ffmpegProc = spawn(
    "ffmpeg",
    [
      "-f", "avfoundation",
      "-i", `:${deviceName}`,
      "-ac", "1",           // mono
      "-ar", "16000",       // 16kHz (good for speech, matches whisper expectations)
      "-acodec", "pcm_s16le",
      "-y",                 // overwrite if exists
      filePath,
    ],
    {
      stdio: ["pipe", "ignore", "pipe"],
    },
  );

  let stderrOutput = "";
  ffmpegProc.stderr?.on("data", (chunk: Buffer) => {
    stderrOutput += chunk.toString();
  });

  const recording: Recording = {
    filePath,
    startedAt: now,
    stop: () => {
      return new Promise<string>((resolve, reject) => {
        ffmpegProc.on("close", (code) => {
          if (code === 0 || code === 255) {
            // 255 is normal for ffmpeg when stopped via 'q'
            resolve(filePath);
          } else {
            reject(
              new Error(
                `ffmpeg exited with code ${code}\n${stderrOutput.slice(-500)}`,
              ),
            );
          }
        });

        ffmpegProc.on("error", reject);

        // Send 'q' to ffmpeg stdin to gracefully stop recording
        // This ensures the WAV header is written correctly
        ffmpegProc.stdin?.write("q");
        ffmpegProc.stdin?.end();
      });
    },
  };

  return recording;
}
