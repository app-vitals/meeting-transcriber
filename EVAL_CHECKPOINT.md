# Merge Algorithm Evaluation Checkpoint

## What We Did
1. Built `scripts/eval-merge.ts` and `scripts/remerge.ts` for fast iteration
2. Added VAD (Silero v5.1.2) to speaker channel transcription — major improvement:
   - Eliminated hallucination runs (116×, 155×, 54× repeated phrases)
   - Dead channels now return 0 segments (clean `isSpeakerDead()` check)
   - `src/transcribe.ts` now accepts `{ vad: true }` option
   - `ensureModel()` auto-downloads both whisper + silero models
3. Simplified `merge.ts`: removed `filterHallucinations()` (VAD does this at source)
4. Fixed `normalize()`:
   - Replace hyphens with spaces: "end-to-end" → "end to end"
   - Strip filler words "uh", "um" before matching — fixes cases where mic and
     speaker transcribe the same speech with different filler positions
5. Changed gap absorption: replaced anchor-based approach with `MIN_GAP_WORDS = 7`
6. Added dead-channel path: outputs unlabeled mic text with note

## Current merge.ts Changes (vs original)
- `normalize()`: hyphens→spaces, strip "uh"/"um" before matching
- `isSpeakerDead(segments)`: simple `segments.length === 0` check (VAD returns 0 for dead)
- `removeMicHallucinations(words)`: detects any 8-gram repeated 3+ times in a 120-word window, removes the loop
- `mergeTranscripts()`: dead-channel path outputs raw mic text with `*[Speaker separation unavailable...]*`
- `MIN_GAP_WORDS = 7`: unconditional absorption of short You gaps between Them runs
- Removed: `filterHallucinations()` (VAD handles upstream)
- Removed: anchor-based gap absorption (was unreliable without VAD; simpler approach sufficient)

## Session Results (all 14 remerged)
| Session | Duration | Turns | Notes |
|---------|----------|-------|-------|
| 2026-02-16T18-10-55 | 105m | 235 | Large group meeting |
| 2026-02-17T14-01-26 | 47m | 75 | Technical demo, improved with filler fix |
| 2026-02-17T15-52-10 | 4m | 11 | Short troubleshooting call |
| 2026-02-17T17-01-47 | 49m | — | Dead speaker channel → unlabeled |
| 2026-02-18T00-46-44 | 27m | 79 | 1:1 chat |
| 2026-02-18T14-02-32 | 41m | 21 | Champions meeting |
| 2026-02-18T15-41-23 | 29m | 38 | Demo session |
| 2026-02-18T19-00-33 | 63m | 146 | 1:1 technical discussion |
| 2026-02-18T23-01-46 | 52m | 71 | Sales/product call |
| 2026-02-19T17-09-54 | 71m | 237 | Long 1:1 coding session (mic hallucination removed) |
| 2026-02-20T14-01-56 | 24m | 34 | Standup/check-in |
| 2026-02-20T19-00-46 | 29m | 117 | 1:1 |
| 2026-02-20T19-30-41 | 58m | 133 | 3-person meeting |

## Known Remaining Issues
1. **~2-5 misattributed Them fragments per session** (8-12 words): Content word
   differences between mic/speaker transcription that neither filler stripping nor
   word count can fix — inherent to dual-channel approach.
2. **Multi-person meetings**: Speaker channel captures all non-You voices as one stream,
   so Them = everyone else (no per-person diarization).

## What Didn't Work / Why
- **Raising MIN_GAP_WORDS above 7**: Would absorb real You speech (8-12 word genuine
  contributions are common in active discussions)
- **Anchor-based gap absorption**: Can't distinguish real You from misattributed Them
  because both appear adjacent in speaker text (Dan not captured in speaker channel)
- **Filtering "Yeah.", "Okay." as hallucinations**: These are often real backchannels
- **RUN_LENGTH = 4**: Tested and rejected — creates many more spurious matches, turns
  jumped 235→329 for the large group session. 5 is the right threshold.

## Next Steps (if continuing)
- Build and install binary: `bun run build && ./install.sh`
- Add `eval-cache/` to `.gitignore`
- Commit: src/merge.ts, src/transcribe.ts, src/index.ts, scripts/eval-merge.ts, scripts/remerge.ts

## Eval Infrastructure
- `eval-cache/`: 28 JSON files (mic + speaker VAD-transcribed for all 14 sessions)
- `scripts/eval-merge.ts`: Transcribes WAVs, caches, shows merge preview
  - `--retranscribe` flag forces re-transcription (use after algorithm changes to speaker transcription)
  - Speaker channel uses VAD automatically
- `scripts/remerge.ts`: Batch remerge from cached transcriptions (fast, no whisper needed)
