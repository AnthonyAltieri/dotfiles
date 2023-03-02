#!/bin/zsh

# update before anything
brew update

# install regular suff
brew install starship tmux

# install nerd fonts
brew tap homebrew/cask-fonts && brew install --cask font-fira-code-nerd-font
