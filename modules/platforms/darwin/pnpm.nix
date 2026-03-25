{ lib, pkgs, ... }:
let
  bash = "${pkgs.bash}/bin/bash";
  curl = "${pkgs.curl}/bin/curl";
  grep = "${pkgs.gnugrep}/bin/grep";
in {
  home.activation.installPnpmFromOfficialSource = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PNPM_HOME="$HOME/Library/pnpm"

    current_version=""
    if [ -x "$PNPM_HOME/pnpm" ]; then
      current_version="$("$PNPM_HOME/pnpm" --version 2>/dev/null || true)"
    elif command -v pnpm >/dev/null 2>&1; then
      current_version="$(pnpm --version 2>/dev/null || true)"
    fi

    current_major="''${current_version%%.*}"
    if [ "$current_major" != "10" ]; then
      target_version="$(${curl} -fsSL https://registry.npmjs.org/@pnpm/exe \
        | ${grep} -o '"latest-10":[[:space:]]*"[0-9.]*"' \
        | ${grep} -o '[0-9.]*' \
        | head -n 1)"

      if [ -z "$target_version" ]; then
        echo "Failed to resolve pnpm latest-10 from the npm registry" >&2
        exit 1
      fi

      ${curl} -fsSL https://get.pnpm.io/install.sh \
        | env ENV=/dev/null SHELL=/bin/zsh PNPM_VERSION="$target_version" ${bash} -
    fi
  '';
}
