# /distill

Extract structured project context from recent meeting transcripts and write it to `.distill/` files that Claude Code automatically loads.

## What it does

Reads the last 5 meeting transcripts from `~/transcripts/`, calls the Claude API to extract:

- **Goals** — project objectives mentioned or reaffirmed
- **Decisions** — concrete choices made during meetings
- **Action items** — specific tasks with owners and due dates where available
- **Open questions** — unresolved questions raised in meetings

Output is written to `.distill/` in the project root:

```
.distill/
  goals.md           ← Project goals (loaded by Claude Code)
  decisions.md       ← Key decisions (loaded by Claude Code)
  actions.md         ← Action items (loaded by Claude Code)
  open-questions.md  ← Unresolved questions (loaded by Claude Code)
  .processed         ← Tracks which transcripts have been processed
```

Re-running `/distill` is idempotent — already-processed transcripts are skipped and duplicate items are never added.

## Usage

Run the slash command in Claude Code:

```
/distill
```

Or run directly from the terminal:

```bash
# Default: process last 5 transcripts
bun plugins/distill/distill.ts

# Process last 10 transcripts
bun plugins/distill/distill.ts --count 10

# Process all transcripts
bun plugins/distill/distill.ts --all

# Re-process already-seen transcripts
bun plugins/distill/distill.ts --force
```

## Installation

To install as a Claude Code project command, copy `plugin.md` to `.claude/commands/`:

```bash
mkdir -p .claude/commands
cp plugins/distill/plugin.md .claude/commands/distill.md
```

Then `/distill` will be available as a slash command in any Claude Code session in this project.

## When to run

Run `/distill` after a batch of meetings to keep project context up to date. The `.distill/` files are designed to be committed to source control so all team members and Claude Code sessions share the same extracted context.

## Environment

Requires `ANTHROPIC_API_KEY` set in the environment or in `~/.openclaw/workspace/.secrets.env`.

## Implementation

- `distill.ts` — main script (transcript discovery, API call, file writing)
- `prompts.ts` — Claude system prompt for structured extraction

## Instructions for Claude Code

When this slash command is invoked, run the following:

```bash
bun plugins/distill/distill.ts
```

After it completes, read the updated `.distill/` files and summarize what was extracted. If `.distill/goals.md` exists, mention the current project goals. If `.distill/actions.md` exists, list any new action items added.
