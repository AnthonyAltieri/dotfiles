#!/usr/bin/env bash

SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
DOTFILES_DIRECTORY="$( cd ${SCRIPT_DIRECTORY}/.. &> /dev/null && pwd)"
TMUX_CONF_PATH="${DOTFILES_DIRECTORY}/.tmux.conf"
TMUX_DIRECTORY="$( cd ${DOTFILES_DIRECTORY}/.config/tmux &> /dev/null && pwd)"

rm ~/.tmux.conf
rm -rf ~/.config/tmux
ln -s ${TMUX_CONF_PATH} ~/.tmux.conf
ln -s ${TMUX_DIRECTORY} ~/.config/tmux

