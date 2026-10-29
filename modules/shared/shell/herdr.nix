{ config, inputs, lib, overwriteHomeManagerBackups ? false, pkgs, platform, role, ... }:
let
  # On non-sandbox Darwin herdr comes from Homebrew; everywhere else it is
  # built from the herdr flake because nixpkgs does not package it.
  useNixPackage = platform == "linux" || role == "sandbox";
  herdrPackage = inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
  herdrCandidates =
    if useNixPackage then
      [ "${herdrPackage}/bin/herdr" ]
    else
      [
        "/opt/homebrew/bin/herdr"
        "/usr/local/bin/herdr"
      ];
  herdrCandidateArgs = pkgs.lib.concatMapStringsSep " " pkgs.lib.escapeShellArg herdrCandidates;
in
{
  home.packages = pkgs.lib.optionals useNixPackage [
    herdrPackage
  ];

  xdg.configFile."herdr/config.toml" = {
    source = ../../../home/.config/herdr/config.toml;
    force = overwriteHomeManagerBackups;
    # Apply config edits to an already-running server without starting one.
    onChange = ''
      for herdr_bin in ${herdrCandidateArgs}; do
        if [ -x "$herdr_bin" ]; then
          "$herdr_bin" server reload-config >/dev/null 2>&1 || true
          break
        fi
      done
      unset herdr_bin
    '';
  };

  # The Herdr desktop app (herdr-app) reloads keys.json and settings.json
  # itself whenever they change. Its other files are app-owned.
  xdg.configFile."herdr-app/keys.json" = {
    source = ../../../home/.config/herdr-app/keys.json;
    force = overwriteHomeManagerBackups;
  };

  # The app also writes settings.json (zoom keys, the Settings screen), so a
  # read-only link would break those. Copy it in on every activation instead:
  # in-app changes last until the next switch, then the repo version wins.
  home.activation.herdrAppSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    herdr_app_settings="${config.xdg.configHome}/herdr-app/settings.json"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$herdr_app_settings")"
    # Rename into place so the app's file watcher never reads a partial file.
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 ${../../../home/.config/herdr-app/settings.json} "$herdr_app_settings.tmp"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv -f "$herdr_app_settings.tmp" "$herdr_app_settings"
  '';
}
