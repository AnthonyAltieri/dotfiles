{ inputs }:
{ role, system, username, homeDirectory }:
let
  lib = inputs.nixpkgs.lib;
  profiles = import ./profiles.nix { inherit lib; };
in
inputs.nix-darwin.lib.darwinSystem {
  inherit system;
  specialArgs = {
    inherit inputs role system username homeDirectory;
    platform = "darwin";
  };
  modules =
    profiles.darwinSystemModules
    ++ [
      inputs.home-manager.darwinModules.home-manager
      {
        nixpkgs.hostPlatform = system;
        nixpkgs.config.allowUnfree = true;

        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];

        system.primaryUser = username;
        system.stateVersion = 6;

        users.users.${username}.home = homeDirectory;

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "hm-backup";
        home-manager.extraSpecialArgs = {
          inherit inputs role system username homeDirectory;
          platform = "darwin";
        };
        home-manager.users.${username}.imports = profiles.mkHomeModules {
          inherit role;
          platform = "darwin";
        };
      }
    ];
}
