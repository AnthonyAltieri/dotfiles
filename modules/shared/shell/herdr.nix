{ inputs, overwriteHomeManagerBackups ? false, pkgs, platform, role, ... }:
let
  # On non-sandbox Darwin herdr comes from Homebrew; everywhere else it is
  # built from the herdr flake because nixpkgs does not package it.
  useNixPackage = platform == "linux" || role == "sandbox";
in
{
  home.packages = pkgs.lib.optionals useNixPackage [
    inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  xdg.configFile."herdr/config.toml" = {
    source = ../../../home/.config/herdr/config.toml;
    force = overwriteHomeManagerBackups;
    # Apply config edits to an already-running server without starting one.
    onChange = ''
      if command -v herdr >/dev/null 2>&1; then
        herdr server reload-config >/dev/null 2>&1 || true
      fi
    '';
  };
}
