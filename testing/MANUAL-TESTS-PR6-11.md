# Meeting Transcriber — Manual Test Plan (PRs #6-#11)

Shipped 2026-03-05. Run these on macOS to verify all changes.

## Prerequisites

```bash
cd meeting-transcriber && git pull
cd MeetingTranscriberApp && swift build
cd .. && bun run build
```

---

## PR #6 — Native Notifications

1. Launch app, start a short recording (open Zoom/Meet to trigger mic)
2. Stop recording, wait for transcription to complete
3. ✅ Notification appears with "Meeting Transcriber" as app identity (not terminal-notifier)
4. ✅ Notification plays a sound
5. ✅ Click the notification → transcript viewer opens focused on that transcript
6. Test with terminal-notifier uninstalled: `brew uninstall terminal-notifier`
7. ✅ Transcription still completes and notifies without terminal-notifier

---

## PR #7 — DMG Installer

8. Run build script unsigned (no cert needed):
   ```bash
   chmod +x scripts/build-dmg.sh && ./scripts/build-dmg.sh
   ```
9. ✅ Script completes without error, produces `build/MeetingTranscriber-1.0.0.dmg`
10. ✅ Mount the DMG — shows drag-to-Applications layout
11. ✅ App inside DMG has correct bundle structure (right-click → Show Package Contents → Contents/MacOS, Contents/Resources)
12. ✅ `MeetingTranscriber.entitlements` is present at repo root
13. Check GitHub Actions tab — workflow file should parse clean (no YAML errors)

---

## PR #8 — Preserve mt CLI

14. Drag app to ~/Applications (or /Applications)
15. Launch app → look for "Install mt CLI" in the menu bar dropdown
16. ✅ Click "Install mt CLI" → success message
17. ✅ `which mt` → points to `~/.local/bin/mt`
18. ✅ `mt list` → shows your existing transcripts
19. ✅ `mt watch` → starts the TS engine (Ctrl+C to stop)
20. ✅ `ls -la ~/.local/bin/mt` → symlink points into app bundle Resources
21. Reinstall app (drag fresh copy to Applications)
22. ✅ `mt list` still works (symlink survives reinstall)
23. In app menu → click "Remove mt CLI"
24. ✅ `which mt` → gone

---

## PR #9 — AI Summaries

25. Set API key: `export ANTHROPIC_API_KEY=sk-ant-...` (or use Settings UI from PR #10)
26. Run a meeting recording → let transcription complete
27. ✅ Open transcript file — `## Summary` section at the top with TL;DR, action items (checkboxes), key decisions
28. ✅ Check console output for `[summarize] claude-sonnet-4-6 — input: X tokens, output: Y tokens`
29. Test without API key: `unset ANTHROPIC_API_KEY`, run another recording
30. ✅ Console shows `[summarize] ANTHROPIC_API_KEY not set — skipping AI summary`
31. ✅ Transcript still saves successfully (just no summary section)
32. Test with invalid key: `export ANTHROPIC_API_KEY=garbage`
33. ✅ Console shows `[summarize] API call failed:` error
34. ✅ Transcript still saves (graceful degradation)

---

## PR #10 — Settings UI

35. Launch app → open Settings/Preferences (⌘, or menu item)
36. ✅ Tabbed UI appears (General, AI, Audio tabs)
37. ✅ Enter Claude API key → saves to Keychain
    ```bash
    security find-generic-password -s ai.openclaw.MeetingTranscriber -a anthropic-api-key -w
    ```
38. ✅ Toggle AI summaries on/off
39. ✅ Change whisper model selection
40. ✅ Change transcript directory path
41. ✅ Toggle notifications on/off
42. Close and reopen Settings → ✅ all values persisted
43. ✅ Config file written:
    ```bash
    cat ~/Library/Application\ Support/MeetingTranscriber/config.json
    ```
44. Quit and relaunch app → ✅ settings still loaded

---

## PR #11 — Meeting History

45. Open transcript viewer / meeting history view
46. ✅ List shows your existing transcripts with metadata (date, duration if available)
47. ✅ Search box filters transcripts by content
48. ✅ Sort works (by date, name, etc.)
49. ✅ Click a transcript → opens it in the viewer
50. ✅ Empty state looks reasonable if no transcripts exist

---

## 🔥 Smoke Test (End-to-End)

51. Fresh app launch → complete onboarding → grant all permissions
52. Join a real meeting (or fake one with 2 browser tabs playing audio)
53. Let it auto-detect mic → record → stop → transcribe → summarize → notify
54. ✅ Full pipeline works: notification appears, click opens viewer, transcript has summary, history view shows it

---

## Results

| PR | Status | Notes |
|----|--------|-------|
| #6 Notifications | ⬜ | |
| #7 DMG Installer | ⬜ | |
| #8 Preserve CLI | ⬜ | |
| #9 AI Summaries | ⬜ | |
| #10 Settings UI | ⬜ | |
| #11 Meeting History | ⬜ | |
| Smoke Test | ⬜ | |
