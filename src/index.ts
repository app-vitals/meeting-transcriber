/**
 * Meeting Transcriber - Main entry point
 *
 * Watches for microphone activation, auto-records, and provides
 * a menu bar indicator to stop recording.
 *
 * Usage:
 *   bun run src/index.ts   # Watch mode: detect mic, auto-record
 */

import { createMicDetector } from "./detect.ts";
import { startMicRecording, type Recording } from "./record.ts";

function notify(title: string, message: string) {
  Bun.spawn(["terminal-notifier", "-title", title, "-message", message]);
}

function showRecStatus(): { promise: Promise<void>; kill: () => void } {
  const proc = Bun.spawn([import.meta.dir + "/rec-status"], {
    stdout: "pipe",
    stderr: "ignore",
  });
  return {
    promise: new Response(proc.stdout).text().then(() => {}),
    kill: () => proc.kill(),
  };
}

function formatDuration(ms: number): string {
  const secs = Math.floor(ms / 1000);
  const mins = Math.floor(secs / 60);
  const remainingSecs = secs % 60;
  return mins > 0 ? `${mins}m ${remainingSecs}s` : `${remainingSecs}s`;
}

async function stopRecording(recording: Recording): Promise<void> {
  const duration = Date.now() - recording.startedAt.getTime();
  console.log(`[record] Stopping recording... (${formatDuration(duration)})`);
  try {
    const path = await recording.stop();
    console.log(`[record] Saved: ${path}`);
    notify("Meeting Transcriber", `Recording saved (${formatDuration(duration)})`);
  } catch (err) {
    console.error("[record] Error stopping recording:", err);
  }
}

// --- Main ---

console.log("Watching for microphone activation...");
console.log("Press Ctrl+C to exit.\n");

let currentRecording: Recording | null = null;
let currentRecStatus: { promise: Promise<void>; kill: () => void } | null = null;
let shuttingDown = false;

const detector = createMicDetector(2000);

async function finishRecording() {
  if (!currentRecording) return;
  const recording = currentRecording;
  currentRecording = null;
  currentRecStatus?.kill();
  currentRecStatus = null;
  await stopRecording(recording);
}

detector.on("mic-active", async (deviceName: string) => {
  if (currentRecording || shuttingDown) return;

  console.log(`[detect] Microphone activated: ${deviceName}`);

  currentRecording = startMicRecording(deviceName);
  console.log(`[record] Recording started: ${currentRecording.filePath}`);
  notify("Meeting Transcriber", "Recording started");

  currentRecStatus = showRecStatus();
  currentRecStatus.promise.then(() => finishRecording());
});

detector.on("error", (err) => {
  console.error("[detect] Error:", err.message);
});

async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log("\nShutting down...");
  detector.stop();
  await finishRecording();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
