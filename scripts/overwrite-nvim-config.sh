#!/usr/bin/env bash

SCRIPT_DIRECTORY="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
DOTFILES_DIRECTORY="$( cd ${SCRIPT_DIRECTORY}/.. &> /dev/null && pwd)"
NVIM_DIRECTORY="$( cd ${DOTFILES_DIRECTORY}/.config/nvim &> /dev/null && pwd)"

rm -rf ~/.config/nvim
ln -s ${NVIM_DIRECTORY} ~/.config/nvim

