{
  home.file = let
    recursive = source: {
      inherit source;
      recursive = true;
    };
  in {
    ".vimrc".source = ../../home/.vimrc;

    ".claude/README.md".source = ../../home/.claude/README.md;
    ".claude/settings.json".source = ../../home/.claude/settings.json;
    ".claude/commands" = recursive ../../home/.claude/commands;
    ".claude/skills/frontend-design" = recursive ../../home/.claude/skills/frontend-design;
    ".claude/skills/gh-address-comments" = recursive ../../home/.claude/skills/gh-address-comments;
    ".claude/skills/gh-fix-ci" = recursive ../../home/.claude/skills/gh-fix-ci;
    ".claude/skills/gh-manage-pr" = recursive ../../home/.claude/skills/gh-manage-pr;
    ".claude/skills/programming" = recursive ../../home/.claude/skills/programming;
    ".claude/skills/sql-read" = recursive ../../home/.claude/skills/sql-read;
    ".claude/statusline-command.sh" = {
      source = ../../home/.claude/statusline-command.sh;
      executable = true;
    };
    ".claude/tmux-notify.sh" = {
      source = ../../home/.claude/tmux-notify.sh;
      executable = true;
    };

    ".codex/AGENTS.md".source = ../../home/.codex/AGENTS.md;
    ".codex/prompts" = recursive ../../home/.codex/prompts;
    ".codex/rules/base.rules".source = ../../home/.codex/rules/base.rules;
    ".codex/skills/atlas" = recursive ../../home/.codex/skills/atlas;
    ".codex/skills/frontend-design" = recursive ../../home/.codex/skills/frontend-design;
    ".codex/skills/gh-address-comments" = recursive ../../home/.codex/skills/gh-address-comments;
    ".codex/skills/gh-fix-ci" = recursive ../../home/.codex/skills/gh-fix-ci;
    ".codex/skills/gh-manage-pr" = recursive ../../home/.codex/skills/gh-manage-pr;
    ".codex/skills/notion-knowledge-capture" = recursive ../../home/.codex/skills/notion-knowledge-capture;
    ".codex/skills/programming" = recursive ../../home/.codex/skills/programming;
    ".codex/skills/sql-read" = recursive ../../home/.codex/skills/sql-read;
  };

  xdg.configFile = {
    "nvim" = {
      source = ../../home/.config/nvim;
      recursive = true;
    };
    "starship.toml".source = ../../home/.config/starship.toml;
    "zsh" = {
      source = ../../home/.config/zsh;
      recursive = true;
    };
  };
}
