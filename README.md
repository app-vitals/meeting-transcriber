# meeting-transcriber

Auto-records and transcribes meetings on macOS. Detects when a meeting app activates your microphone, records both your voice and other participants' audio, then transcribes with speaker labels.

## How it works

1. Polls CoreAudio for microphone activation (e.g. Zoom, Meet, FaceTime)
2. Records two audio streams simultaneously:
   - **Mic** — your voice via the system default input (SoX)
   - **Speaker** — other participants via BlackHole 2ch virtual audio (SoX)
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
# Meeting Transcript — 2026-02-13 19:25

[00:00] **You:** Hello, can you hear me?
[00:02] **Them:** Yes, I can hear you clearly.
[00:05] **You:** Great, let's get started.
```

## Prerequisites

```bash
brew install blackhole-2ch sox whisper-cpp terminal-notifier
```

Then set up the Multi-Output Device:

1. Open **Audio MIDI Setup** → "+" → **Create Multi-Output Device**
2. Check both your speakers and **BlackHole 2ch**
3. Set **Multi-Output Device** as system output in System Settings > Sound

## Install and run

```bash
bun install
bun run build   # compile Swift helpers
bun run start   # watch for mic activation
```

The whisper model (~1.5GB) downloads automatically on first transcription.

## Menu bar

A red **REC** indicator appears in the menu bar during recording. Click it to stop.
