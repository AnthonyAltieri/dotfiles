# Codex + `spaces`

If you are moving from `claude --worktree` to Codex and want the same isolated-branch workflow, you can do it with [`spaces`](https://github.com/AnthonyAltieri/spaces) instead of wiring raw `git worktree` commands together by hand.

This guide adapts Alex Fazio's article on X: https://x.com/alxfazio/status/2035093597238784486

In this repo, `spaces` is the standard for all worktree-style management. The only supported Codex shortcut is `codex --spaces`.

## Supported Wrapper

The wrapper creates a new space and launches Codex in it.

Supported forms:

```bash
codex --spaces
codex --spaces /path/to/repo
codex --spaces /path/to/repo/1 /path/to/repo/2
codex --spaces /path/to/repo --name api-cleanup
codex --name api-cleanup --spaces /path/to/repo
codex --spaces /path/to/repo --name api-cleanup -- --model gpt-5.4
```

Rules:

- The only wrapper-owned flags before `--` are `--spaces` and `--name`.
- Any other Codex CLI flags still go after `--`.
- If you pass no repo operands, the wrapper uses the current Git repo root.
- Repo operands are resolved to Git toplevel paths before `spaces create` runs.
- If you pass one repo, Codex opens at that repo worktree path inside the new space.
- If you pass multiple repos, Codex opens at the space root.

## `--name` Behavior

`--name` is used for both:

- the `spaces` workspace name
- the branch name created inside each repo worktree

The wrapper translates:

```bash
codex --spaces /path/to/repo --name api-cleanup
```

into the equivalent `spaces` create call:

```bash
spaces create --json --name api-cleanup --branch api-cleanup /path/to/repo
```

Before calling `spaces create`, the wrapper fails if `api-cleanup` already exists as:

- a local branch in any provided repo
- a remote-tracking branch in any provided repo

That keeps the failure at the shell boundary instead of waiting for partial worktree creation.

## Manual Equivalent

The wrapper is convenience only. The core flow is still:

```bash
repo=$(git rev-parse --show-toplevel) &&
space_json=$(spaces create --json "$repo") &&
target_dir=$(printf '%s\n' "$space_json" | jq -r '.repos[0].worktree_path') &&
codex -C "$target_dir"
```

For multiple repos:

```bash
space_json=$(spaces create --json /path/to/repo/1 /path/to/repo/2) &&
target_dir=$(printf '%s\n' "$space_json" | jq -r '.workspace_dir') &&
codex -C "$target_dir"
```

With a deterministic workspace and branch name:

```bash
space_json=$(spaces create --json --name api-cleanup --branch api-cleanup /path/to/repo) &&
target_dir=$(printf '%s\n' "$space_json" | jq -r '.repos[0].worktree_path') &&
codex -C "$target_dir"
```

## Direct CLI Workflow

Use the `spaces` CLI directly when you need discovery or cleanup:

```bash
spaces list --json
spaces show <space> --json
spaces create <repo-path>... --json
spaces remove <space> --yes --keep-branches
spaces remove <space> --yes --delete-branches
```

Key details:

- `spaces create` requires the source repo to have an `origin` remote.
- In local testing, `spaces create` based new workspaces on the source repo's upstream default branch rather than the currently checked out feature branch.
- `CODEX_SPACES_BASE_DIR` overrides the default base directory for both the wrapper and direct CLI usage when you pass `--base-dir` consistently.

## Multi-Repo Rule

If the task spans multiple repos, create one space containing all of them and root Codex at the space root unless you explicitly need one repo only.
