# Meeting Transcriber

Record meetings, transcribe them, and make transcripts available to Claude Code.

## Architecture

- **Runtime**: Bun (TypeScript)
- **Mic detection**: CoreAudio helper (`mic-check.swift`, compiled via `swiftc`)
- **Recording UI**: Menu bar indicator (`rec-status.swift`, compiled via `swiftc`)
- **Notifications**: `terminal-notifier` (install via `brew install terminal-notifier`)
- **Audio recording**: ffmpeg (spawned as child process)
- **System audio capture**: BlackHole virtual audio driver
- **Transcription**: whisper.cpp CLI or OpenAI Whisper API
- **Output**: Plain text files in `transcripts/` directory
- **No database** - everything is file-based

## Phases

### Phase 1: Detect + Record Mic (done)
- [x] Detect when microphone is activated by another app (CoreAudio polling via mic-check)
- [x] Auto-record when detected
- [x] Record mic audio (you) to `recordings/` as WAV via ffmpeg
- [x] Menu bar "● REC" indicator to stop recording
- [x] Notifications on start/stop via terminal-notifier
- [x] Clean shutdown (Ctrl+C, SIGTERM, menu bar click)

### Phase 2: Speaker Recording
- [ ] Set up BlackHole for system audio capture
- [ ] Record system audio (them) as separate WAV simultaneously
- [ ] Two files per session: `mic_<timestamp>.wav` + `speaker_<timestamp>.wav`

### Phase 3: Transcribe
- [ ] Transcribe each audio file via whisper.cpp or Whisper API
- [ ] Output per-file transcript with timestamps

### Phase 4: Merge
- [ ] Interleave mic and speaker transcripts by timestamp
- [ ] Label as `You:` and `Them:`
- [ ] Write final transcript to `transcripts/<timestamp>.md`

### Phase 5: Claude Code Integration
- [ ] Claude Code skill to read/summarize latest transcript
- [ ] Configurable project directory

## File Structure

```
meeting-transcriber/
├── plan.md
├── package.json
├── tsconfig.json
├── src/
│   ├── index.ts           # Main orchestrator
│   ├── detect.ts          # Mic activation detection (polls mic-check)
│   ├── record.ts          # Audio recording via ffmpeg
│   ├── mic-check.swift    # CoreAudio binary: reports active input device
│   ├── rec-status.swift   # Menu bar "● REC" indicator
│   ├── transcribe.ts      # Whisper transcription (Phase 3)
│   └── merge.ts           # Interleave + label transcripts (Phase 4)
├── recordings/            # Raw WAV files
└── transcripts/           # Final labeled transcripts
```
