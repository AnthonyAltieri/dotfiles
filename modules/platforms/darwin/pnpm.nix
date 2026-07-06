{ lib, pkgs, ... }:
let
  curl = "${pkgs.curl}/bin/curl";
  install = "${pkgs.coreutils}/bin/install";
  jq = "${pkgs.jq}/bin/jq";
  mkdir = "${pkgs.coreutils}/bin/mkdir";
  mktemp = "${pkgs.coreutils}/bin/mktemp";
  rm = "${pkgs.coreutils}/bin/rm";
  uname = "${pkgs.coreutils}/bin/uname";
in {
  home.sessionPath = [
    "$HOME/Library/pnpm"
  ];

  home.sessionVariables.PNPM_HOME = "$HOME/Library/pnpm";

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
      target_version="$(${curl} -fsSL https://registry.npmjs.org/@pnpm/exe | ${jq} -r '.["dist-tags"]["latest-10"] // empty')"

      if [ -z "$target_version" ]; then
        echo "Failed to resolve pnpm latest-10 from the npm registry" >&2
        exit 1
      fi

      case "$(${uname} -m)" in
        arm64|aarch64)
          pnpm_arch="arm64"
          ;;
        x86_64|amd64)
          pnpm_arch="x64"
          ;;
        *)
          echo "Unsupported pnpm architecture: $(${uname} -m)" >&2
          exit 1
          ;;
      esac

      ${mkdir} -p "$PNPM_HOME"
      tmp_dir="$(${mktemp} -d)"

      if ! ${curl} -fL "https://github.com/pnpm/pnpm/releases/download/v$target_version/pnpm-macos-$pnpm_arch" -o "$tmp_dir/pnpm"; then
        ${rm} -rf "$tmp_dir"
        exit 1
      fi

      if ! ${install} -m 0755 "$tmp_dir/pnpm" "$PNPM_HOME/pnpm"; then
        ${rm} -rf "$tmp_dir"
        exit 1
      fi

      ${rm} -rf "$tmp_dir"
    fi
  '';
}
