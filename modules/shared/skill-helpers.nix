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

  buildRustHelper = { pname, src, lockFile, meta ? { } }:
    pkgs.rustPlatform.buildRustPackage {
      inherit pname meta;
      version = "0.1.0";
      src = cleanRustSource src;
      cargoLock.lockFile = lockFile;
      doCheck = false;
    };

  ghAddressCommentsTools = buildRustHelper {
    pname = "gh-address-comments-tools";
    src = ../../home/.codex/skills/gh-address-comments/scripts;
    lockFile = ../../home/.codex/skills/gh-address-comments/scripts/Cargo.lock;
  };

  ghFixCiTools = buildRustHelper {
    pname = "gh-fix-ci-tools";
    src = ../../home/.codex/skills/gh-fix-ci/scripts;
    lockFile = ../../home/.codex/skills/gh-fix-ci/scripts/Cargo.lock;
  };

  sqlReadTools = buildRustHelper {
    pname = "sql-read-tools";
    src = ../../home/.codex/skills/sql-read/scripts;
    lockFile = ../../home/.codex/skills/sql-read/scripts/Cargo.lock;
  };

  ghManagePrTools = buildRustHelper {
    pname = "gh-manage-pr-tools";
    src = ../../home/.codex/skills/gh-manage-pr/scripts;
    lockFile = ../../home/.codex/skills/gh-manage-pr/scripts/Cargo.lock;
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
