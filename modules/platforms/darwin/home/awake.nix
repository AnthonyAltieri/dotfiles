{ config, lib, ... }:
let
  # Menu-bar keep-awake toggle; see pkgs/awake/main.swift. It is built with the
  # Xcode Command Line Tools swiftc because AppKit apps need the macOS SDK.
  label = "dotfiles.awake";
  source = ../../../../pkgs/awake/main.swift;
  infoPlist = builtins.toFile "Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleDevelopmentRegion = "en";
      CFBundleDisplayName = "Awake";
      CFBundleExecutable = "awake";
      CFBundleIdentifier = label;
      CFBundleName = "Awake";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = "1.0";
      CFBundleVersion = "1";
      # Menu-bar only: no Dock icon or app menu.
      LSUIElement = true;
    }
  );
  app = "/Applications/Awake.app";
  binary = "${app}/Contents/MacOS/awake";
in
{
  # Rebuild the bundle only when its inputs change, before launchd loads the
  # agent, then restart a running agent so it picks up the new binary.
  home.activation.dotfilesAwakeBuild = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "writeBoundary" ] ''
    awake_app="${app}"
    # Marks the bundle as ours and records the inputs it was built from.
    awake_stamp="$awake_app/Contents/Resources/dotfiles-source"
    awake_inputs="${source} ${infoPlist}"

    # Earlier versions installed a bare binary here.
    $DRY_RUN_CMD rm -rf "${config.xdg.dataHome}/awake"

    if [ ! -x /usr/bin/swiftc ]; then
      echo "awake: /usr/bin/swiftc not found; run xcode-select --install. Skipping build." >&2
    elif [ -e "$awake_app" ] && [ ! -f "$awake_stamp" ]; then
      echo "awake: $awake_app exists but was not built by dotfiles. Skipping build." >&2
    elif [ ! -x "${binary}" ] || [ "$(cat "$awake_stamp" 2>/dev/null)" != "$awake_inputs" ]; then
      awake_tmp="$awake_app.tmp"
      $DRY_RUN_CMD rm -rf "$awake_tmp"
      $DRY_RUN_CMD mkdir -p "$awake_tmp/Contents/MacOS" "$awake_tmp/Contents/Resources"
      $DRY_RUN_CMD cp "${infoPlist}" "$awake_tmp/Contents/Info.plist"
      $DRY_RUN_CMD chmod u+w "$awake_tmp/Contents/Info.plist"
      $DRY_RUN_CMD /usr/bin/env -i PATH=/usr/bin:/bin HOME="$HOME" \
        /usr/bin/swiftc -O -o "$awake_tmp/Contents/MacOS/awake" "${source}"
      if [ -z "''${DRY_RUN_CMD:-}" ]; then
        printf '%s\n' "$awake_inputs" > "$awake_tmp/Contents/Resources/dotfiles-source"
      fi
      # Ad-hoc sign the whole bundle so the signature covers Info.plist.
      $DRY_RUN_CMD /usr/bin/codesign --force --sign - "$awake_tmp"
      $DRY_RUN_CMD rm -rf "$awake_app"
      $DRY_RUN_CMD mv "$awake_tmp" "$awake_app"
      if /bin/launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1; then
        $DRY_RUN_CMD /bin/launchctl kickstart -k "gui/$(id -u)/${label}"
      fi
    fi
  '';

  launchd.agents.awake = {
    enable = true;
    config = {
      Label = label;
      ProgramArguments = [ binary ];
      RunAtLoad = true;
      # Restart after a crash, but stay quit after "Quit awake".
      KeepAlive.SuccessfulExit = false;
      ProcessType = "Interactive";
    };
  };
}
