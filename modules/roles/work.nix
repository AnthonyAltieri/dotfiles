{ overwriteHomeManagerBackups ? false, pkgs, ... }:
{
  home.file."go/bin/observe" = {
    source = "${pkgs.observe}/bin/observe";
    force = overwriteHomeManagerBackups;
  };

  home.packages = with pkgs; [
    observe
  ];

  home.sessionVariables = {
    DOTFILES_PROFILE = "work";
  };
}
