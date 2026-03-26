---
name: spaces
description: Use when the user asks about Codex worktrees, isolated task branches, or multi-repo task environments. In this repo, all worktree-style management goes through the local `spaces` CLI and the `codex --spaces` shell shortcut.
metadata:
  short-description: Manage Codex worktree-style flows with `spaces`
---

# Spaces

Use this skill for Codex workspace management in this dotfiles setup.

Trigger this skill for:
- requests that say "worktree" but really mean isolated Codex branch or workspace flows
- creating a fresh Codex workspace for a task
- inspecting, reusing, or cleaning up existing `spaces` workspaces
- multi-repo tasks that should share one workspace root

## Defaults

- Treat "worktree" as the `spaces` workflow in this repo.
- Use `spaces` for all worktree-style management.
- Prefer `codex --spaces` when the user wants to create and launch a fresh Codex workspace directly.
- Use the `spaces` CLI directly for discovery and cleanup.

Supported wrapper patterns:

- `codex --spaces [repo-path ...]`
- `codex --spaces [repo-path ...] --name <workspace-name>`
- `codex --name <workspace-name> --spaces [repo-path ...]`
- `codex --spaces [repo-path ...] -- --model gpt-5.4`

Wrapper rules:

- `--spaces` and `--name` are the only wrapper-owned flags before `--`.
- Anything after `--` is forwarded to the real Codex CLI unchanged.
- If no repo paths are passed, the wrapper uses the current Git repo root.
- `--name` sets both the workspace name and branch name.
- The wrapper rejects `--name` if that branch already exists locally or as a remote-tracking branch in any provided repo.

## Target Selection

The wrapper resolves targets like this:

- single-repo space: open the repo worktree path
- multi-repo space: open the space root

That means the default behaves like the old single-repo worktree flow when a space contains one repo, but still supports multi-repo task spaces cleanly.

## Direct CLI Workflow

Use the `spaces` CLI directly when you need discovery or cleanup:

```bash
spaces list --json
spaces show <space> --json
spaces create <repo>... --json
spaces remove <space> --yes --keep-branches
spaces remove <space> --yes --delete-branches
```

Key details:

- `spaces create` requires the source repo to have an `origin` remote.
- In local testing, `spaces create` based new workspaces on the source repo's upstream default branch rather than the currently checked out feature branch.
- `CODEX_SPACES_BASE_DIR` overrides the default base directory for both the wrapper and direct CLI usage when you pass `--base-dir` consistently.

## Multi-Repo Rule

If the task spans multiple repos, create one space containing all of them and root Codex at the space root unless the user explicitly wants one repo only.

## When Not To Use This Skill

- The request is about ordinary Git branching with no isolated Codex workspace behavior.
