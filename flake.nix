{
  description = "Anthony Altieri dotfiles managed with Nix";

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
  };

  outputs = inputs@{ ... }: let
    mkHome = import ./lib/mkHome.nix { inherit inputs; };
    mkDarwin = import ./lib/mkDarwin.nix { inherit inputs; };
    username = "anthonyaltieri";
  in {
    darwinConfigurations = {
      personal = mkDarwin {
        role = "personal";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = "/Users/${username}";
      };

      work = mkDarwin {
        role = "work";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = "/Users/${username}";
      };
    };

    homeConfigurations = {
      personal-linux = mkHome {
        role = "personal";
        system = "x86_64-linux";
        inherit username;
        homeDirectory = "/home/${username}";
      };

      personal-aarch64-linux = mkHome {
        role = "personal";
        system = "aarch64-linux";
        inherit username;
        homeDirectory = "/home/${username}";
      };

      work-linux = mkHome {
        role = "work";
        system = "x86_64-linux";
        inherit username;
        homeDirectory = "/home/${username}";
      };

      work-aarch64-linux = mkHome {
        role = "work";
        system = "aarch64-linux";
        inherit username;
        homeDirectory = "/home/${username}";
      };

      sandbox-aarch64-darwin = mkHome {
        role = "sandbox";
        system = "aarch64-darwin";
        inherit username;
        homeDirectory = "/Users/${username}";
      };

      sandbox-aarch64-linux = mkHome {
        role = "sandbox";
        system = "aarch64-linux";
        inherit username;
        homeDirectory = "/home/${username}";
      };

      sandbox-x86_64-linux = mkHome {
        role = "sandbox";
        system = "x86_64-linux";
        inherit username;
        homeDirectory = "/home/${username}";
      };
    };
  };
}
