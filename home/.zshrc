source ~/.config/zsh/config.zsh

# Free Ctrl+S/Ctrl+Q for terminal apps such as Neovim and herdr instead of
# letting the TTY line discipline treat them as XON/XOFF flow control.
if [[ -o interactive ]] && [[ -t 0 ]]; then
  stty -ixon 2>/dev/null
fi

# Start starship CLI https://starship.rs/
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

# Load nvm as the interactive Node owner. Prefer Homebrew on macOS and retain
# the standard per-user layout as a fallback on machines without Homebrew.
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

if (( $+functions[nvm] )); then
  autoload -Uz add-zsh-hook

  _dotfiles_find_node_version_file() {
    local search_dir="$PWD"

    while [[ -n "$search_dir" ]]; do
      if [[ -f "$search_dir/.nvmrc" ]]; then
        print -r -- "$search_dir/.nvmrc"
        return 0
      fi

      if [[ -f "$search_dir/.node-version" ]]; then
        print -r -- "$search_dir/.node-version"
        return 0
      fi

      [[ "$search_dir" == "/" ]] && break
      search_dir="${search_dir:h}"
    done

    return 1
  }

  _dotfiles_use_project_node() {
    local version_file requested_version

    version_file="$(_dotfiles_find_node_version_file)" || return 0
    if [[ "${version_file:t}" == ".nvmrc" ]]; then
      nvm use --silent
      return
    fi

    IFS= read -r requested_version < "$version_file"
    if [[ -z "$requested_version" ]]; then
      print -u2 -- "nvm: $version_file is empty"
      return 1
    fi

    nvm use --silent "$requested_version"
  }

  add-zsh-hook chpwd _dotfiles_use_project_node
  _dotfiles_use_project_node
fi


# pnpm
if [[ "$(uname)" == "Darwin" ]]; then
  pnpm_home_default="$HOME/Library/pnpm"
else
  pnpm_home_default="$HOME/.local/share/pnpm"
fi

# Codex runs in a sandbox that cannot write to home-directory pnpm state.
# Keep the managed pnpm runtime out of $HOME, but share a stable store cache.
if [[ -n "${CODEX_SANDBOX:-}" || -n "${CODEX_CI:-}" ]]; then
  export PNPM_HOME="/tmp/pnpm-home"
  export NPM_CONFIG_STORE_DIR="/tmp/pnpm-store"
  path=("$pnpm_home_default" "$PNPM_HOME" "${(@)path:#$pnpm_home_default}" "${(@)path:#$PNPM_HOME}")
else
  export PNPM_HOME="$pnpm_home_default"
  unset NPM_CONFIG_STORE_DIR
  path=("$PNPM_HOME" "${(@)path:#$PNPM_HOME}")
fi

unset pnpm_home_default
export PATH
# pnpm end

# bun
export BUN_INSTALL="$HOME/.bun"
path=("$BUN_INSTALL/bin" "${(@)path:#$BUN_INSTALL/bin}")
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

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
