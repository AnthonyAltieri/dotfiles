let &t_SI = "\<Esc>]50;CursorShape=1\x7"
let &t_SR = "\<Esc>]50;CursorShape=2\x7"
let &t_EI = "\<Esc>]50;CursorShape=0\x7"

" Split window
nmap ss :split<Return><C-w>w
nmap sv :vsplit<Return><C-w>w
" Move window
map <C-h> <C-w>h
map <C-k> <C-w>k
map <C-j> <C-w>j
map <C-l> <C-w>l
" Switch tab
nmap <S-Tab> :tabprev<Return>
nmap <Tab> :tabnext<Return>
" Navigate
map <C-d> <C-d>zz
map <C-u> <C-u>zz

""" always show status line
set laststatus=2

""" use OS clipboard
set clipboard+=unnamedplus

set title
set noshowcmd
set noruler
set tabstop=2
set number
set relativenumber
set nohlsearch
set incsearch
set scrolloff=8

syntax on

