{ inputs }:
{ role, system, username, homeDirectory }:
let
  lib = inputs.nixpkgs.lib;
  profiles = import ./profiles.nix { inherit lib; };
  platform =
    if lib.hasSuffix "darwin" system
    then "darwin"
    else "linux";
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ inputs.self.overlays.default ];
  };
in
inputs.home-manager.lib.homeManagerConfiguration {
  inherit pkgs;
  extraSpecialArgs = {
    inherit inputs role system username homeDirectory platform;
  };
  modules = profiles.mkHomeModules {
    inherit role platform;
  };
}
