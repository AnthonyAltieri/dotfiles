# Go links for Chrome

Short links like `go/docs` on every device, served by [golink](https://github.com/tailscale/golink) at `http://go` on the tailnet. The server runs on debian as the systemd user service `golink` (`modules/platforms/linux/golink.nix`). This extension makes it nicer to use from Chrome on a computer.

## What the extension does

- **Type `go/name` in the address bar.** Chrome sends a search for `go/name` to Google; the extension catches it before it loads and opens the link on `https://go.<tailnet>.ts.net`. Typed or clicked `http://go/...` links take the same route. Anything after the name is passed on, so `go/gh/dotfiles` works with golink's path templates.
- **Nothing opens without Tailscale.** Before opening a link, the extension checks that your go server answers over HTTPS at its full tailnet name. That name only resolves through Tailscale, and only your tailnet can get its certificate. If the check fails, you get a "Tailscale isn't connected" page with a Retry button, and nothing named `go` on the current network is ever contacted.
- **Autocomplete.** Type `go/`, press Tab, then part of a name or URL to pick from your saved links.
- **Save the current tab.** Click the extension icon, type a name, press Save. If the name already points somewhere else, the button turns into Replace so you confirm before overwriting.
- **All links.** The popup links to `http://go/.all`. The full editor (edit, delete, owners, templates) is golink's own page at `http://go/`.

The redirect only covers Google on `www.google.com`, Chrome's default search engine. With another default engine, use the `go/` + Tab keyword or type `http://go/name`.

## Install (Mac or Windows)

Every computer needs Tailscale connected with MagicDNS on (the default), so `http://go` resolves.

The first time you open a go link, the extension follows `http://go/` to learn the server's full name, `https://go.<tailnet>.ts.net`, and remembers it. It only accepts a name of that shape served over HTTPS, so it won't learn a different machine called `go` by mistake. To make it forget the name (for example, after renaming the tailnet), remove the extension and load it again.

1. Get this folder onto the computer: clone the dotfiles repo, or download it from GitHub as a ZIP and unzip it somewhere permanent. Chrome loads the extension from this folder every time it starts, so don't delete it.
2. Open `chrome://extensions` and turn on **Developer mode** (top right).
3. Click **Load unpacked** and choose the `chrome/go-links` folder.
4. Pin the extension from the puzzle-piece menu so the save button is one click away.

Unpacked extensions don't sync through your Google account, so repeat this on each computer. After pulling changes, click the reload icon on the extension's card.

## iPhone

Chrome on iOS can't run extensions, but the links live on the server, so the phone only needs Tailscale connected.

- Open `https://go.<tailnet>.ts.net/name`. That name only resolves while Tailscale is connected, so it can't open anything else by mistake. Shorter `http://go/name` also works when connected, but nothing on the phone checks the connection first.
- Add `https://go.<tailnet>.ts.net/` to your home screen (Share → Add to Home Screen) to create, edit and browse links from the phone.

## First-time server setup

On debian, after switching to a Home Manager generation that includes `golink`:

```sh
journalctl --user -u golink | grep -m1 login.tailscale.com
```

Open that link and approve the node. It joins the tailnet as `go`, and `http://go/` starts working on every device. If the tailnet has HTTPS certificates enabled, golink also serves `https://go.<tailnet>.ts.net` and sends `http://go` there.

## Backups

`curl -s http://go/.export > golinks.jsonl` saves every link. golink restores from such a file with `--snapshot`.
