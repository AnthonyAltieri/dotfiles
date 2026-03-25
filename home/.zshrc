source ~/.config/zsh/config.zsh

# Start starship CLI https://starship.rs/
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

# Load nvm. Prefer the Homebrew install on macOS, but keep the legacy
# per-user layout as a fallback until all machines converge on Nix.
export NVM_DIR="$HOME/.nvm"
if command -v brew >/dev/null 2>&1; then
  NVM_PREFIX="$(brew --prefix nvm 2>/dev/null || true)"
  if [[ -n "$NVM_PREFIX" && -s "$NVM_PREFIX/nvm.sh" ]]; then
    . "$NVM_PREFIX/nvm.sh"
    [[ -s "$NVM_PREFIX/etc/bash_completion.d/nvm" ]] && . "$NVM_PREFIX/etc/bash_completion.d/nvm"
  elif [[ -s "$NVM_DIR/nvm.sh" ]]; then
    . "$NVM_DIR/nvm.sh"
    [[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"
  fi
elif [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"
fi


# pnpm
if [[ "$(uname)" == "Darwin" ]]; then
  export PNPM_HOME="$HOME/Library/pnpm"
else
  export PNPM_HOME="$HOME/.local/share/pnpm"
fi
path=("$PNPM_HOME" "${(@)path:#$PNPM_HOME}")
export PATH
# pnpm end

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# Load ~/.env if it exists and has valid syntax
if [[ -f "${HOME}/.env" ]]; then
  if zsh -n "${HOME}/.env" 2>/dev/null; then
    set -o allexport
    source "${HOME}/.env"
    set +o allexport
  else
    echo "[.zshrc] Warning: ~/.env has invalid syntax, skipping"
  fi
fi

# WarpStream
export PATH="$HOME/.warpstream:$PATH"

# Codex + spaces shortcuts
# Supported shell-only flags:
#   --yorkspace / --yorktree
#   --gorkspace / --gorktree
#   --sorkspace / --sorktree
# With optional suffixes:
#   -fork <session-id|--last> [repos...]
#   -open <space|space:repo|path>
#   -refork <session-id|--last> <space|space:repo|path>
#
# Repo args stop at `--`; any args after that are forwarded to the real Codex CLI.
# Examples:
#   codex --gorktree
#   codex --gorkspace infra webapps-infra -- --model gpt-5.4
#   codex --gorktree-open jolly-anchor
#   codex --gorktree-open jolly-anchor:infra
#   codex --gorktree-fork --last

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
    york) reply=() ;;
    gork) reply=(-s workspace-write -a on-request -c 'sandbox_workspace_write.network_access=true') ;;
    sork) reply=(-s workspace-write -a never -c 'sandbox_workspace_write.network_access=true') ;;
    *)
      print -u2 "codex spaces wrapper: unknown mode: $1"
      return 1
      ;;
  esac
}

_codex_space_target_from_json() {
  local space_json="$1"
  local repo="$2"

  if [[ -n "$repo" ]]; then
    printf '%s\n' "$space_json" |
      jq -r --arg repo "$repo" '.repos[] | select(.repo_name == $repo) | .worktree_path'
    return
  fi

  printf '%s\n' "$space_json" |
    jq -r 'if (.repos | length) == 1 then .repos[0].worktree_path else .workspace_dir end'
}

_codex_space_target_dir() {
  local target="$1"
  local space repo space_json
  local -a base_args

  if [[ -d "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  _codex_spaces_base_args || return 1
  base_args=("${reply[@]}")

  if [[ "$target" == *:* ]]; then
    space="${target%%:*}"
    repo="${target#*:}"
  else
    space="$target"
    repo=""
  fi

  space_json="$(spaces show "${base_args[@]}" "$space" --json)" || return 1
  _codex_space_target_from_json "$space_json" "$repo"
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
  local cmd shortcut flavor action mode target sid target_dir space_json
  local -a mode_args wrapper_args codex_args repos

  cmd="$1"

  case "$cmd" in
    --yorkspace*|--gorkspace*|--sorkspace*|--yorktree*|--gorktree*|--sorktree*) ;;
    *)
      command codex "$@"
      return
      ;;
  esac

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

  shortcut="${cmd#--}"
  flavor="${shortcut%%-*}"
  action="${shortcut#"$flavor"}"
  action="${action#-}"

  case "$flavor" in
    yorkspace|yorktree) mode="york" ;;
    gorkspace|gorktree) mode="gork" ;;
    sorkspace|sorktree) mode="sork" ;;
    *)
      print -u2 "codex spaces wrapper: unknown shortcut: $cmd"
      return 2
      ;;
  esac

  _codex_mode_args "$mode" || return 1
  mode_args=("${reply[@]}")

  case "$action" in
    '')
      repos=("${wrapper_args[@]}")
      space_json="$(_codex_new_space_json "${repos[@]}")" || return 1
      target_dir="$(_codex_space_target_from_json "$space_json" "")" || return 1
      [[ -n "$target_dir" && -d "$target_dir" ]] || {
        print -u2 "codex spaces wrapper: failed to resolve new space target"
        return 1
      }
      command codex -C "$target_dir" "${mode_args[@]}" "${codex_args[@]}"
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
      target_dir="$(_codex_space_target_from_json "$space_json" "")" || return 1
      [[ -n "$target_dir" && -d "$target_dir" ]] || {
        print -u2 "codex spaces wrapper: failed to resolve new space target"
        return 1
      }
      command codex fork "$sid" -C "$target_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    open)
      target="${wrapper_args[1]}"
      [[ -n "$target" ]] || {
        print -u2 "usage: codex $cmd <space|space:repo|path> [-- extra-codex-args...]"
        return 2
      }
      target_dir="$(_codex_space_target_dir "$target")" || return 1
      [[ -n "$target_dir" && -d "$target_dir" ]] || {
        print -u2 "codex spaces wrapper: target not found: $target"
        return 1
      }
      command codex -C "$target_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    refork)
      sid="${wrapper_args[1]}"
      target="${wrapper_args[2]}"
      [[ -n "$sid" && -n "$target" ]] || {
        print -u2 "usage: codex $cmd <session-id|--last> <space|space:repo|path> [-- extra-codex-args...]"
        return 2
      }
      target_dir="$(_codex_space_target_dir "$target")" || return 1
      [[ -n "$target_dir" && -d "$target_dir" ]] || {
        print -u2 "codex spaces wrapper: target not found: $target"
        return 1
      }
      command codex fork "$sid" -C "$target_dir" "${mode_args[@]}" "${codex_args[@]}"
      ;;
    *)
      print -u2 "codex spaces wrapper: unsupported shortcut: $cmd"
      return 2
      ;;
  esac
}
