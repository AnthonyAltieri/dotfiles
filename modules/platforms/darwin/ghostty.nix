{ overwriteHomeManagerBackups ? false, ... }:
let
  ghosttyConfig = {
    source = ../../../home/.config/ghostty;
    recursive = true;
    force = overwriteHomeManagerBackups;
  };
in
{
  xdg.configFile."ghostty" = ghosttyConfig;

  home.file."Library/Application Support/com.mitchellh.ghostty" = ghosttyConfig;
}
