/**
 * Detect when the microphone is activated by another app on macOS.
 *
 * Uses a compiled CoreAudio helper (mic-check) that queries
 * kAudioDevicePropertyDeviceIsRunningSomewhere on all input devices.
 * Returns the active device name, or "inactive" if none.
 */

import { EventEmitter } from "events";

const MIC_CHECK_BIN = process.cwd() + "/src/mic-check";

export interface MicDetector extends EventEmitter {
  on(event: "mic-active", listener: (deviceName: string) => void): this;
  on(event: "mic-inactive", listener: () => void): this;
  on(event: "error", listener: (err: Error) => void): this;
  stop(): void;
}

export function createMicDetector(pollIntervalMs = 2000): MicDetector {
  const emitter = new EventEmitter() as MicDetector;
  let wasActive = false;
  let timer: ReturnType<typeof setInterval> | null = null;
  let stopped = false;

  async function checkMic(): Promise<string | null> {
    const proc = Bun.spawn([MIC_CHECK_BIN], {
      stdout: "pipe",
      stderr: "ignore",
    });
    const output = (await new Response(proc.stdout).text()).trim();
    const exitCode = await proc.exited;

    if (exitCode !== 0) {
      throw new Error(`mic-check exited with code ${exitCode}`);
    }

    return output === "inactive" ? null : output;
  }

  async function poll() {
    if (stopped) return;
    try {
      const deviceName = await checkMic();
      if (deviceName && !wasActive) {
        wasActive = true;
        emitter.emit("mic-active", deviceName);
      } else if (!deviceName && wasActive) {
        wasActive = false;
        emitter.emit("mic-inactive");
      }
    } catch (err) {
      emitter.emit(
        "error",
        err instanceof Error ? err : new Error(String(err)),
      );
    }
  }

  timer = setInterval(poll, pollIntervalMs);
  poll();

  emitter.stop = () => {
    stopped = true;
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  };

  return emitter;
}
