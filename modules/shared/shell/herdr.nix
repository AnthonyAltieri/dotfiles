{ inputs, overwriteHomeManagerBackups ? false, pkgs, platform, role, ... }:
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
}
