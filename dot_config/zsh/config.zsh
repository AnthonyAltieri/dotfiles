# default editor
if (( $+commands[nvim] )) then
  export EDITOR=/usr/local/bin/nvim
else
  export EDITOR=/usr/local/bin/vim
fi

# path setup
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

# load environment
if [[ -f "${HOME}/.env" ]]; then
  load-env-file "${HOME}/.env" > /dev/null
fi
 
# aliases
if (( $+commands[nvim] )) then
  alias vim=nvim
  alias vi=nvim
fi

alias gcb=git-current-branch
alias g=git

