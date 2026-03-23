# Mcfly
if (( $+commands[mcfly] )) then
  eval "$(mcfly init zsh)"
  # use vim bindings instead of emacs (gross)
  export MCFLY_KEY_SCHEME=vim
  # enable fuzzy search
  export MCFLY_FUZZY=true
fi

