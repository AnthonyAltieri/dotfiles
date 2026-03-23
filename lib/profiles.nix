{ lib }:
let
  sharedHomeModules = [
    ../modules/shared/base.nix
    ../modules/shared/files.nix
    ../modules/shared/shell.nix
    ../modules/shared/tmux.nix
    ../modules/shared/neovim.nix
    ../modules/shared/agents-codex.nix
    ../modules/shared/agents-claude.nix
    ../modules/shared/starship.nix
    ../modules/shared/vim.nix
  ];

  roleHomeModules = {
    common = [
      ../modules/roles/common.nix
    ];

    personal = [
      ../modules/roles/common.nix
      ../modules/roles/personal.nix
    ];

    work = [
      ../modules/roles/common.nix
      ../modules/roles/work.nix
    ];

    sandbox = [
      ../modules/roles/sandbox.nix
    ];
  };

  linuxHomeModules = [
    ../modules/platforms/linux/default.nix
  ];

  darwinRoleHomeModules = role:
    lib.optionals (role != "sandbox") [
      ../modules/platforms/darwin/ghostty.nix
    ];
in {
  darwinSystemModules = [
    ../modules/platforms/darwin/default.nix
  ];

  mkHomeModules = { role, platform }:
    let
      platformModules =
        if platform == "linux"
        then linuxHomeModules
        else if platform == "darwin"
        then [ ]
        else throw "Unsupported platform: ${platform}";
    in
      sharedHomeModules
      ++ platformModules
      ++ darwinRoleHomeModules role
      ++ (roleHomeModules.${role} or (throw "Unsupported role: ${role}"));
}
