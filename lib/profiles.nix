{ lib }:
let
  sharedHomeModules = [
    ../modules/shared/base.nix
    ../modules/shared/files.nix
    ../modules/shared/agents
    ../modules/shared/editors
    ../modules/shared/shell
  ];

  roleHomeModules = {
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
in {
  darwinSystemModules = [
    ../modules/platforms/darwin/system
  ];

  mkHomeModules = { role, platform }:
    let
      platformModules =
        if platform == "linux"
        then lib.optionals (role != "sandbox") [ ../modules/platforms/linux ]
        else if platform == "darwin"
        then lib.optionals (role != "sandbox") [ ../modules/platforms/darwin/home ]
        else throw "Unsupported platform: ${platform}";
    in
      sharedHomeModules
      ++ platformModules
      ++ (roleHomeModules.${role} or (throw "Unsupported role: ${role}"));
}
