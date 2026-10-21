{ pkgs, ... }:
{
  # One long-lived sccache server per user, so every checkout and sandboxed agent shares compiled
  # crates over the local port instead of starting its own server with a private cache. Clients
  # opt in with RUSTC_WRAPPER=sccache; per-host settings such as SCCACHE_DIR and
  # SCCACHE_CACHE_SIZE come from ~/.env.
  home.packages = [ pkgs.sccache ];

  systemd.user.services.sccache = {
    Unit.Description = "Shared sccache server";
    Service = {
      Environment = [
        "SCCACHE_NO_DAEMON=1"
        "SCCACHE_IDLE_TIMEOUT=0"
      ];
      EnvironmentFile = "-%h/.env";
      ExecStart = "${pkgs.sccache}/bin/sccache --start-server";
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
