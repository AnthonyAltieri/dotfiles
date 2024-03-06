return {
    -- "gc" to comment visual regions/lines
    { 'numToStr/Comment.nvim', opts = {} },
     -- Highlight todo, notes, etc in comments
    { 'folke/todo-comments.nvim', event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },
}