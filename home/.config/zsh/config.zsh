if [[ "$(uname)" == "Darwin" ]]; then
  export PATH="${PATH}:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
fi

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
if [[ "$(uname)" == "Darwin" ]] && [[ -r ~/.config/zsh/os/config-osx.zsh ]]; then
  source ~/.config/zsh/os/config-osx.zsh
fi

# aliases
if (( $+commands[nvim] )) then
  alias vim=nvim
  alias vi=nvim
fi
export VISUAL="${EDITOR}"

alias gcb=git-current-branch
alias g=git
