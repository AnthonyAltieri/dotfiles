{ lib, pkgs, ... }:
let
  spacesBin = lib.getExe pkgs.spaces;
  escapedSpacesBin = lib.escapeShellArg spacesBin;
in {
  system.activationScripts.spacesLocalBin.text = ''
    target="/usr/local/bin/spaces"
    source=${escapedSpacesBin}

    /bin/mkdir -p /usr/local/bin

    if [ -d "$target" ] && [ ! -L "$target" ]; then
      echo "Refusing to replace directory at $target" >&2
      exit 1
    fi

    if [ -L "$target" ] && [ "$(/usr/bin/readlink "$target")" = "$source" ]; then
      :
    else
      /bin/rm -f "$target"
      /bin/ln -s "$source" "$target"
    fi
  '';
}
