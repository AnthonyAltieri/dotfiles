### neovim configuration
Inspired by (ie. most of it taken from): https://github.com/ThePrimeagen/neovimrc/tree/master

`:Hidden` opens an editable JSON buffer for the left Neo-tree sidebar's hidden
file patterns. Save with `:w` to apply changes immediately. Settings persist in
`stdpath("data")/hidden.json` (normally `~/.local/share/nvim/hidden.json`), outside
the Nix-managed configuration. The initial configuration is:

```json
{
  "python": [
    "**/__pycache__/**"
  ]
}
```

Add language keys with lists of Neo-tree glob patterns. All language groups apply
together, regardless of the current buffer's language. A pattern ending in `/**`
also hides the matching directory. Remove a pattern to show those files again;
`{}` clears all custom filters. These patterns stay hidden even with Neo-tree's
`H` toggle; dotfiles, Git-ignored files, and search pickers keep their existing
settings. Invalid JSON, list shapes, or globs report an error and leave the active
filters unchanged; fix the file and save again. If invalid settings remain on
disk when Neovim restarts, it reports the error and uses the initial configuration.

Matching results are cached for up to 20,000 paths per Neovim session, with the
oldest entries evicted first. Changing patterns clears the cache; saving unchanged
patterns keeps it and avoids a sidebar refresh. The cache covers only these
hidden-pattern checks, so file changes still appear through Neo-tree's normal
refresh behavior.

`:Md` opens the current saved Markdown file in Obsidian on macOS using
`obsidian open "path=file:<absolute-path>"`. It opens the original file in place and
leaves unsaved Neovim edits untouched; use `:w` first to include those changes.
The `file:` prefix identifies a file outside the vault; a plain absolute path
is still treated as a vault path by the CLI. The CLI opens the tab without
focusing Obsidian, so `:Md` runs `open -a Obsidian` after a successful open to
bring the window to the front.

Keep Obsidian running and enable **Settings → General → Command line interface**.
The command uses `obsidian` from PATH, falling back to the CLI bundled at
`/Applications/Obsidian.app/Contents/MacOS/obsidian-cli`.

Install Obsidian manually from [obsidian.md/download](https://obsidian.md/download).
Bootstrap does not install or update Obsidian. To receive [early-access versions](https://obsidian.md/help/early-access),
sign in with a Catalyst-enabled Obsidian account, enable **Settings → General →
Receive early access versions**, then check for updates and relaunch.

Opening files outside a vault requires [Obsidian 1.14.2 or newer](https://obsidian.md/changelog/2026-09-15-desktop-v1.14.2/)
with a CLI-capable installer (1.12.7+). Version 1.14.2 introduced this feature
in early access. The launcher also reports CLI errors printed with exit code zero.
