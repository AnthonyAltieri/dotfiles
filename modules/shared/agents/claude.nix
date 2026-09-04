{ config, lib, pkgs, ... }:
let
  baseSettingsFile = ../../../home/.claude/settings.json;
  extraPlugins = config.dotfiles.claudeEnabledPlugins;

  # Roles add plugins on top of the tracked settings payload. When none are
  # declared, the raw file is deployed untouched so other roles stay
  # byte-identical to home/.claude/settings.json.
  mergedSettings =
    lib.recursiveUpdate (builtins.fromJSON (builtins.readFile baseSettingsFile)) {
      enabledPlugins = extraPlugins;
    };

  settingsSource =
    if extraPlugins == { } then
      baseSettingsFile
    else
      (pkgs.formats.json { }).generate "claude-settings.json" mergedSettings;
in
{
  options.dotfiles.claudeEnabledPlugins = lib.mkOption {
    type = lib.types.attrsOf lib.types.bool;
    default = { };
    example = { "slack@claude-plugins-official" = true; };
    description = ''
      Claude Code plugins enabled in addition to those in
      `home/.claude/settings.json`, keyed `<plugin>@<marketplace>`. Merged
      into `enabledPlugins` of the managed `~/.claude/settings.json`.
      Marketplaces other than the built-in `claude-plugins-official` must
      already be declared in `extraKnownMarketplaces`.
    '';
  };

  options.dotfiles.claudeSettingsSource = lib.mkOption {
    type = lib.types.path;
    readOnly = true;
    description = "Resolved source for the managed ~/.claude/settings.json.";
  };

  config = {
    dotfiles.claudeSettingsSource = settingsSource;

    home.sessionVariables = {
      CLAUDE_CONFIG_DIR = "$HOME/.claude";
    };
  };
}
