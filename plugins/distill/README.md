# distill — Structured Context Extraction Plugin

Extracts structured project context (goals, decisions, action items, open questions) from meeting transcripts and writes persistent markdown files that Claude Code automatically loads.

## What gets extracted

| File | Contents |
|---|---|
| `.distill/goals.md` | Project-level objectives mentioned or reaffirmed in meetings |
| `.distill/decisions.md` | Concrete decisions made (past tense, specific) |
| `.distill/actions.md` | Tasks with owners and due dates where available |
| `.distill/open-questions.md` | Questions raised but not yet resolved |
| `.distill/.processed` | Ledger of already-processed transcript filenames |

## Installation

### As a Claude Code slash command

```bash
mkdir -p .claude/commands
cp plugins/distill/plugin.md .claude/commands/distill.md
```

Then use `/distill` inside any Claude Code session in this project.

### Standalone CLI

No installation needed — run directly with Bun:

```bash
bun plugins/distill/distill.ts
```

## Usage

```bash
# Process last 5 transcripts (default)
bun plugins/distill/distill.ts

# Process last N transcripts
bun plugins/distill/distill.ts --count 10

# Process all transcripts
bun plugins/distill/distill.ts --all

# Re-process already-seen transcripts (adds new/changed items)
bun plugins/distill/distill.ts --force
```

## Idempotency

- Transcripts are tracked by filename in `.distill/.processed`
- Re-running skips already-processed files unless `--force` is passed
- Duplicate items are never written (case-insensitive deduplication)
- Safe to commit `.distill/` and run across machines

## Output format

Each `.distill/*.md` file is a plain markdown bullet list with source annotations:

```markdown
# Action Items

_Tasks and next steps from meetings._

<!-- distilled: 2026-03-05 from 2026-03-04_14-00-00.md -->
- Ship the onboarding redesign (Alice, by 2026-03-10)
- Set up staging environment (Bob)
```

## Requirements

- Bun runtime
- `ANTHROPIC_API_KEY` in environment or `~/.openclaw/workspace/.secrets.env`
- Transcripts in `~/transcripts/` as `.md` files

## Architecture

```
plugins/distill/
  distill.ts    Main script: discovery → API → write output
  prompts.ts    Claude system prompt for structured JSON extraction
  plugin.md     Claude Code slash command definition
  README.md     This file
```

The extraction prompt requests JSON with four arrays (`goals`, `decisions`, `actions`, `openQuestions`). The script de-duplicates against existing file content before appending.
