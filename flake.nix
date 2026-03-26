{
  description = "Dotfiles managed with Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    spaces-src = {
      url = "github:AnthonyAltieri/spaces";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, ... }: let
    lib = nixpkgs.lib;
    mkHome = import ./lib/mkHome.nix { inherit inputs; };
    mkDarwin = import ./lib/mkDarwin.nix { inherit inputs; };
    env = builtins.getEnv;
    username =
      let
        sudoUser = env "SUDO_USER";
        user = env "USER";
        logname = env "LOGNAME";
      in
      if sudoUser != "" then
        sudoUser
      else if user != "" then
        user
      else if logname != "" then
        logname
      else
        throw "Unable to determine the current user. Re-run the flake command with --impure and USER or LOGNAME set.";
    homeDirectoryFor =
      system:
      if lib.hasSuffix "darwin" system then
        "/Users/${username}"
      else
        "/home/${username}";
    supportedSystems = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    forAllSystems = lib.genAttrs supportedSystems;
  in {
    overlays.default = final: prev: {
      observe = final.callPackage ./pkgs/observe.nix { };
      spaces = final.callPackage ./pkgs/spaces.nix {
        spacesSrc = inputs.spaces-src;
      };
    };

    packages = forAllSystems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ self.overlays.default ];
        };
      in
      {
        observe = pkgs.observe;
        spaces = pkgs.spaces;
      }
    );

    apps = forAllSystems (system: {
      spaces = {
        type = "app";
        program = "${self.packages.${system}.spaces}/bin/spaces";
      };
    });

    darwinConfigurations = {
      personal = mkDarwin {
        role = "personal";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-darwin";
      };

      personal-overwrite = mkDarwin {
        role = "personal";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-darwin";
        overwriteHomeManagerBackups = true;
      };

      work = mkDarwin {
        role = "work";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-darwin";
      };

      work-overwrite = mkDarwin {
        role = "work";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-darwin";
        overwriteHomeManagerBackups = true;
      };
    };

    homeConfigurations = {
      personal-linux = mkHome {
        role = "personal";
        system = "x86_64-linux";
        inherit username;
        homeDirectory = homeDirectoryFor "x86_64-linux";
      };

      personal-aarch64-linux = mkHome {
        role = "personal";
        system = "aarch64-linux";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-linux";
      };

      work-linux = mkHome {
        role = "work";
        system = "x86_64-linux";
        inherit username;
        homeDirectory = homeDirectoryFor "x86_64-linux";
      };

      work-aarch64-linux = mkHome {
        role = "work";
        system = "aarch64-linux";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-linux";
      };

      sandbox-aarch64-darwin = mkHome {
        role = "sandbox";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-darwin";
      };

      sandbox-aarch64-linux = mkHome {
        role = "sandbox";
        system = "aarch64-linux";
        inherit username;
        homeDirectory = homeDirectoryFor "aarch64-linux";
      };

      sandbox-x86_64-linux = mkHome {
        role = "sandbox";
        system = "x86_64-linux";
        inherit username;
        homeDirectory = homeDirectoryFor "x86_64-linux";
      };
    };
  };
}
