# Put nvm's default Node on PATH for every zsh, including the non-interactive
# login shells that terminals such as Rex take their environment from when they
# start a program directly. Without it, a program such as Claude Code that Rex
# starts has no `node`, and its Node hooks fail. .zshrc still loads nvm itself,
# and `nvm use` there replaces this entry. Sourcing nvm.sh here would slow every
# zsh, so this only reads the default alias and picks the newest matching install.
() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}" wanted=""
  local -a bins
  [[ -r "$nvm_dir/alias/default" ]] && wanted="$(<"$nvm_dir/alias/default")"
  wanted="${wanted#v}"
  if [[ "$wanted" == [0-9]* ]]; then
    bins=("$nvm_dir"/versions/node/v${wanted}/bin(N/) "$nvm_dir"/versions/node/v${wanted}.*/bin(N/nOn))
  fi
  (( $#bins )) || bins=("$nvm_dir"/versions/node/v*/bin(N/nOn))
  (( $#bins )) && path=("$bins[1]" $path)
}
