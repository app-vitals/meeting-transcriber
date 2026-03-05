# /transcripts

Fetch and display meeting transcripts using natural language time queries.

## Usage

```
/transcripts [query]
```

Where `[query]` is an optional time expression (default: `latest`).

## Supported queries

| Query | Meaning |
|---|---|
| `latest` or `last` | Most recent transcript (default) |
| `today` | All transcripts from today |
| `yesterday` | All transcripts from yesterday |
| `9am` / `2pm` / `14:00` | Transcript closest to that time today |
| `Monday` / `last Friday` | All transcripts from that weekday |
| `2026-01-15` | All transcripts from that date |

## Examples

```
/transcripts
/transcripts latest
/transcripts today
/transcripts yesterday
/transcripts 9am
/transcripts Monday
/transcripts last Friday
/transcripts 2025-01-15
```

## Output

- **Single match**: prints the full transcript content
- **Multiple matches**: lists each with date/time and a short preview
- **No match**: explains what was searched and shows the available date range

## Instructions for Claude Code

When this slash command is invoked, extract the query argument (everything after `/transcripts`, trimmed). If no argument is given, use `latest`.

Run:

```bash
bun plugins/meeting-transcripts/transcripts.ts $ARGUMENTS
```

After the script completes:

- If a single transcript was printed, summarize its key discussion points and any action items you see.
- If multiple transcripts were listed, tell the user how many were found and ask which one they'd like to read.
- If an error occurred (no match), relay the error message and suggest alternative queries based on the available date range shown.
