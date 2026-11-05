{ config, overwriteHomeManagerBackups ? false, ... }:
{
  # The Rex server reads init.lua but does not watch it, so reload a running
  # server after each change. The Rex app installs its CLI in ~/.local/bin.
  xdg.configFile."rex/init.lua" = {
    source = ../../../../home/.config/rex/init.lua;
    force = overwriteHomeManagerBackups;
    onChange = ''
      rex_bin="${config.home.homeDirectory}/.local/bin/rex"
      if [ -x "$rex_bin" ]; then
        "$rex_bin" config reload >/dev/null 2>&1 || true
      fi
      unset rex_bin
    '';
  };
}
