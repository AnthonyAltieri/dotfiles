# default editor
if (( $+commands[nvim] )) then
  export EDITOR=/usr/local/bin/nvim
else
  export EDITOR=/usr/local/bin/vim
fi

# Homebrew
if (( $+commands[brew] )); then
  eval "$(brew shellenv)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# path setup
export PATH="${HOME}/.cargo/bin:${PATH}"
export PATH="${HOME}/.local/bin:${PATH}"
export PATH="${HOME}/.poetry/bin:${PATH}"
export PATH="${PATH}:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# load other .zsh files
for f in ~/.config/zsh/features/*.zsh; do
  if [[ -r ${f} ]] ; then
    source "${f}"
  fi
done
for f in ~/.config/zsh/functions/*.zsh; do
  if [[ -r ${f} ]] ; then
    source "${f}"
  fi
done
unset f
if [[  "$(uname)" == "Darwin" ]]; then
  source ~/.config/zsh/os/config-osx.zsh
fi

# aliases
if (( $+commands[nvim] )) then
  alias vim=nvim
  alias vi=nvim
fi

alias gcb=git-current-branch
alias g=git
