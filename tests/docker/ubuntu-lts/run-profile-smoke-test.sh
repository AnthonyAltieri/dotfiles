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
assert_jq '.files | index(".codex/AGENTS.md") != null' "Expected Codex config to be managed"
assert_jq '.files | index(".claude/settings.json") != null' "Expected Claude settings to be managed"
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

case "$profile" in
  personal)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "personal"' "Expected DOTFILES_PROFILE=personal"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for personal"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for personal"
    ;;
  work)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "work"' "Expected DOTFILES_PROFILE=work"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for work"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for work"
    ;;
  sandbox)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "sandbox"' "Expected DOTFILES_PROFILE=sandbox"
    assert_jq '.sessionVariables.CODEX_SANDBOX == "1"' "Expected CODEX_SANDBOX=1 for sandbox"
    assert_jq '(.sessionVariables | has("DOTFILES_COMMON")) | not' "Did not expect DOTFILES_COMMON for sandbox"
    assert_jq '.ohMyZsh == false' "Did not expect Oh My Zsh for sandbox"
    ;;
  personal-linux|personal-aarch64-linux)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "personal"' "Expected DOTFILES_PROFILE=personal"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for personal-linux"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for personal-linux"
    ;;
  work-linux|work-aarch64-linux)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "work"' "Expected DOTFILES_PROFILE=work"
    assert_jq '.sessionVariables.DOTFILES_COMMON == "1"' "Expected DOTFILES_COMMON=1 for work-linux"
    assert_jq '.ohMyZsh == true' "Expected Oh My Zsh for work-linux"
    ;;
  sandbox-x86_64-linux|sandbox-aarch64-linux)
    assert_jq '.sessionVariables.DOTFILES_PROFILE == "sandbox"' "Expected DOTFILES_PROFILE=sandbox"
    assert_jq '.sessionVariables.CODEX_SANDBOX == "1"' "Expected CODEX_SANDBOX=1 for sandbox Linux"
    assert_jq '(.sessionVariables | has("DOTFILES_COMMON")) | not' "Did not expect DOTFILES_COMMON for sandbox Linux"
    assert_jq '.ohMyZsh == false' "Did not expect Oh My Zsh for sandbox Linux"
    ;;
esac

if [[ "${FULL_ACTIVATE:-0}" == "1" ]]; then
  rm -f result
  nix --extra-experimental-features "nix-command flakes" build --no-write-lock-file ".#homeConfigurations.${profile_output}.activationPackage"
  ./result/activate
fi

echo "Smoke test passed for ${profile} (${profile_output})"
