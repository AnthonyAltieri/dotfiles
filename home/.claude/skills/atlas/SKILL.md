---
name: "atlas"
description: "macOS-only AppleScript control for the ChatGPT Atlas desktop app. Use only when the user explicitly asks to control Atlas tabs/bookmarks/history on macOS and the \"ChatGPT Atlas\" app is installed; do not trigger for general browser tasks or non-macOS environments."
---


# Atlas Control (macOS)

Use the `atlas-cli` helper from the active Nix profile to control Atlas and inspect local browser data.

Use browser automation for DOM inspection, visible page interaction, and logged-in web sessions. Use this skill only for Atlas-native tab operations or Atlas-local bookmarks and history.

## Quick Start

The active Nix profile puts `atlas-cli` on `PATH`, so call it directly.

Then run:

```bash
atlas-cli app-name
atlas-cli tabs --json
```

The CLI requires the Atlas app bundle in `/Applications` or `~/Applications`:

- `ChatGPT Atlas`

If AppleScript fails with a permissions error, grant Automation permission in System Settings > Privacy & Security > Automation, allowing your terminal to control ChatGPT Atlas.

## Tabs Workflow

1. List tabs to get `window_id` and `tab_index`:

```bash
atlas-cli tabs
```

2. Focus a tab using the `window_id` and `tab_index` from the listing:

```bash
atlas-cli focus-tab <window_id> <tab_index>
```

3. Open a new tab:

```bash
atlas-cli open-tab "https://chatgpt.com/"
```

Optional maintenance commands:

```bash
atlas-cli reload-tab <window_id> <tab_index>
atlas-cli close-tab <window_id> <tab_index>
```

## Bookmarks and History

Atlas stores Chromium-style profile data under `~/Library/Application Support/com.openai.atlas/browser-data/host/`.

List bookmarks:

```bash
atlas-cli bookmarks --limit 100
```

Search bookmarks:

```bash
atlas-cli bookmarks --search "docs"
```

Search history:

```bash
atlas-cli history --search "openai docs" --limit 50
```

History for today (local time):

```bash
atlas-cli history --today --limit 200 --json
```

The history command copies the SQLite database to an automatically cleaned temporary location to avoid lock errors.

The helper checks stable and beta Atlas data roots and selects the one with the most recently modified `Local State`. Set `ATLAS_DATA_ROOT` to an absolute `browser-data/host` directory only when automatic selection is wrong.

If `atlas-cli` is missing on macOS, reapply the profile so the packaged helper is rebuilt and activated. This skill is not installed on Linux profiles.

If history looks stale or empty, inspect these roots without printing unrelated profile data:

- `~/Library/Application Support/com.openai.atlas/browser-data/host/`
- `~/Library/Application Support/com.openai.atlas.beta/browser-data/host/`

## References

Read `references/atlas-data.md` in the skill folder (for example, `$CLAUDE_CONFIG_DIR/skills/atlas/references/atlas-data.md`) when adjusting data paths or timestamps.
