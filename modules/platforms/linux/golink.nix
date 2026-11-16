{ lib, pkgs, role, ... }:
let
  stateDir = "%h/.local/share/golink";
in
{
  # Tailscale's golink server, on the personal hub only. It joins the tailnet as
  # its own node `go`, so http://go/<name> works from every device on the
  # tailnet, including phones where browser extensions can't run. Links live in
  # SQLite under ~/.local/share/golink; http://go/.export dumps them as JSON.
  #
  # First start prints a Tailscale login URL to the journal
  # (`journalctl --user -u golink`); opening it enrolls the node. The saved
  # identity sits in the config dir, so no auth key goes into the Nix store.
  systemd.user.services.golink = lib.mkIf (role == "personal") {
    Unit = {
      Description = "golink: private go/ short links on the tailnet";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.golink}/bin/golink"
        "--hostname go"
        "--sqlitedb ${stateDir}/golink.db"
        "--config-dir ${stateDir}/tsnet"
      ];
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${stateDir}/tsnet";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
