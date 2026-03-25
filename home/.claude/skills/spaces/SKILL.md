---
name: spaces
description: Use when the user asks about worktrees, isolated task branches, opening or reusing task workspaces, or multi-repo task environments in this repo. All worktree-style management here goes through the local `spaces` CLI.
metadata:
  short-description: Manage worktree-style flows with `spaces`
---

# Spaces

Use this skill for workspace management in this dotfiles setup.

Trigger this skill for:
- requests that say "worktree" but really mean isolated branch or workspace flows
- creating a fresh task workspace
- opening, reusing, or cleaning up existing `spaces` workspaces
- multi-repo tasks that should share one workspace root

## Defaults

- Treat "worktree" as the `spaces` workflow in this repo.
- Use `spaces` for all worktree-style management.
- When a space contains multiple repos, prefer the space root unless the user explicitly wants one repo inside it.

## Direct CLI Workflow

Use the `spaces` CLI directly for discovery, creation, and cleanup:

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
- Use `spaces show <space> --json` to discover the workspace root and any per-repo worktree paths inside it.
- `CODEX_SPACES_BASE_DIR` still overrides the default base directory when the environment or wrappers set it.

## Multi-Repo Rule

If the task spans multiple repos, create one space containing all of them and root the work there at the space root unless the user explicitly wants one repo only.

## When Not To Use This Skill

- The request is about ordinary Git branching with no isolated workspace behavior.
