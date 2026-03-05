# meeting-transcripts — Natural Language Transcript Access Plugin

Fetch meeting transcripts from `~/transcripts/` using natural language time queries. Works as a Claude Code slash command or a standalone CLI.

## Installation

### As a Claude Code slash command

```bash
mkdir -p .claude/commands
cp plugins/meeting-transcripts/plugin.md .claude/commands/transcripts.md
```

Then use `/transcripts` inside any Claude Code session in this project.

### Standalone CLI

No installation needed — run directly with Bun:

```bash
bun plugins/meeting-transcripts/transcripts.ts [query]
```

## Usage examples

```bash
# Most recent transcript (default)
/transcripts
/transcripts latest
/transcripts last

# Today's transcripts
/transcripts today

# Yesterday's transcripts
/transcripts yesterday

# Transcript closest to a specific time today
/transcripts 9am
/transcripts 2pm
/transcripts 14:30

# Transcripts from a specific weekday (most recent occurrence)
/transcripts Monday
/transcripts Friday
/transcripts last Tuesday

# Transcripts from a specific date
/transcripts 2025-01-15
/transcripts 2026-03-04
```

## Output

**Single match** — prints the full transcript:

```
# 2026-03-04T09-15-30.md
# Tue, Mar 4, 2026 at 9:15 AM

**You:** Good morning, let's review the roadmap...
**Them:** Sure, I wanted to discuss the launch timeline...
```

**Multiple matches** — lists with previews:

```
Found 3 transcripts matching "today":

## 2026-03-05T09-00-12.md
   Thu, Mar 5, 2026 at 9:00 AM
   You: Let's start the standup...

## 2026-03-05T14-30-45.md
   Thu, Mar 5, 2026 at 2:30 PM
   Them: Thanks for joining the design review...
```

**No match** — helpful error:

```
No transcripts found for: last Wednesday (searched: Wed, Feb 25 00:00 – Wed, Feb 25 23:59)
Available range: Mon, Jan 6, 2026 at 10:00 AM → Thu, Mar 5, 2026 at 9:00 AM
Try: latest, today, yesterday, a weekday name, or YYYY-MM-DD
```

## Architecture

```
plugins/meeting-transcripts/
  time-parser.ts    Natural language → DateRange conversion
  transcripts.ts    Transcript discovery, matching, and output
  plugin.md         Claude Code slash command definition
  README.md         This file
```

### time-parser.ts

Converts a natural language string into a `DateRange` (start/end `Date` pair). Returns `null` for "latest" to signal most-recent-by-mtime selection. Handles:

- Named periods: `today`, `yesterday`
- Time of day: `9am`, `2pm`, `14:30` (±3h search window, picks closest)
- Weekdays: `Monday`, `last Friday`, `this Tuesday`
- ISO dates: `YYYY-MM-DD`

### transcripts.ts

1. Scans `~/transcripts/` for `.md` files matching `YYYY-MM-DDTHH-MM-SS.md`
2. Parses each filename into a `Date` via `parseTranscriptDate`
3. Applies the `DateRange` filter from `time-parser`
4. Outputs single transcript in full, or a list with snippets for multiple matches

## Requirements

- Bun runtime
- Transcripts in `~/transcripts/` as `.md` files named `YYYY-MM-DDTHH-MM-SS.md`
