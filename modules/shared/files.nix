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
    ".claude/skills/atlas" = recursive ../../home/.claude/skills/atlas;
    ".claude/skills/frontend-design" = recursive ../../home/.claude/skills/frontend-design;
    ".claude/skills/gh-address-comments" = recursive ../../home/.claude/skills/gh-address-comments;
    ".claude/skills/gh-fix-ci" = recursive ../../home/.claude/skills/gh-fix-ci;
    ".claude/skills/gh-manage-pr" = recursive ../../home/.claude/skills/gh-manage-pr;
    ".claude/skills/notion-knowledge-capture" = recursive ../../home/.claude/skills/notion-knowledge-capture;
    ".claude/skills/programming" = recursive ../../home/.claude/skills/programming;
    ".claude/skills/spaces" = recursive ../../home/.claude/skills/spaces;
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
    ".agents/skills/atlas" = recursive ../../home/.codex/skills/atlas;
    ".agents/skills/frontend-design" = recursive ../../home/.codex/skills/frontend-design;
    ".agents/skills/gh-address-comments" = recursive ../../home/.codex/skills/gh-address-comments;
    ".agents/skills/gh-fix-ci" = recursive ../../home/.codex/skills/gh-fix-ci;
    ".agents/skills/gh-manage-pr" = recursive ../../home/.codex/skills/gh-manage-pr;
    ".agents/skills/notion-knowledge-capture" = recursive ../../home/.codex/skills/notion-knowledge-capture;
    ".agents/skills/programming" = recursive ../../home/.codex/skills/programming;
    ".agents/skills/spaces" = recursive ../../home/.codex/skills/spaces;
    ".agents/skills/sql-read" = recursive ../../home/.codex/skills/sql-read;
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
