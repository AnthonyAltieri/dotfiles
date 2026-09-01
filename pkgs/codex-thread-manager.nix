{ lib, makeWrapper, python3, stdenvNoCC }:
let
  python = python3.withPackages (pythonPackages: [
    pythonPackages.mcp
  ]);
  source = ./codex-thread-manager;
in
stdenvNoCC.mkDerivation {
  pname = "codex-thread-manager";
  version = "0.1.0";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  doCheck = true;

  checkPhase = ''
    ${python}/bin/python -m unittest discover \
      -s ${source} \
      -p 'test_*.py'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    makeWrapper ${python}/bin/python "$out/bin/codex-thread-manager" \
      --add-flags ${source}/codex_thread_manager.py
    runHook postInstall
  '';

  meta = {
    description = "Claude MCP bridge for persistent Codex app-server threads";
    license = lib.licenses.mit;
    mainProgram = "codex-thread-manager";
  };
}
