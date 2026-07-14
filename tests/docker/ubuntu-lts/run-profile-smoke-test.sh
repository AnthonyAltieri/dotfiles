#!/usr/bin/env bash
set -euo pipefail

profile="${1:-}"

host_arch="$(uname -m)"
case "${host_arch}" in
  arm64|aarch64)
    linux_suffix="aarch64-linux"
    ;;
  x86_64|amd64)
    linux_suffix="x86_64-linux"
    ;;
  *)
    echo "Unsupported container architecture: ${host_arch}" >&2
    exit 1
    ;;
esac

resolve_profile_output() {
  local requested_profile="$1"
  case "${requested_profile}" in
    personal)
      if [[ "${linux_suffix}" == "aarch64-linux" ]]; then
        echo "personal-aarch64-linux"
      else
        echo "personal-linux"
      fi
      ;;
    work)
      if [[ "${linux_suffix}" == "aarch64-linux" ]]; then
        echo "work-aarch64-linux"
      else
        echo "work-linux"
      fi
      ;;
    sandbox)
      echo "sandbox-${linux_suffix}"
      ;;
    personal-linux|personal-aarch64-linux|work-linux|work-aarch64-linux|sandbox-x86_64-linux|sandbox-aarch64-linux)
      echo "${requested_profile}"
      ;;
    *)
      echo "" >&2
      return 1
      ;;
  esac
}

profile_output="$(resolve_profile_output "${profile}")" || {
  echo "Usage: $0 <personal|work|sandbox>" >&2
  echo "       or $0 <personal-linux|personal-aarch64-linux|work-linux|work-aarch64-linux|sandbox-x86_64-linux|sandbox-aarch64-linux>" >&2
  exit 1
}

case "$profile_output" in
  personal-linux|personal-aarch64-linux|work-linux|work-aarch64-linux|sandbox-x86_64-linux|sandbox-aarch64-linux)
    ;;
  *)
    echo "Resolved unsupported profile output: ${profile_output}" >&2
    exit 1
    ;;
esac

source "$HOME/.nix-profile/etc/profile.d/nix.sh"

assert_jq() {
  local filter="$1"
  local message="$2"
  if ! jq -e "$filter" >/dev/null <<<"$summary"; then
    echo "$message" >&2
    exit 1
  fi
}

assert_work_notion_mcp_enabled() {
  assert_jq '.activationEntries | index("workCodexNotionMcp") != null' "Expected work Notion MCP activation entry"
  assert_jq '.workCodexNotionMcpScript | contains("https://mcp.notion.com/mcp")' "Expected Notion MCP URL in work activation entry"
  assert_jq '.workCodexNotionMcpScript | contains("rmcp_client")' "Expected rmcp_client in work activation entry"
}

assert_work_notion_mcp_disabled() {
  assert_jq '.activationEntries | index("workCodexNotionMcp") == null' "Did not expect work Notion MCP activation entry"
}

cd /work

summary="$(nix eval --impure --json --no-write-lock-file --expr '
let
  flake = builtins.getFlake "path:/work";
  hm = flake.homeConfigurations.'"${profile_output}"';
  cfg = hm.config;
  packageName = pkg:
    if pkg ? pname then pkg.pname
    else if pkg ? name then pkg.name
    else "<unknown>";
in {
  files = builtins.attrNames cfg.home.file;
  xdgFiles = builtins.attrNames cfg.xdg.configFile;
  activationEntries = builtins.attrNames cfg.home.activation;
  workCodexNotionMcpScript = cfg.home.activation.workCodexNotionMcp.data or "";
  agentManagedCopies = map (entry: {
    target = entry.target;
    kind = entry.kind;
    executable = entry.executable;
    source = toString entry.source;
  }) cfg.dotfiles.agentManagedCopies;
  agentManagedTargets = map (entry: entry.target) cfg.dotfiles.agentManagedCopies;
  ohMyZsh = cfg.programs.zsh."oh-my-zsh".enable or false;
  sessionVariables = cfg.home.sessionVariables;
  packages = map packageName cfg.home.packages;
  tmuxEnabled = cfg.programs.tmux.enable or false;
  zshEnabled = cfg.programs.zsh.enable or false;
}')"

assert_jq '.zshEnabled == true' "Expected zsh to be enabled"
assert_jq '.tmuxEnabled == true' "Expected tmux to be enabled"
assert_jq '.xdgFiles | index("zsh") != null' "Expected ~/.config/zsh to be managed"
assert_jq '.xdgFiles | index("nvim") != null' "Expected ~/.config/nvim to be managed"
assert_jq '.xdgFiles | index("starship.toml") != null' "Expected starship config to be managed"
assert_jq '.agentManagedTargets | index(".codex/AGENTS.md") != null' "Expected Codex config to be managed"
assert_jq '.agentManagedTargets | index(".codex/skills/adversarial-review") != null' "Expected Codex adversarial-review skill to be managed"
assert_jq '[.agentManagedCopies[] | select(.target == ".codex/skills/adversarial-review")] | length == 1' "Expected exactly one Codex adversarial-review managed copy"
assert_jq '.agentManagedTargets | index(".codex/skills/handoff") != null' "Expected Codex handoff skill to be managed"
assert_jq '.agentManagedTargets | index(".codex/skills/improve-codebase-architecture") != null' "Expected Codex improve-codebase-architecture skill to be managed"
assert_jq '.agentManagedTargets | index(".codex/skills/linear-claim-work") != null' "Expected Codex linear-claim-work skill to be managed"
assert_jq '.agentManagedTargets | index(".claude/settings.json") != null' "Expected Claude settings to be managed"
assert_jq '.agentManagedTargets | index(".claude/skills/adversarial-review") == null' "Did not expect Claude adversarial-review skill to be managed"
assert_jq '.agentManagedTargets | index(".claude/skills/handoff") != null' "Expected Claude handoff skill to be managed"
assert_jq '.agentManagedTargets | index(".claude/skills/improve-codebase-architecture") != null' "Expected Claude improve-codebase-architecture skill to be managed"
assert_jq '.agentManagedTargets | index(".claude/skills/linear-claim-work") == null' "Did not expect Claude linear-claim-work skill to be managed"
assert_jq '.files | index(".vimrc") != null' "Expected ~/.vimrc to be managed"
assert_jq '.packages | index("git") != null' "Expected git in home.packages"
assert_jq '.packages | index("jq") != null' "Expected jq in home.packages"
assert_jq '.packages | index("bun") != null' "Expected bun in home.packages"
assert_jq '.packages | index("pnpm") != null' "Expected pnpm in home.packages"
assert_jq '.packages | index("fd") != null' "Expected fd in home.packages"
assert_jq '.packages | index("ripgrep") != null' "Expected ripgrep in home.packages"
assert_jq '.packages | index("neovim") != null' "Expected neovim in home.packages"
assert_jq '.packages | index("starship") != null' "Expected starship in home.packages"
assert_jq '.packages | index("vim") != null' "Expected vim in home.packages"

adversarial_review_source="$(jq -er '.agentManagedCopies[] | select(.target == ".codex/skills/adversarial-review") | .source' <<<"$summary")"
if [[ ! -f "$adversarial_review_source/SKILL.md" || ! -f "$adversarial_review_source/agents/openai.yaml" ]]; then
  echo "Expected complete Codex adversarial-review source payload" >&2
  exit 1
fi

if ! grep -Fq 'name: adversarial-review' "$adversarial_review_source/SKILL.md"; then
  echo "Expected Codex adversarial-review source identity" >&2
  exit 1
fi

if ! grep -Fq 'allow_implicit_invocation: false' "$adversarial_review_source/agents/openai.yaml"; then
  echo "Expected Codex adversarial-review source to require explicit invocation" >&2
  exit 1
fi

if jq -e '.sessionVariables.DOTFILES_COMMON == "1"' >/dev/null <<<"$summary"; then
  assert_jq '.packages | index("docker") != null' "Expected docker in home.packages for common roles"
fi

case "$profile" in
  personal)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "personal"' "Expected DOTFILES_PROFILE=personal"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for personal"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for personal"
    assert_jq '.packages | index("cargo") != null' "Expected cargo in home.packages for personal"
    assert_jq '.packages | index("rustc") != null' "Expected rustc in home.packages for personal"
    assert_jq '.agentManagedTargets | index(".codex/skills/observe") == null' "Did not expect Codex observe skill for personal"
    assert_jq '.agentManagedTargets | index(".claude/skills/observe") == null' "Did not expect Claude observe skill for personal"
    assert_work_notion_mcp_disabled
    ;;
  work)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "work"' "Expected DOTFILES_PROFILE=work"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for work"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for work"
    assert_jq '.packages | index("cargo") != null' "Expected cargo in home.packages for work"
    assert_jq '.packages | index("rustc") != null' "Expected rustc in home.packages for work"
    assert_jq '.agentManagedTargets | index(".codex/skills/observe") != null' "Expected Codex observe skill for work"
    assert_jq '.agentManagedTargets | index(".claude/skills/observe") != null' "Expected Claude observe skill for work"
    assert_work_notion_mcp_enabled
    ;;
  sandbox)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "sandbox"' "Expected DOTFILES_PROFILE=sandbox"
    assert_jq '.sessionVariables.CODEX_SANDBOX == "1"' "Expected CODEX_SANDBOX=1 for sandbox"
    assert_jq '(.sessionVariables | has("DOTFILES_COMMON")) | not' "Did not expect DOTFILES_COMMON for sandbox"
    assert_jq '.ohMyZsh == false' "Did not expect Oh My Zsh for sandbox"
    assert_jq '.packages | index("cargo") == null' "Did not expect cargo in home.packages for sandbox"
    assert_jq '.packages | index("rustc") == null' "Did not expect rustc in home.packages for sandbox"
    assert_jq '.agentManagedTargets | index(".codex/skills/observe") == null' "Did not expect Codex observe skill for sandbox"
    assert_jq '.agentManagedTargets | index(".claude/skills/observe") == null' "Did not expect Claude observe skill for sandbox"
    assert_work_notion_mcp_disabled
    ;;
  personal-linux|personal-aarch64-linux)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "personal"' "Expected DOTFILES_PROFILE=personal"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for personal-linux"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for personal-linux"
    assert_jq '.packages | index("cargo") != null' "Expected cargo in home.packages for personal-linux"
    assert_jq '.packages | index("rustc") != null' "Expected rustc in home.packages for personal-linux"
    assert_jq '.agentManagedTargets | index(".codex/skills/observe") == null' "Did not expect Codex observe skill for personal-linux"
    assert_jq '.agentManagedTargets | index(".claude/skills/observe") == null' "Did not expect Claude observe skill for personal-linux"
    assert_work_notion_mcp_disabled
    ;;
  work-linux|work-aarch64-linux)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "work"' "Expected DOTFILES_PROFILE=work"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for work-linux"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for work-linux"
    assert_jq '.packages | index("cargo") != null' "Expected cargo in home.packages for work-linux"
    assert_jq '.packages | index("rustc") != null' "Expected rustc in home.packages for work-linux"
    assert_jq '.agentManagedTargets | index(".codex/skills/observe") != null' "Expected Codex observe skill for work-linux"
    assert_jq '.agentManagedTargets | index(".claude/skills/observe") != null' "Expected Claude observe skill for work-linux"
    assert_work_notion_mcp_enabled
    ;;
  sandbox-x86_64-linux|sandbox-aarch64-linux)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "sandbox"' "Expected DOTFILES_PROFILE=sandbox"
    assert_jq '.sessionVariables.CODEX_SANDBOX == "1"' "Expected CODEX_SANDBOX=1 for sandbox Linux"
    assert_jq '(.sessionVariables | has("DOTFILES_COMMON")) | not' "Did not expect DOTFILES_COMMON for sandbox Linux"
    assert_jq '.ohMyZsh == false' "Did not expect Oh My Zsh for sandbox Linux"
    assert_jq '.packages | index("cargo") == null' "Did not expect cargo in home.packages for sandbox Linux"
    assert_jq '.packages | index("rustc") == null' "Did not expect rustc in home.packages for sandbox Linux"
    assert_jq '.agentManagedTargets | index(".codex/skills/observe") == null' "Did not expect Codex observe skill for sandbox Linux"
    assert_jq '.agentManagedTargets | index(".claude/skills/observe") == null' "Did not expect Claude observe skill for sandbox Linux"
    assert_work_notion_mcp_disabled
    ;;
esac

if [[ "${FULL_ACTIVATE:-0}" == "1" ]]; then
  rm -f result
  nix --extra-experimental-features "nix-command flakes" build --impure --no-write-lock-file ".#homeConfigurations.${profile_output}.activationPackage"
  ./result/activate

  for path in \
    "$HOME/.codex/AGENTS.md" \
    "$HOME/.codex/skills/adversarial-review/SKILL.md" \
    "$HOME/.codex/skills/adversarial-review/agents/openai.yaml" \
    "$HOME/.codex/skills/linear-claim-work/SKILL.md" \
    "$HOME/.codex/skills/programming/SKILL.md" \
    "$HOME/.claude/settings.json" \
    "$HOME/.claude/commands/pr.md"
  do
    if [[ ! -e "$path" ]]; then
      echo "Expected copied agent file to exist: ${path}" >&2
      exit 1
    fi

    if [[ -L "$path" ]]; then
      echo "Expected copied agent file to be a real file: ${path}" >&2
      exit 1
    fi
  done

  if ! grep -Fq 'name: adversarial-review' "$HOME/.codex/skills/adversarial-review/SKILL.md"; then
    echo "Expected installed Codex adversarial-review skill identity" >&2
    exit 1
  fi

  if ! grep -Fq 'allow_implicit_invocation: false' "$HOME/.codex/skills/adversarial-review/agents/openai.yaml"; then
    echo "Expected installed Codex adversarial-review skill to require explicit invocation" >&2
    exit 1
  fi

  if [[ -e "$HOME/.claude/skills/adversarial-review" || -L "$HOME/.claude/skills/adversarial-review" ]]; then
    echo "Did not expect Claude adversarial-review skill to be installed" >&2
    exit 1
  fi

  case "$profile_output" in
    work-linux|work-aarch64-linux)
      if [[ ! -f "$HOME/.codex/config.toml" ]]; then
        echo "Expected work profile activation to create Codex config.toml" >&2
        exit 1
      fi

      if ! grep -Fq 'rmcp_client = true' "$HOME/.codex/config.toml"; then
        echo "Expected work profile activation to enable rmcp_client" >&2
        exit 1
      fi

      if ! grep -Fq 'url = "https://mcp.notion.com/mcp"' "$HOME/.codex/config.toml"; then
        echo "Expected work profile activation to configure Notion MCP URL" >&2
        exit 1
      fi
      ;;
  esac
fi

echo "Smoke test passed for ${profile} (${profile_output})"
