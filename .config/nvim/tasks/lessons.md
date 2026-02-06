# Lessons

- **Don’t `require()` Vimscript-only plugins**
  - What went wrong: I configured `rhysd/accelerated-jk` with `require("accelerated-jk")`, but the plugin ships as Vimscript (no `lua/` module), so startup failed.
  - Guardrail: before calling `require("<plugin>")`, confirm the plugin actually provides `lua/<module>.lua` (or docs explicitly show a Lua API). Otherwise configure via `vim.g` and keymaps only.
