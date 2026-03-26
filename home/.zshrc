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

# The Codex spaces wrapper is sourced from ~/.config/zsh/functions/codex-spaces-wrapper.zsh.
