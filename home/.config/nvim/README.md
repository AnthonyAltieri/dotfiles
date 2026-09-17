### neovim configuration
Inspired by (ie. most of it taken from): https://github.com/ThePrimeagen/neovimrc/tree/master

`:Md` opens the current saved Markdown file in Obsidian on macOS using
`obsidian open "path=file:<absolute-path>"`. It opens the original file in place and
leaves unsaved Neovim edits untouched; use `:w` first to include those changes.
The `file:` prefix identifies a file outside the vault; a plain absolute path
is still treated as a vault path by the CLI.

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
