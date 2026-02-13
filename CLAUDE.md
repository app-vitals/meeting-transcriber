# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `bun run build` — compile Swift helpers and standalone binary
- `bun run start` — run the compiled meeting-transcriber binary
- `./install.sh` — build, install as LaunchAgent (auto-start on login)
- `./uninstall.sh` — stop and remove LaunchAgent
- `bun test` — run tests

Use Bun, not Node.js. Use `Bun.file`, `Bun.spawn`, `Bun.write` over Node equivalents.

## Architecture

macOS-only meeting transcription pipeline: detect mic activation → record dual audio → transcribe → merge.

**Flow:**
1. `index.ts` orchestrates everything. On startup, checks for BlackHole 2ch and downloads the whisper model if needed.
2. `detect.ts` polls `mic-check` (compiled Swift binary) every 2s via CoreAudio to detect when a meeting app activates a microphone.
3. On mic activation, `record.ts` starts two SoX `rec` processes — one for the default mic (you), one for BlackHole 2ch (other participants). Both output 16kHz mono 16-bit WAV.
4. `rec-status.swift` shows a red "REC" menu bar indicator. Clicking it stops recording.
5. On stop, `transcribe.ts` runs `whisper-cli` (whisper.cpp) on both WAV files in parallel, parsing JSON output into timestamped segments.
6. `merge.ts` interleaves segments by time, filters speaker bleed from the mic recording using word-overlap similarity, labels as You/Them, writes markdown to `transcripts/`.

**Key design decisions:**
- SoX for recording (not ffmpeg) — ffmpeg's avfoundation layer produces clicks/pops with virtual audio devices like BlackHole
- SoX can't address input-only devices by name on macOS, so mic uses system default input
- Speaker bleed dedup happens at the text level after transcription, not in audio processing
- Swift helpers are minimal single-file CLIs compiled with `swiftc`, no Xcode project needed
- `bun build --compile` produces a standalone `meeting-transcriber` binary — needed so macOS grants mic permissions to it directly
- All file paths use `process.cwd()` (not `import.meta.dir`) for compatibility with the compiled binary

## Prerequisites

`brew install blackhole-2ch sox whisper-cpp terminal-notifier` plus a Multi-Output Device in Audio MIDI Setup (speakers + BlackHole 2ch).
