{ overwriteHomeManagerBackups ? false, ... }:
{
  xdg.configFile."ghostty" = {
    source = ../../../home/.config/ghostty;
    recursive = true;
    force = overwriteHomeManagerBackups;
  };
}
