-- This file can be loaded by calling `lua require('plugins')` from your init.vim

-- Only required if you have packer configured as `opt`
vim.cmd [[packadd packer.nvim]]

return require('packer').startup(function(use)
  -- Packer can manage itself
  use 'wbthomason/packer.nvim'

  use "nvim-lua/plenary.nvim" -- essential utils required by most other plugins

  -- Theme
  -- use({
  --   'rose-pine/neovim',
  --   as = 'rose-pine',
  --   config = function()
  -- 	  vim.cmd('colorscheme rose-pine')
  --   end
  -- })
  use({
    'ellisonleao/gruvbox.nvim',
    as = 'gruvbox',
    config = function()
      vim.cmd('colorscheme gruvbox')
    end
  })



  ---------
  -- LSP --
  ---------
  -- LSP Support
  use 'neovim/nvim-lspconfig' -- LSP
  -- Syntax Highlighting
  use {
    'nvim-treesitter/nvim-treesitter',
    run = function() require('nvim-treesitter.install').update({ with_sync = true }) end,
  }
  use("nvim-treesitter/playground")
  use 'jose-elias-alvarez/null-ls.nvim' -- Use Neovim as a language server to inject LSP diagnostics, code actions, and more via Lua
  -- LSP language installation
  use 'williamboman/mason.nvim'
  use 'williamboman/mason-lspconfig.nvim'
  -- Autocompletion
  use 'hrsh7th/nvim-cmp'     -- Completion
  use 'hrsh7th/cmp-buffer'   -- nvim-cmp source for buffer words
  use 'hrsh7th/cmp-path'     -- nvim-cmp source for filesystem paths
  use 'hrsh7th/cmp-nvim-lsp' -- nvim-cmp source for neovim's built-in LSP
  use 'hrsh7th/cmp-nvim-lua' -- nvim-cmp source for lua
  -- LSP UI
  use 'onsails/lspkind-nvim' -- vscode-like pictograms
  use({
    "glepnir/lspsaga.nvim",
    requires = {
      { "nvim-tree/nvim-web-devicons" },
      --Please make sure you install markdown and markdown_inline parser
      { "nvim-treesitter/nvim-treesitter" }
    }
  }) -- LSP UI


  ----------------
  -- Auto-Pairs --
  ----------------
  use 'windwp/nvim-autopairs'  -- automatic closing pair symbols
  use 'windwp/nvim-ts-autotag' -- automatic closing tags (ie. html, react)

  ----------------
  -- Commenting --
  ----------------
  -- comment selected code with a keypress
  use { 'numToStr/Comment.nvim',
    requires = { 'JoosepAlviste/nvim-ts-context-commentstring' }
  }

  ------------
  -- Colors --
  ------------
  use 'norcalli/nvim-colorizer.lua' -- show colors inline over hex codes


  ----------------
  -- Navigation --
  ----------------
  --use 'theprimeagen/harpoon'
  use 'nvim-telescope/telescope.nvim'
  use 'nvim-telescope/telescope-file-browser.nvim'


  ------------
  -- Others --
  ------------
  use("mbbill/undotree") -- show local history (without git)

  use({
    "christoomey/vim-tmux-navigator",
    lazy = false
  }) -- navigate between tmux and vim
end)
