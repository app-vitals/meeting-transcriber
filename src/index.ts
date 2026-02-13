/**
 * Meeting Transcriber - Main entry point
 *
 * CLI: mt list [filter] | mt watch | mt --help
 * Daemon (mt watch): detect mic activation → record → transcribe → merge
 */

import { realpathSync } from "fs";
import { dirname, join } from "path";
import { listTranscripts } from "./list.ts";

// CLI subcommands — run and exit before starting the daemon
const repoDir = dirname(realpathSync(process.execPath));
const subcommand = process.argv[2];

if (subcommand === "list") {
  listTranscripts(join(repoDir, "transcripts"), process.argv.slice(3));
  process.exit(0);
} else if (subcommand === "watch" && (process.argv[3] === "--help" || process.argv[3] === "-h")) {
  console.log("Usage: mt watch\n");
  console.log("Start the meeting transcriber daemon. Detects mic activation,");
  console.log("records dual audio (mic + speaker), transcribes, and merges.");
  console.log("Normally runs automatically via LaunchAgent after install.");
  process.exit(0);
} else if (subcommand !== "watch") {
  console.log("Usage: mt <command>\n");
  console.log("Commands:");
  console.log("  list [filter]  List transcripts (default: 10 most recent)");
  console.log("  watch          Start daemon (detect mic, auto-record)\n");
  console.log("Run mt <command> --help for details.");
  process.exit(subcommand === "help" || subcommand === "--help" ? 0 : 1);
}

import { createMicDetector } from "./detect.ts";
import { startMicRecording, startSpeakerRecording, makeSessionTimestamp, type Recording } from "./record.ts";
import { ensureModel, transcribe } from "./transcribe.ts";
import { mergeTranscripts } from "./merge.ts";

function notify(title: string, message: string) {
  Bun.spawn(["terminal-notifier", "-title", title, "-message", message]);
}

let recStatus: {
  proc: ReturnType<typeof Bun.spawn>;
  stdin: Bun.FileSink;
} | null = null;

function spawnRecStatus(onStop: () => void) {
  const proc = Bun.spawn([process.cwd() + "/src/rec-status"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "ignore",
  });

  // Listen for "stop" messages from clicks
  const reader = proc.stdout.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  (async () => {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop()!;
      for (const line of lines) {
        if (line.trim() === "stop") onStop();
      }
    }
  })();

  recStatus = { proc, stdin: proc.stdin };
}

function sendRecStatus(command: "record" | "idle") {
  if (!recStatus) return;
  recStatus.stdin.write(command + "\n");
  recStatus.stdin.flush();
}

function killRecStatus() {
  if (!recStatus) return;
  recStatus.proc.kill();
  recStatus = null;
}

function formatDuration(ms: number): string {
  const secs = Math.floor(ms / 1000);
  const mins = Math.floor(secs / 60);
  const remainingSecs = secs % 60;
  return mins > 0 ? `${mins}m ${remainingSecs}s` : `${remainingSecs}s`;
}

interface Session {
  mic: Recording;
  speaker: Recording;
  sessionTimestamp: string;
  startedAt: Date;
}

async function stopSession(session: Session): Promise<void> {
  const duration = Date.now() - session.startedAt.getTime();
  console.log(`[record] Stopping recordings... (${formatDuration(duration)})`);

  const results = await Promise.allSettled([session.mic.stop(), session.speaker.stop()]);

  for (const result of results) {
    if (result.status === "fulfilled") {
      console.log(`[record] Saved: ${result.value}`);
    } else {
      console.error("[record] Error stopping recording:", result.reason);
    }
  }

  notify("Meeting Transcriber", `Recording saved (${formatDuration(duration)})`);

  // Transcribe both recordings in parallel, then merge
  try {
    console.log("[transcribe] Transcribing...");
    const [micSegments, speakerSegments] = await Promise.all([
      transcribe(session.mic.filePath),
      transcribe(session.speaker.filePath),
    ]);
    console.log(`[transcribe] Mic: ${micSegments.length} segments, Speaker: ${speakerSegments.length} segments`);

    const transcriptPath = await mergeTranscripts(micSegments, speakerSegments, session.sessionTimestamp);
    console.log(`[transcribe] Saved: ${transcriptPath}`);
    notify("Meeting Transcriber", "Transcript ready");
  } catch (err) {
    console.error("[transcribe] Error:", err);
  }
}

/** Check that BlackHole 2ch is installed and visible as an audio device. */
async function checkBlackHole(): Promise<boolean> {
  const proc = Bun.spawn(["system_profiler", "SPAudioDataType"], {
    stdout: "pipe",
    stderr: "ignore",
  });
  const output = await new Response(proc.stdout).text();
  return output.includes("BlackHole 2ch");
}

// --- Main ---

const blackHoleAvailable = await checkBlackHole();
if (!blackHoleAvailable) {
  console.error("BlackHole 2ch not found. Speaker recording requires it.\n");
  console.error("Setup instructions:");
  console.error("  1. brew install blackhole-2ch");
  console.error("  2. Open Audio MIDI Setup → '+' → Create Multi-Output Device");
  console.error("     → check both your speakers and 'BlackHole 2ch'");
  console.error("  3. Set Multi-Output Device as system output in System Settings > Sound");
  process.exit(1);
}

console.log("BlackHole 2ch detected. Speaker recording enabled.");

await ensureModel();

spawnRecStatus(() => finishRecording());

console.log("Watching for microphone activation...");
console.log("Press Ctrl+C to exit.\n");

let currentSession: Session | null = null;
let shuttingDown = false;

const detector = createMicDetector(2000);

async function finishRecording() {
  if (!currentSession) return;
  const session = currentSession;
  currentSession = null;
  sendRecStatus("idle");
  await stopSession(session);
}

detector.on("mic-active", async (deviceName: string) => {
  if (currentSession || shuttingDown) return;

  console.log(`[detect] Microphone activated: ${deviceName}`);

  const sessionTimestamp = makeSessionTimestamp();
  const mic = startMicRecording(sessionTimestamp);
  const speaker = startSpeakerRecording(sessionTimestamp);
  const startedAt = new Date();

  currentSession = { mic, speaker, sessionTimestamp, startedAt };
  console.log(`[record] Mic recording: ${mic.filePath}`);
  console.log(`[record] Speaker recording: ${speaker.filePath}`);
  notify("Meeting Transcriber", "Recording started (mic + speaker)");

  sendRecStatus("record");
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
  killRecStatus();
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
