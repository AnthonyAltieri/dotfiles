# Atlas Data Paths (macOS)

Atlas stores Chromium-style profile data under stable and beta roots:

- `~/Library/Application Support/com.openai.atlas/browser-data/host/Local State`
- `~/Library/Application Support/com.openai.atlas.beta/browser-data/host/Local State`
- Profiles under the selected root's `<profile>` directory

Key files in the active profile:

- `History` (SQLite DB, table `urls`)
- `Bookmarks` (JSON)

The helper selects the root with the most recently modified `Local State`, unless `ATLAS_DATA_ROOT` names an explicit absolute `browser-data/host` directory. The active profile is derived from `profile.last_used`, with a fallback to `Default`.

## AppleScript Assumptions

Atlas appears to expose a Safari-style AppleScript dictionary with:

- `every window`
- `every tab of w`
- `active tab index`
- `make new tab with properties {URL:"..."}`
- `close tab <n>`
- `reload tab <n>`

Treat Atlas as a single app with one AppleScript target.
