{ buildGoModule, fetchFromGitHub, lib }:
buildGoModule rec {
  pname = "observe";
  version = "0.3.0-rc2";

  src = fetchFromGitHub {
    owner = "observeinc";
    repo = "observe";
    rev = "v${version}";
    hash = "sha256-7K8Zq5gt6NjVO8t/FiiDRnKvd0Lzk/ixy5K4rxBc3xc=";
  };

  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  doCheck = false;

  meta = with lib; {
    description = "Command-line client for the Observe observability platform";
    homepage = "https://github.com/observeinc/observe";
    license = licenses.asl20;
    mainProgram = "observe";
    platforms = platforms.unix;
  };
}
