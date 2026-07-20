{ lib, pkgs, platform, ... }:
let
  cleanRustSource = src:
    lib.cleanSourceWith {
      inherit src;
      filter = path: type:
        let
          pathString = toString path;
          srcString = toString src;
          relativePath = lib.removePrefix "${srcString}/" pathString;
        in
          !(
            relativePath == "target"
            || lib.hasPrefix "target/" relativePath
            || lib.hasInfix "/target/" relativePath
            || lib.hasSuffix "/target" relativePath
          );
    };

  buildRustHelper = {
    pname,
    src,
    lockFile,
    meta ? { },
    nativeCheckInputs ? [ ],
  }:
    pkgs.rustPlatform.buildRustPackage {
      inherit pname meta nativeCheckInputs;
      version = "0.1.0";
      src = cleanRustSource src;
      cargoLock.lockFile = lockFile;
      doCheck = true;
    };

  ghAddressCommentsTools = buildRustHelper {
    pname = "gh-address-comments-tools";
    src = ../../home/.codex/skills/gh-comments/scripts;
    lockFile = ../../home/.codex/skills/gh-comments/scripts/Cargo.lock;
  };

  ghFixCiTools = buildRustHelper {
    pname = "gh-fix-ci-tools";
    src = ../../home/.codex/skills/gh-ci/scripts;
    lockFile = ../../home/.codex/skills/gh-ci/scripts/Cargo.lock;
  };

  sqlReadTools = buildRustHelper {
    pname = "sql-read-tools";
    src = ../../home/.codex/skills/sql-read/scripts;
    lockFile = ../../home/.codex/skills/sql-read/scripts/Cargo.lock;
  };

  ghManagePrTools = buildRustHelper {
    pname = "gh-manage-pr-tools";
    src = ../../home/.codex/skills/gh-pr-body/scripts;
    lockFile = ../../home/.codex/skills/gh-pr-body/scripts/Cargo.lock;
    nativeCheckInputs = [ pkgs.jq ];
  };

  atlasCli = buildRustHelper {
    pname = "atlas-cli";
    src = ../../home/.codex/skills/atlas/scripts;
    lockFile = ../../home/.codex/skills/atlas/scripts/Cargo.lock;
  };
in
{
  home.packages =
    [
      ghAddressCommentsTools
      ghFixCiTools
      ghManagePrTools
      sqlReadTools
    ]
    ++ lib.optionals (platform == "darwin") [
      atlasCli
    ];
}
