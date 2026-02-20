# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- `bun run build` — compile Swift helpers and standalone binary
- `bun run start` — run the compiled meeting-transcriber binary
- `./install.sh` — build, install as LaunchAgent (auto-start on login), symlink `mt` to `~/.local/bin`
- `./uninstall.sh` — stop and remove LaunchAgent and `mt` symlink
- `bun test` — run tests

Use Bun, not Node.js. Use `Bun.file`, `Bun.spawn`, `Bun.write` over Node equivalents.

## CLI (`mt`)

After install, `mt` is available in PATH via symlink. Subcommands:

- `mt list [filter]` — list transcripts (default: 10 most recent). Filters: `today`, `week`, `all`, `N` (days), `YYYY-MM-DD`, `YYYY-MM-DD YYYY-MM-DD`
- `mt watch` — start the daemon (detect mic, auto-record). The LaunchAgent runs this automatically.
- `mt --help` — show usage

**Important:** `mt` with no args shows help and exits — it does NOT start the daemon. The daemon only runs via `mt watch` (or through the LaunchAgent).

## Architecture

macOS-only meeting transcription pipeline: detect mic activation → record dual audio → transcribe → merge.

**Flow:**
1. `index.ts` orchestrates everything. On startup, checks for BlackHole 2ch and downloads the whisper model if needed.
2. `detect.ts` polls `mic-check` (compiled Swift binary) every 2s via CoreAudio to detect when a meeting app activates a microphone.
3. On mic activation, `record.ts` starts two SoX `rec` processes — one for the default mic (you), one for BlackHole 2ch (other participants). Both output 16kHz mono 16-bit WAV.
4. `rec-status.swift` shows a red "REC" menu bar indicator. Clicking it stops recording.
5. On stop, `transcribe.ts` runs `whisper-cli` (whisper.cpp) on both WAV files in parallel, parsing JSON output into timestamped segments.
6. `merge.ts` flattens both transcripts to plain text, walks the mic text with a 5-word sliding window to find runs matching the speaker text (Them), labels the rest as You, writes markdown to `transcripts/`.

**Key design decisions:**
- SoX for recording (not ffmpeg) — ffmpeg's avfoundation layer produces clicks/pops with virtual audio devices like BlackHole
- SoX can't address input-only devices by name on macOS, so mic uses system default input
- Merge uses the mic recording as the single timeline source (accurate timestamps) and the speaker recording only to identify who's talking (text matching, not timestamps)
- Short unmatched gaps between Them runs are absorbed if the speaker text flows continuously through them (handles whisper transcription differences like "will" vs "we'll")
- Swift helpers are minimal single-file CLIs compiled with `swiftc`, no Xcode project needed
- `bun build --compile` produces a standalone `meeting-transcriber` binary — needed so macOS grants mic permissions to it directly
- All file paths use `process.cwd()` (not `import.meta.dir`) for compatibility with the compiled binary

## Granola Import

`bun scripts/import-granola.ts` — import meeting transcripts from Granola into `transcripts/`. Requires the Granola MCP server (`npx -y mcp-remote https://mcp.granola.ai/mcp`) to have been run at least once to create OAuth tokens in `~/.mcp-auth/`. Idempotent — skips existing files. Rate limited to 1 request/minute with 10 min cooldown.

## Merge Algorithm Dev

Two scripts for iterating on `src/merge.ts` without re-running whisper:

- `bun scripts/eval-merge.ts [timestamp] [--retranscribe]` — transcribe WAVs (cached to `eval-cache/`), show raw segments and merge preview for one or all sessions. Use `--retranscribe` to force re-transcription after changing transcribe options. Speaker channel always uses VAD; mic does not.
- `bun scripts/remerge.ts` — batch re-run the merge algorithm from cached transcriptions and overwrite `transcripts/`. Fast (no whisper). Use this when iterating on merge logic only.

`eval-cache/` is gitignored (28 JSON files, ~speaker+mic segments for each session).

## Prerequisites

`brew install blackhole-2ch sox whisper-cpp terminal-notifier` plus a Multi-Output Device in Audio MIDI Setup (speakers + BlackHole 2ch).
