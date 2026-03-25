{ lib, rustPackages_1_88, spacesSrc }:
let
  cargoToml = builtins.fromTOML (builtins.readFile "${spacesSrc}/Cargo.toml");
in
rustPackages_1_88.rustPlatform.buildRustPackage {
  pname = cargoToml.package.name;
  version = cargoToml.package.version;
  src = spacesSrc;
  cargoLock.lockFile = "${spacesSrc}/Cargo.lock";
  doCheck = false;

  meta = with lib; {
    description = "Create a parent directory with multiple worktrees under it for multi-repo agentic coding";
    homepage = "https://github.com/AnthonyAltieri/spaces";
    license = licenses.mit;
    mainProgram = cargoToml.package.name;
    platforms = platforms.unix;
  };
}
