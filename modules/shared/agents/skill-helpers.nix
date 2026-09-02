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
  }:
    pkgs.rustPlatform.buildRustPackage {
      inherit pname meta;
      version = "0.1.0";
      src = cleanRustSource src;
      cargoLock.lockFile = lockFile;
      doCheck = true;
    };

  ghAddressCommentsTools = buildRustHelper {
    pname = "gh-address-comments-tools";
    src = ../../../pkgs/gh-comment-tools;
    lockFile = ../../../pkgs/gh-comment-tools/Cargo.lock;
  };

  ghFixCiTools = buildRustHelper {
    pname = "gh-fix-ci-tools";
    src = ../../../pkgs/gh-ci-tools;
    lockFile = ../../../pkgs/gh-ci-tools/Cargo.lock;
  };

  sqlReadTools = buildRustHelper {
    pname = "sql-read-tools";
    src = ../../../pkgs/sql-read;
    lockFile = ../../../pkgs/sql-read/Cargo.lock;
  };

  atlasCli = buildRustHelper {
    pname = "atlas-cli";
    src = ../../../pkgs/atlas-cli;
    lockFile = ../../../pkgs/atlas-cli/Cargo.lock;
  };
in
{
  home.packages =
    [
      ghAddressCommentsTools
      ghFixCiTools
      sqlReadTools
    ]
    ++ lib.optionals (platform == "darwin") [
      atlasCli
      pkgs.codex-thread-manager
    ];
}
