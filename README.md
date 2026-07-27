# dotfiles

Managed with Nix using `nix-darwin` for macOS and Home Manager for user configuration.

For the full architecture walkthrough, see [`docs/nix/README.md`](docs/nix/README.md).

## Configuration model

This repo composes configuration on two axes:

- **Role**
  - `common` — shared configuration for personal and work machines
  - `personal` — `common + personal`
  - `work` — `common + work`
  - `sandbox` — standalone profile for agent sandboxes
- **Platform**
  - `darwin` — `nix-darwin` system modules, Homebrew integration, macOS defaults
  - `linux` — Home Manager plus Nix packages

The resulting outputs are:

- `darwinConfigurations.personal`
- `darwinConfigurations.work`
- `homeConfigurations.personal-linux`
- `homeConfigurations.personal-aarch64-linux`
- `homeConfigurations.work-linux`
- `homeConfigurations.work-aarch64-linux`
- `homeConfigurations.sandbox-aarch64-darwin`
- `homeConfigurations.sandbox-aarch64-linux`
- `homeConfigurations.sandbox-x86_64-linux`

The user-bound outputs resolve the current login user at evaluation time. `bootstrap.sh` handles that automatically; direct `darwin-rebuild`, `home-manager`, `nix build`, and `nix flake check` commands that touch those outputs should include `--impure`.

## Repo layout

```text
.
├── flake.nix
├── bootstrap.sh
├── docs/
├── home/
│   ├── .zshrc
│   ├── .tmux.conf
│   ├── .vimrc
│   ├── .config/
│   ├── .codex/
│   └── .claude/
├── lib/
└── modules/
    ├── shared/
    ├── roles/
    └── platforms/
```

`home/` stores the managed payloads using their real target names, so the tree matches the home directory layout Home Manager deploys.

## Bootstrap on macOS

`bootstrap.sh` is the supported macOS apply path. It is safe to rerun after pulling changes or editing the flake. It installs missing prerequisites only, reloads Nix and Homebrew when they already exist, then reapplies the selected Darwin role.

Run bootstrap as your normal user. On a real apply, the script uses `sudo` only for the final `darwin-rebuild switch` step.

First-time prerequisite install:

```bash
./bootstrap.sh install-dependencies
```

```bash
./bootstrap.sh personal
./bootstrap.sh work
```

Preview without switching:

```bash
./bootstrap.sh personal --dry-run
./bootstrap.sh personal --dry-run --diff
./bootstrap.sh personal --dry-run --overwrite
```

`--dry-run` is available only after Nix is already installed on the machine. On a fresh Mac, run `./bootstrap.sh install-dependencies` first.

Show a closure diff before a real apply:

```bash
./bootstrap.sh personal --diff
./bootstrap.sh work --diff
```

During a real apply, Home Manager backs up conflicting managed files with the `.hm-backup` suffix before replacing them by default.
If you want a one-off apply to force-replace those managed files directly instead, run bootstrap with `--overwrite`.

On the first real nix-darwin apply, bootstrap may also find unmanaged `/etc/bashrc` or `/etc/zshrc` content.
Without `--overwrite`, bootstrap backs those files up to `*.before-nix-darwin` automatically and continues.
With `--overwrite`, bootstrap shows a diff for each conflicting file and asks for confirmation before replacing it.

The deeper explanation of what bootstrap does and how the flake composes roles and platforms lives in [`docs/nix/README.md`](docs/nix/README.md).

## Day-to-day usage

On macOS, rerunning bootstrap is the simplest path:

```bash
./bootstrap.sh personal
./bootstrap.sh work
./bootstrap.sh personal --overwrite
```

If you want to preview first:

```bash
./bootstrap.sh personal --dry-run --diff
./bootstrap.sh work --dry-run --diff
```

You can still apply the Darwin role directly if you want the native command:

```bash
darwin-rebuild switch --flake .#personal --impure
darwin-rebuild switch --flake .#work --impure
```

Apply a Linux profile:

```bash
home-manager switch --flake .#personal-linux --impure
home-manager switch --flake .#personal-aarch64-linux --impure
home-manager switch --flake .#work-linux --impure
home-manager switch --flake .#work-aarch64-linux --impure
```

Apply a sandbox profile:

```bash
home-manager switch --flake .#sandbox-aarch64-darwin --impure
home-manager switch --flake .#sandbox-aarch64-linux --impure
home-manager switch --flake .#sandbox-x86_64-linux --impure
```

Update flake inputs:

```bash
nix flake update
```

## Package strategy

- **Darwin** uses Homebrew through `modules/platforms/darwin/homebrew.nix`.
- **Linux** uses Nix packages through `modules/platforms/linux/packages.nix`.
- **Sandbox** stays lean and avoids desktop-specific settings.
- Repo-local packages that are not present in pinned `nixpkgs`, such as `observe`, are defined under `pkgs/` and exposed through flake `packages`.
- Work-only private Homebrew taps and casks are supplied through local env state, not tracked files.

Current hidden runtime dependencies are also declared, including `jq`.

### Private work Homebrew

The public flake intentionally does not name private Homebrew taps or casks. For work-only taps, set `DOTFILES_WORK_HOMEBREW_TAPS` to a colon-separated list of tap names. For private taps that should clone through SSH or another explicit Git URL, set `DOTFILES_WORK_HOMEBREW_TAP_CLONE_TARGETS` to a semicolon-separated list of `tap=clone_target` entries. For work-only casks, set `DOTFILES_WORK_HOMEBREW_CASKS` to a colon-separated list of cask tokens.

When using bootstrap, put the value in the ignored repo-local file `.dotfiles-private.env`:

```bash
DOTFILES_WORK_HOMEBREW_TAPS=owner/tap
DOTFILES_WORK_HOMEBREW_TAP_CLONE_TARGETS=owner/tap=git@github.com:owner/homebrew-tap.git
DOTFILES_WORK_HOMEBREW_CASKS=private-cask
```

`./bootstrap.sh work` loads that file, trusts the private taps as the Homebrew activation user, and forwards the variables across the final `sudo` apply. If you run `darwin-rebuild` directly, set the variables in the shell for that command and run `brew trust` for private taps yourself. The personal role ignores these variables. If a tap is listed in both `DOTFILES_WORK_HOMEBREW_TAPS` and `DOTFILES_WORK_HOMEBREW_TAP_CLONE_TARGETS`, the clone-target entry wins.

## Managed vs unmanaged files

This repo manages a curated subset of `~/.codex` and `~/.claude`.

Managed agent files include:

- `~/.codex/skills/{adversarial-review,agent-code-review-loop,frontend-design,generate-sprite-sheets,gh-ci,gh-comments,gh-pr-body,handoff,improve-codebase-architecture,linear-claim-work,notion-knowledge-capture,notion-read,programming,sql-read,ultragoal}`
- `~/.codex/AGENTS.md`
- `~/.codex/prompts/pr.md`
- `~/.codex/rules/base.rules`
- `~/.claude/CLAUDE.md`
- `~/.claude/README.md`
- `~/.claude/settings.json`
- `~/.claude/commands/{handle-pr-checks.md,handle-pr-comments.md,pr.md}`
- `~/.claude/skills/{agent-code-review-loop,frontend-design,gh-address-comments,gh-fix-ci,gh-manage-pr,handoff,improve-codebase-architecture,notion-knowledge-capture,notion-read,programming,sql-read}`
- `~/.claude/{statusline-command.sh,tmux-notify.sh}`

Darwin profiles additionally manage `~/.codex/skills/atlas` and `~/.claude/skills/atlas`. The work profile also manages `~/.codex/skills/observe` and `~/.claude/skills/observe`.

The work profile also applies a targeted merge to `~/.codex/config.toml` so Codex knows about the Notion remote MCP server:

```toml
[features]
rmcp_client = true

[mcp_servers.notion]
url = "https://mcp.notion.com/mcp"
```

That merge intentionally touches only those keys. Notion OAuth state remains local; on a new machine, run `codex mcp login notion` after applying the work profile.

These managed `.codex` and `.claude` paths are copied into place as regular files and directories during Home Manager activation. They are intentionally not left as symlinks so Codex and Claude can discover local skills and prompts reliably.

Rust-backed helper commands such as `atlas-cli`, `fetch-comments`, `classify-ci-log`, `gh-manage-pr-summarize`, `gh-pr-image`, and `sql-read` are built from the managed source trees and exposed on `PATH` by the active profile.
Use `gh-pr-image add <image> --alt <text> [--pr ...] [-R ...]` when asked to add an image to a PR body. The prompt-gated MVP accepts exactly one PNG, JPEG, or GIF per invocation on public, same-repository PRs the authenticated account can update and uploads through an experimental, undocumented GitHub endpoint. Private, internal, and fork-authored PRs are unsupported.

Examples of intentionally unmanaged local state:

- `~/.codex/config.toml`, except for the work profile's targeted Notion MCP merge
- `~/.codex/auth.json`
- `~/.codex/rules/default.rules`
- `~/.codex/history.jsonl`
- `~/.codex/sessions/**`
- `~/.codex/worktrees/**`
- `~/.codex/sqlite/**`
- `~/.codex/log/**`
- machine-local Claude/Codex runtime state

`~/.codex/rules/base.rules` is the tracked Nix baseline. `~/.codex/rules/default.rules` is left as a normal local file so Codex can append execpolicy amendments without fighting the Nix-managed path.

## Where changes go

- role-specific policy: `modules/roles/`
- platform-specific policy: `modules/platforms/`
- shared Home Manager behavior: `modules/shared/`
- raw config payloads: `home/`

## Verification

Fast local checks:

```bash
bash tests/nvim-external-write-merge-smoke.sh
bash tests/nvim-monorepo-routing-smoke.sh
bash scripts/test-skill-helpers.sh
```

The Neovim checks expect the relevant lazy.nvim plugin checkouts to already exist under `~/.local/share/nvim/lazy`. `scripts/test-skill-helpers.sh` expects Rust and the helper crates' offline dependencies to be available.

Once Nix is available on the target machine, run:

```bash
nix flake check --impure
nix build --impure .#darwinConfigurations.personal.system
nix build --impure .#darwinConfigurations.personal-overwrite.system
nix build --impure .#darwinConfigurations.work.system
nix build --impure .#darwinConfigurations.work-overwrite.system
nix build --impure .#homeConfigurations.personal-linux.activationPackage
nix build --impure .#homeConfigurations.work-linux.activationPackage
nix build --impure .#homeConfigurations.sandbox-aarch64-darwin.activationPackage
nix build --impure .#homeConfigurations.sandbox-aarch64-linux.activationPackage
nix build --impure .#homeConfigurations.sandbox-x86_64-linux.activationPackage
```

`flake.lock` pins upstream flake inputs, so update it intentionally when you want to move those revisions.

## Docker smoke tests

Ubuntu LTS smoke tests are available through Docker and validate the Linux Home Manager profiles in a fresh `ubuntu:24.04` container:

```bash
./tests/run-linux-docker-smoke.sh
```

By default the runner tests the three logical Linux roles, `personal`, `work`, and `sandbox`, and maps each one to the correct Linux output for the container architecture.

You can also target specific roles:

```bash
./tests/run-linux-docker-smoke.sh personal
./tests/run-linux-docker-smoke.sh work
./tests/run-linux-docker-smoke.sh sandbox
```

The Docker harness installs Nix inside the container, evaluates the Linux Home Manager profile that corresponds to the requested role and container architecture, and asserts key managed files, package selections, and profile-specific behavior such as Oh My Zsh being present on `personal` and `work` but absent on `sandbox`.

If you want to force full activation as well, set `FULL_ACTIVATE=1`:

```bash
FULL_ACTIVATE=1 ./tests/run-linux-docker-smoke.sh
```

Full activation pulls a much larger Nix closure and can exceed typical Docker Desktop disk budgets. Docker does not cover `nix-darwin`, Homebrew integration, or the macOS bootstrap path.

## Visible dataflow research

This human-facing bibliography preserves the research behind the repository's named-stage dataflow guidance without adding it to the programming skill's required context.

See the [Visible Dataflow forward-test evidence](docs/skill-evaluations/programming/visible-dataflow.md) for the human-only prompts, raw outputs, rubric, and iteration record.

### Foundations and architecture

- [McIlroy, Pinson, and Tague, “UNIX Time-Sharing System: Foreword” (1978)](https://doi.org/10.1002/j.1538-7305.1978.tb02135.x): connect small tools through a shared input/output convention; the connector and protocol matter more than the glyph.
- [Backus, “Can Programming Be Liberated from the von Neumann Style?” (1978)](https://doi.org/10.1145/359576.359579): build programs with combining forms rather than reasoning primarily through mutable stores and statement sequences.
- [Hughes, “Why Functional Programming Matters” (1989)](https://doi.org/10.1093/comjnl/32.2.98): use higher-order functions and laziness as modularity glue, not merely as alternative syntax.
- [Garlan and Shaw, “An Introduction to Software Architecture,” §3.1](https://www.sei.cmu.edu/documents/1119/1994_005_001_16331.pdf): distinguish streaming pipes and filters from batch-sequential processing and document the style's architectural limits.
- [Parnas, “On the Criteria To Be Used in Decomposing Systems into Modules” (1972)](https://doi.org/10.1145/361598.361623): prefer information-hiding module boundaries over automatically decomposing a system by processing step.
- [Lee and Parks, “Dataflow Process Networks” (1995)](https://ptolemy.berkeley.edu/publications/papers/95/processNets/): treat runtime dataflow as a formal network model with actors, FIFO channels, and execution semantics, not as a visual synonym for a chain.

### Program comprehension evidence

- [Heltweg, Schwarz, and Riehle, “Can a domain-specific language improve program structure comprehension of data pipelines?” (2026)](https://link.springer.com/article/10.1007/s10664-025-10746-7): an explicit pipeline DSL improved structural correctness, but not speed or perceived difficulty, for 57 non-professional programmers.
- [Alharbi and Kolovos, “Exploring the Impact of Source Code Linearity...” (2024)](https://eprints.whiterose.ac.uk/id/eprint/218768/1/ICPC_2024_ERA_Paper.pdf): locally linear Java API examples generally reduced response time in a 61-participant experiment without a broad correctness advantage.
- [Cates, Yunik, and Feitelson, “Does Code Structure Affect Comprehension?” (2021)](https://arxiv.org/abs/2103.11008): meaningful intermediate variables helped most in the hardest case; meaningless temporaries could add noise.
- [Salvaneschi et al., “An Empirical Study on Program Comprehension with Reactive Programming” (2014)](https://programming-group.com/assets/pdf/papers/2014_An-Empirical-Study-on-Program-Comprehension-with-Reactive-Programming.pdf): explicit reactive dependencies outperformed callback-oriented Observer implementations in a small student experiment.
- [Hofmeister, Siegmund, and Holt, “Shorter Identifier Names Take Longer to Comprehend” (2019)](https://www.se.cs.uni-saarland.de/publications/docs/HoSeHo17.pdf): 72 professional C# developers located defects about 19% faster with full-word identifiers than with letters or abbreviations.
- [Schankin et al., “Descriptive Compound Identifier Names Improve Source Code Comprehension” (2018)](https://brains-on-code.github.io/descriptive-compound-identifier-names.pdf): 88 Java developers found semantic defects about 14% faster with descriptive names; the effect disappeared for syntax-error search.
- [Börstler and Paech, “The Role of Method Chains and Comments...” (2016)](https://doi.org/10.1109/TSE.2016.2527791): a 104-student experiment found no overall readability or comprehension advantage from method chaining.
- [Zid et al., “A Study on the Pythonic Functional Constructs' Understandability” (2024)](https://mdipenta.github.io/files/ICSE24_funcExperiment.pdf): results for lambdas, comprehensions, and map/reduce/filter varied by construct and complexity; functional syntax was not inherently clearer.
- [Tempero et al., “On the Comprehensibility of Functional Decomposition” (2024)](https://juholeinonen.com/assets/pdf/tempero2024comprehensibility.pdf): decomposition helped one studied Java operation and hurt another, arguing against universal tiny-function rules.
- [Pennington, “Stimulus Structures and Mental Representations...” (1987)](https://www.cs.kent.edu/~jmaletic/cs69995-PC/papers/pennington87.pdf): professional programmers formed control-flow and later functional/dataflow representations according to the task.
- [Green, “Cognitive Dimensions of Notations” (1989)](https://www.cl.cam.ac.uk/~afb21/CognitiveDimensions/papers/Green1989.pdf): use visibility, hidden dependencies, viscosity, and related dimensions as tradeoff vocabulary, not causal proof.
- [Busjahn et al., “Eye Movements in Code Reading: Relaxing the Linear Order” (2015)](https://doi.org/10.1109/ICPC.2015.36): expert code reading was less linear than novice reading, cautioning against equating source order with actual navigation.
- [Wyrich, Bogner, and Wagner, “40 Years of Designing Code Comprehension Experiments” (2022)](https://arxiv.org/abs/2206.11102): comprehension experiments vary widely in tasks, measures, materials, and participants; generalize individual findings cautiously.

### Language and API traditions

- [Syme, “The Early History of F#,” §9.1](https://fsharp.org/history/hopl-final/hopl-fsharp.pdf) and [F# function documentation](https://learn.microsoft.com/en-us/dotnet/fsharp/language-reference/functions/): distinguish applying a value with `|>` from constructing a new function with composition.
- [Clojure Threading Macros Guide](https://clojure.org/guides/threading_macros): expose first-, last-, flexible-, optional-, and conditional-threading policies as different forms.
- [Elixir Enumerables and Streams](https://elixir.hexdocs.pm/enumerable-and-streams.html): distinguish eager `Enum` pipelines that materialize intermediates from lazy `Stream` pipelines.
- [R Forward Pipe Operator](https://stat.ethz.ch/R-manual/R-devel/RHOME/library/base/html/pipeOp.html) and [magrittr design tradeoffs](https://magrittr.tidyverse.org/articles/tradeoffs.html): see how pipe implementations affect laziness, evaluation count, lexical effects, stack shape, and debugging.
- [TC39 Pipeline Operator proposal](https://github.com/tc39/proposal-pipeline-operator): study the tradeoff between unary-function F# pipes and arbitrary-expression Hack pipes; neither adds runtime pipeline semantics.
- [Fowler, “Fluent Interface”](https://martinfowler.com/bliki/FluentInterface.html): design the entire call sequence as a domain-specific language; do not confuse fluency with chaining alone.

### Production semantics

- [Java Stream package documentation](https://docs.oracle.com/en/java/javase/17/docs/api/java.base/java/util/stream/package-summary.html): keep stream behaviors stateless and non-interfering; side effects may be reordered, run on different threads, or be elided.
- [Go, “Concurrency Patterns: Pipelines and cancellation”](https://go.dev/blog/pipelines): propagate cancellation so early downstream termination does not strand upstream goroutines.
- [Wlaschin, “Railway Oriented Programming”](https://fsharpforfunandprofit.com/rop/) and [“Against Railway-Oriented Programming”](https://fsharpforfunandprofit.com/posts/against-railway-oriented-programming/): compose expected domain failures while retaining exceptions and diagnostics for cases where `Result` is the wrong model.
- [Reactive Streams](https://www.reactive-streams.org/): make non-blocking backpressure part of the contract between asynchronous stages.
- [Enterprise Integration Patterns, “Pipes and Filters”](https://www.enterpriseintegrationpatterns.com/patterns/messaging/PipesAndFilters.html): compose independent message-processing steps behind a simple connector interface.
- [AWS, “Making retries safe with idempotent APIs”](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/): treat ambiguous completion and duplicate effects as first-class concerns across network boundaries.
- [Microsoft, “Saga distributed transactions pattern”](https://learn.microsoft.com/en-us/azure/architecture/patterns/saga): model a cross-service sequence as durable local transactions, retries, and compensations rather than false atomicity.
- [Coutts, Leshchinskiy, and Stewart, “Stream Fusion” (2007)](https://doi.org/10.1145/1291151.1291199): composition may allocate intermediates unless the runtime or compiler deliberately fuses them.
