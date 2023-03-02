# Path to your oh-my-zsh installation.
export ZSH="/Users/$USER/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# IMPORTANT: This theme doesn't matter because we use starship
ZSH_THEME="robbyrussell"

# Plugins
# see README.md for plugin installation
plugins=(
  git 
  npm
  zsh-autosuggestions 
  # fast syntax highlighting
  F-Sy-H 
  z
)

source $ZSH/oh-my-zsh.sh
source ~/.config/zsh/config.zsh


# Environment 
export PATH="$HOME/.poetry/bin:$PATH"

# Start starship CLI https://starship.rs/
eval "$(starship init zsh)"

# Load nvm
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

# Start tmux automatically
if [ "$TMUX" = "" ]; then tmux; fi