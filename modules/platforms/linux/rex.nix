{ inputs, lib, role, ... }:
{
  # Rex's own Home Manager module: the rex command, its terminfo entry in
  # ~/.terminfo, and the ssh guard that keeps TERM=xterm-rex off remote hosts.
  imports = [ inputs.rex.homeManagerModules.default ];

  programs.rex.enable = true;

  # Home Manager writes ~/.ssh/config only when this is on, and the Rex module
  # adds its ssh guard there as the first Include.
  programs.ssh.enable = true;

  # The personal server as the systemd user service `rex`, on the same socket
  # every rex command uses. A switch never restarts it, because that ends every
  # session; run `systemctl --user restart rex` to pick up a new package.
  services.rex.enable = true;

  # On the personal hub the server joins the tailnet as its own node, so other
  # machines connect to rex.<tailnet>.ts.net with no root login server. Only the
  # Tailscale account that enrolls the node may connect.
  services.rex.tailscale.enable = role == "personal";
}
