#!/usr/bin/env bash
# E2e: real Debian, Nix, and Home Manager; only the managed payload is minimal.
set -euo pipefail
source "$HOME/.nix-profile/etc/profile.d/nix.sh"

cd /work
bash tests/bootstrap-platform-smoke.sh

# Evaluate the production profiles without building every development package.
nix eval --impure --json --expr '
  let
    flake = builtins.getFlake "path:/work";
    names = [ "personal-linux" "personal-aarch64-linux" "work-linux" "work-aarch64-linux" ];
    check = name:
      let
        normal = flake.homeConfigurations.${name};
        overwrite = flake.homeConfigurations.${name + "-overwrite"};
      in assert !normal.config.home.file.".vimrc".force;
         assert overwrite.config.home.file.".vimrc".force;
         { inherit name; normal = normal.activationPackage.drvPath; overwrite = overwrite.activationPackage.drvPath; };
  in map check names
'

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/scripts"
cp bootstrap.sh "$fixture/"
cp scripts/bootstrap-linux.sh "$fixture/scripts/"
cat > "$fixture/flake.nix" <<'EOF'
{
  inputs.dotfiles.url = "path:/work";
  outputs = { dotfiles, ... }: let
    system = builtins.currentSystem;
    suffix = if system == "aarch64-linux" then "aarch64-linux" else "linux";
    home = force: dotfiles.inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = dotfiles.inputs.nixpkgs.legacyPackages.${system};
      modules = [{
        home.username = "dotfiles";
        home.homeDirectory = "/home/dotfiles";
        home.stateVersion = "25.05";
        home.file."bootstrap-example" = { text = "managed\n"; inherit force; };
      }];
    };
  in {
    homeConfigurations."personal-${suffix}" = home false;
    homeConfigurations."personal-${suffix}-overwrite" = home true;
  };
}
EOF

cd "$fixture"
printf 'original\n' > "$HOME/bootstrap-example"
./bootstrap.sh personal --dry-run --diff
[[ "$(cat "$HOME/bootstrap-example")" == original ]]
[[ ! -e "$HOME/bootstrap-example.hm-backup" ]]
./bootstrap.sh personal --diff
[[ -L "$HOME/bootstrap-example" ]]
[[ "$(cat "$HOME/bootstrap-example")" == managed ]]
[[ "$(cat "$HOME/bootstrap-example.hm-backup")" == original ]]
./bootstrap.sh personal --dry-run --diff

rm "$HOME/bootstrap-example" "$HOME/bootstrap-example.hm-backup"
printf 'replace me\n' > "$HOME/bootstrap-example"
./bootstrap.sh personal --overwrite
[[ -L "$HOME/bootstrap-example" ]]
[[ "$(cat "$HOME/bootstrap-example")" == managed ]]
[[ ! -e "$HOME/bootstrap-example.hm-backup" ]]
echo 'ok Debian bootstrap install, preview, diff, backup, and overwrite with real Home Manager'
