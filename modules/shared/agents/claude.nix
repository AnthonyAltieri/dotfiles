{ config, lib, pkgs, ... }:
let
  baseSettingsFile = ../../../home/.claude/settings.json;
  extraPlugins = config.dotfiles.claudeEnabledPlugins;
  autoMode = config.dotfiles.claudeAutoMode;

  # Roles add plugins and auto mode rules on top of the tracked settings
  # payload. When none are declared, the raw file is deployed untouched so
  # other roles stay byte-identical to home/.claude/settings.json.
  mergedSettings =
    lib.recursiveUpdate (builtins.fromJSON (builtins.readFile baseSettingsFile)) (
      { enabledPlugins = extraPlugins; }
      // lib.optionalAttrs (autoMode != { }) {
        # "$defaults" keeps Claude Code's built-in entries in each section.
        autoMode = lib.mapAttrs (_section: entries: [ "$defaults" ] ++ entries) autoMode;
      }
    );

  settingsSource =
    if extraPlugins == { } && autoMode == { } then
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

  options.dotfiles.claudeAutoMode = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    example = { environment = [ "Trusted repos: github.com/me/*" ]; };
    description = ''
      Auto mode classifier entries by section (`environment`, `allow`,
      `soft_deny`), each written as plain-English rules into `autoMode` of
      the managed `~/.claude/settings.json`. Every section keeps the built-in
      entries through a leading `"$defaults"`. Claude Code reads `autoMode`
      only from user, managed, or `--settings` settings, never from a
      project's `.claude/settings.json`.
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
