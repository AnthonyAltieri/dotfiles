# Codex + `spaces`

If you are moving from `claude --worktree` to Codex and want the same isolated-branch workflow, you can do it with [`spaces`](https://github.com/AnthonyAltieri/spaces) instead of wiring raw `git worktree` commands together by hand.

That has two practical upsides:

- `spaces` handles naming, branch creation, workspace layout, and discovery for you.
- The Codex workspace root can be the whole `space`, which is better when one task spans multiple repos.

By the end of this guide, you will have patterns for:

- creating a new `space` and opening Codex there with one of three sandbox levels
- forking an existing Codex conversation into a new `space`
- opening an existing `space` as a fresh session or a forked conversation
- targeting either the whole `space` or one repo inside it
- handling custom `spaces` base directories
- wrapping the whole thing in `.zshrc` shortcuts

The examples below use `spaces --json` plus `jq` so the shell can extract the generated workspace path reliably. In this dotfiles setup, both are already available.

## Cheat Sheet

Common one-off flows:

```bash
# new space, loose sandbox
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir"

# new space, workspace-write + on-request approvals
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'

# fork the current conversation into a fresh space
sid='<session-id>' &&
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex fork "$sid" -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'

# reopen an existing space
space='jolly-anchor' &&
space_dir=$(spaces show "$space" --json | jq -r '.workspace_dir') &&
codex -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

If you want the exact old one-repo root instead of the whole `space`, extract `repos[0].worktree_path` or a specific repo path from `spaces show --json` and point `codex -C` there instead.

## The Core Pattern

The raw `git worktree` version had to solve four separate problems:

- invent a random worktree name
- choose a parent directory
- create the branch and worktree
- remember where that worktree ended up later

`spaces` collapses those into one command:

```bash
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir"
```

That creates a new named `space`, writes registry metadata, and gives you a stable `workspace_dir` to hand to Codex.

If you want Codex rooted at the single repo worktree inside that space instead of the space root, use:

```bash
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
repo_dir=$(printf '%s\n' "$space_json" | jq -r '.repos[0].worktree_path') &&
codex -C "$repo_dir"
```

Two practical notes:

- `spaces create` requires the source repo to have an `origin` remote.
- In testing, `spaces create` based the new workspace branch on the repo's upstream default branch even when the source repo was currently checked out on another feature branch. That means you usually do not need the explicit `base=main` plumbing from the raw `git worktree` version.

If you want deterministic names instead of the generated random workspace name, `spaces` already exposes that directly:

```bash
repo=$(git rev-parse --show-toplevel) &&
spaces create "$repo" --name api-cleanup --json
```

If you want a specific branch name inside the new space, use `--branch`:

```bash
repo=$(git rev-parse --show-toplevel) &&
spaces create "$repo" --branch release/1.2-agent --json
```

`--branch` controls the branch name created inside the repo worktree. It does not replace the generated workspace directory name unless you also pass `--name`.

## Three Modes

The useful question is still how tightly you want Codex fenced inside the new workspace. The same silly mnemonic pattern from the original article still works fine, just with `space` instead of `worktree`.

### `yorkspace` (yolo + space)

New space, no extra fences:

```bash
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir"
```

### `gorkspace` (git + space)

New space, workspace-write, Git can still ask for approval:

```bash
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

For most real branch work, this is the best default.

### `sorkspace` (sandbox + space)

New space, workspace-write, no approval prompts:

```bash
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir" -s workspace-write -a never -c 'sandbox_workspace_write.network_access=true'
```

If the goal is to keep Codex hard-fenced inside the new workspace, this is the strict version.

## Reusing An Existing Space

This is where `spaces` is nicer than raw `git worktree` plumbing. You do not need to rediscover paths with `git worktree list --porcelain`; the registry already knows them.

Fresh session in an existing space:

```bash
space='jolly-anchor' &&
space_dir=$(spaces show "$space" --json | jq -r '.workspace_dir') &&
test -d "$space_dir" &&
codex -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

Same conversation context, forked into that existing space:

```bash
sid='<session-id>' &&
space='jolly-anchor' &&
space_dir=$(spaces show "$space" --json | jq -r '.workspace_dir') &&
test -d "$space_dir" &&
codex fork "$sid" -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

If you want a specific repo inside the space instead of the workspace root, resolve that repo explicitly:

```bash
space='jolly-anchor' &&
repo='infra' &&
repo_dir="$(
  spaces show "$space" --json |
  jq -r --arg repo "$repo" '.repos[] | select(.repo_name == $repo) | .worktree_path'
)" &&
test -d "$repo_dir" &&
codex -C "$repo_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

Use explicit session IDs rather than `--last` when you want deterministic behavior.

## Forking Conversation Context Into A New Space

This is the subtle workflow: take a conversation already happening in one repo or one space and fork the same transcript into a brand-new space.

With raw `git worktree`, you had to be careful to force the new worktree to branch from `main` instead of whatever feature branch you happened to be standing on. With `spaces`, that plumbing is shorter because the new space is created from the source repo's upstream default branch.

```bash
sid='<session-id-from-/status>' &&
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create "$repo" --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex fork "$sid" -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

If the task spans multiple repos, pass all of them to `spaces create` up front:

```bash
space_json=$(spaces create infra lrl-aws webapps-infra --json) &&
space_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$space_dir" -s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true'
```

One caveat still applies: `codex fork` copies conversation context, not file state. The new thread sees the files from the new space you just created, not any uncommitted edits that only existed in the original repo or original space.

## Discovery, Paths, And Base Directories

The old path trap was accidentally nesting `.codex/worktrees/...` inside some other linked worktree because the relative path resolved from the wrong Git root.

`spaces` mostly removes that class of mistake because it stores workspaces under a dedicated base directory and tracks them in a registry. On this machine, the default looks like this:

- registry: `~/.spaces/registry.json`
- workspace root: `~/.spaces/<workspace-name>`
- repo worktree inside that space: `~/.spaces/<workspace-name>/<repo-name>`

If you want to see what exists, ask `spaces` directly:

```bash
spaces list --json
spaces show jolly-anchor --json
```

If you do not want to use `~/.spaces`, pass `--base-dir` consistently:

```bash
repo=$(git rev-parse --show-toplevel) &&
spaces create "$repo" --base-dir "$HOME/tmp/spaces" --json
```

That matters for `create`, `list`, `show`, and `remove`. If you use shell wrappers, it is convenient to centralize that with an env var such as `CODEX_SPACES_BASE_DIR`.

## Cleanup

Raw `git worktree` helpers usually stop at creation. `spaces` also gives you a first-class cleanup path:

```bash
spaces remove jolly-anchor --yes --keep-branches
spaces remove jolly-anchor --yes --delete-branches
```

Use the explicit branch cleanup mode you want rather than assuming a default.

So this version is already better than the raw worktree helper pattern: cleanup is not automatic, but it is at least a supported command instead of separate Git housekeeping.

## `.zshrc` Wrapper

If you want this to feel like a native Codex affordance, wrap it in a shell function. The version below keeps the same three modes:

- `codex --yorkspace`
- `codex --gorkspace`
- `codex --sorkspace`

It also adds the same higher-level workflows:

- `codex --*-fork <session-id|--last>`
- `codex --*-open <space-name>`
- `codex --*-refork <session-id|--last> <space-name>`

To keep repo arguments separate from real Codex arguments, anything after `--` is forwarded to the real Codex CLI unchanged. If you do not pass repos for the create flows, the wrapper defaults to the current Git repo root.

Put this in your `.zshrc`:

```bash
# -----------------------------------------------------------------------------
# CODEX CLI WRAPPER (codex)
# -----------------------------------------------------------------------------
# Shell-only convenience flags for creating or reusing `spaces` workspaces.
#
# Custom flags:
#   --yorkspace                  -> new space, no extra fences
#   --gorkspace                  -> new space, workspace-write + on-request
#   --sorkspace                  -> new space, workspace-write + a never + network
#   --*-fork <sid> [repos...]    -> new space + fork existing conversation
#   --*-open <space>             -> open existing space as fresh session
#   --*-refork <sid> <space>     -> fork existing conversation into existing space
#
# Extra Codex flags go after `--`:
#   codex --gorkspace -- --model gpt-5.4
#   codex --gorkspace infra webapps-infra -- --model gpt-5.4

_codex_current_repo() {
  git rev-parse --show-toplevel 2>/dev/null || {
    print -u2 'codex spaces wrapper: not inside a Git repo'
    return 1
  }
}

_codex_spaces_base_args() {
  if [[ -n "${CODEX_SPACES_BASE_DIR:-}" ]]; then
    reply=(--base-dir "$CODEX_SPACES_BASE_DIR")
  else
    reply=()
  fi
}

_codex_mode_args() {
  case "$1" in
    yorkspace) reply=() ;;
    gorkspace) reply=(-s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true') ;;
    sorkspace) reply=(-s workspace-write -a never -c 'sandbox_workspace_write.network_access=true') ;;
    *)
      print -u2 "codex spaces wrapper: unknown mode: $1"
      return 1
      ;;
  esac
}

_codex_space_dir() {
  local space="$1"
  local -a base_args

  _codex_spaces_base_args || return 1
  base_args=("${reply[@]}")

  spaces show "${base_args[@]}" "$space" --json | jq -r '.workspace_dir'
}

_codex_new_space_json() {
  local -a repos base_args

  _codex_spaces_base_args || return 1
  base_args=("${reply[@]}")

  if (( $# == 0 )); then
    repos=("$( _codex_current_repo )") || return 1
  else
    repos=("$@")
  fi

  spaces create "${base_args[@]}" --json "${repos[@]}"
}

codex() {
  local cmd flavor action sid space space_json space_dir
  local -a mode_args wrapper_args codex_args repos

  cmd="$1"

  if [[ "$cmd" != --yorkspace* && "$cmd" != --gorkspace* && "$cmd" != --sorkspace* ]]; then
    command codex "$@"
    return
  fi

  shift

  while (( $# > 0 )); do
    if [[ "$1" == -- ]]; then
      shift
      codex_args=("$@")
      break
    fi
    wrapper_args+=("$1")
    shift
  done

  flavor="${cmd#--}"
  flavor="${flavor%%-*}"
  action="${cmd#--$flavor}"
  action="${action#-}"

  _codex_mode_args "$flavor" || return 1
  mode_args=("${reply[@]}")

  case "$action" in
    '')
      repos=("${wrapper_args[@]}")
      space_json="$(_codex_new_space_json "${repos[@]}")" || return 1
      space_dir="$(printf '%s\n' "$space_json" | jq -r '.workspace_dir')" || return 1
      command codex -C "$space_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    fork)
      sid="${wrapper_args[1]}"
      [[ -n "$sid" ]] || {
        print -u2 "usage: codex $cmd <session-id|--last> [repos...] [-- extra-codex-args...]"
        return 2
      }
      if (( ${#wrapper_args[@]} > 1 )); then
        repos=("${wrapper_args[@]:1}")
      else
        repos=()
      fi
      space_json="$(_codex_new_space_json "${repos[@]}")" || return 1
      space_dir="$(printf '%s\n' "$space_json" | jq -r '.workspace_dir')" || return 1
      command codex fork "$sid" -C "$space_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    open)
      space="${wrapper_args[1]}"
      [[ -n "$space" ]] || {
        print -u2 "usage: codex $cmd <space-name> [-- extra-codex-args...]"
        return 2
      }
      space_dir="$(_codex_space_dir "$space")" || return 1
      [[ -n "$space_dir" && -d "$space_dir" ]] || {
        print -u2 "codex spaces wrapper: space not found: $space"
        return 1
      }
      command codex -C "$space_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    refork)
      sid="${wrapper_args[1]}"
      space="${wrapper_args[2]}"
      [[ -n "$sid" && -n "$space" ]] || {
        print -u2 "usage: codex $cmd <session-id|--last> <space-name> [-- extra-codex-args...]"
        return 2
      }
      space_dir="$(_codex_space_dir "$space")" || return 1
      [[ -n "$space_dir" && -d "$space_dir" ]] || {
        print -u2 "codex spaces wrapper: space not found: $space"
        return 1
      }
      command codex fork "$sid" -C "$space_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    *)
      print -u2 "codex spaces wrapper: unsupported shortcut: $cmd"
      return 2
      ;;
  esac
}
```

Reload your shell:

```bash
source ~/.zshrc
```

Example usage:

```text
codex --yorkspace
codex --gorkspace
codex --sorkspace -- --model gpt-5.4
codex --gorkspace infra webapps-infra
codex --gorkspace infra webapps-infra -- --model gpt-5.4
codex --gorkspace-fork 12345678-90ab-cdef-1234-567890abcdef
codex --gorkspace-fork --last infra webapps-infra
codex --gorkspace-open jolly-anchor
codex --gorkspace-refork 12345678-90ab-cdef-1234-567890abcdef jolly-anchor
CODEX_SPACES_BASE_DIR="$HOME/tmp/spaces" codex --sorkspace-fork --last
```

Two practical notes:

- The wrapper above opens Codex at the space root. If you want a specific repo root inside the space, use the manual `spaces show --json` + `jq` snippets from earlier.
- This gets you the old `--worktree` convenience, but cleaner: `spaces` handles naming and cleanup, and the shell wrapper only has to deal with launching Codex in the right place.
