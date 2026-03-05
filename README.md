# meeting-transcriber

Auto-records and transcribes meetings on macOS. Detects when a meeting app activates your microphone, records both your voice and other participants' audio, then transcribes with speaker labels.

## How it works

1. Polls CoreAudio for microphone activation (e.g. Zoom, Meet, FaceTime)
2. Records two audio streams simultaneously:
   - **Mic** — your voice via the system default input (SoX)
   - **Speaker** — other participants via ScreenCaptureKit (macOS 13+) or BlackHole 2ch (macOS 12 fallback)
3. On stop, transcribes both with whisper.cpp (large-v3-turbo model)
4. Merges into a single timeline, deduping speaker bleed from the mic

## Output

```
recordings/
  mic_2026-02-13T19-25-11.wav
  speaker_2026-02-13T19-25-11.wav

transcripts/
  2026-02-13T19-25-11.md
```

Transcripts look like:

```markdown
# Meeting Transcript — 2026-02-13 19:25 (5:32)

**You:** Hello, can you hear me?

**Them:** Yes, I can hear you clearly.

**You:** Great, let's get started.
```

## Prerequisites

```bash
brew install sox whisper-cpp terminal-notifier
```

### System audio (macOS 13+)

On macOS 13 (Ventura) and later, speaker audio is captured via **ScreenCaptureKit** — no extra software needed. Grant **Screen Recording** permission when prompted on first launch.

### System audio (macOS 12 fallback)

On macOS 12, install BlackHole and set up a Multi-Output Device manually:

```bash
brew install blackhole-2ch
```

1. Open **Audio MIDI Setup** → "+" → **Create Multi-Output Device**
2. Check both your speakers and **BlackHole 2ch**
3. Set **Multi-Output Device** as system output in System Settings > Sound

## Install

### DMG (recommended — no terminal required)

1. Download the latest **MeetingTranscriber.dmg** from [GitHub Releases](https://github.com/openclaw-ai/meeting-transcriber/releases/latest)
2. Open the DMG and drag **Meeting Transcriber** to your Applications folder
3. Launch it — the app lives in your menu bar
4. Follow the onboarding flow to grant **Microphone** and **Screen Recording** permissions

Then install runtime dependencies once:

```bash
brew install sox whisper-cpp
```

### CLI power-user install (after DMG install)

After dragging the app to Applications, install the `mt` command from the menu bar:

**Menu bar → ● REC → Install mt CLI…**

This symlinks `~/.local/bin/mt` to the `mt` wrapper inside the app bundle. Make sure `~/.local/bin` is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"   # add to ~/.zshrc
```

After that, all `mt` subcommands work from any terminal:

```bash
mt list              # list recent transcripts
mt watch             # start the daemon manually
```

Reinstalling the app from a new DMG does not break the symlink — the target path (`Contents/Resources/mt`) stays stable across updates.

To remove the CLI command, use **Menu bar → ● REC → Remove mt CLI**, or run:

```bash
rm ~/.local/bin/mt
```

### Build from source (GUI app)

Build and launch the menu bar app:

```bash
bun run build
open MeetingTranscriberApp
```

Auto-start on login is managed natively via **SMAppService** — the app registers itself during onboarding and appears in **System Settings → General → Login Items**. Toggle it on/off any time from the menu bar → **Settings…**.

### CLI / headless (no GUI — legacy)

```bash
./install.sh
```

This checks prerequisites, compiles Swift helpers and a standalone binary, installs a LaunchAgent (auto-starts on login via plist), and symlinks the binary to `~/.local/bin/mt`.

> **Note:** `install.sh` / `uninstall.sh` use the legacy LaunchAgent approach. For GUI app users, SMAppService handles auto-start — no manual install step is needed. Use this only for headless / server installs without the menu bar app.

To uninstall the LaunchAgent:

```bash
./uninstall.sh
```

## CLI

After install (via DMG + "Install mt CLI…" menu item, or `./install.sh`), `mt` is available in your PATH:

```bash
mt list              # 10 most recent transcripts (default)
mt list today        # today's transcripts
mt list week         # last 7 days
mt list 3            # last 3 days
mt list 2026-02-13   # single date
mt list 2026-02-13 2026-02-14  # date range
mt list all          # everything
```

### Manual run

```bash
bun install
bun run build   # compile Swift helpers + standalone binary
bun run start   # run meeting-transcriber watch
```

The whisper model (~1.5GB) and Silero VAD model (~1MB) download automatically on first transcription.

## Iterating on the merge algorithm

Two scripts for developing `src/merge.ts` without re-running whisper:

```bash
# Transcribe WAVs, cache segments, show merge preview (one session or all)
bun scripts/eval-merge.ts [timestamp]
bun scripts/eval-merge.ts --retranscribe [timestamp]  # force re-transcription

# Batch re-run merge from cache and overwrite transcripts/ (fast, no whisper)
bun scripts/remerge.ts
```

The production pipeline automatically saves mic and speaker segments to `eval-cache/` after each transcription, so `remerge.ts` covers all sessions — even after WAV files are deleted (auto-deleted after 30 days). When changing merge logic only, use `remerge.ts`. When changing transcription options (e.g. VAD settings), use `eval-merge.ts --retranscribe`.

## Menu bar

A **REC** indicator lives in the menu bar at all times:

- **Gray REC** — idle. Click to start recording manually (useful when no meeting app is open).
- **Red REC** — recording. Click to stop and trigger transcription.
