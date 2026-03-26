{ pkgs, ... }:
{
  home.file."go/bin/observe".source = "${pkgs.observe}/bin/observe";

  home.packages = with pkgs; [
    observe
  ];

  home.sessionVariables = {
    DOTFILES_PROFILE = "work";
  };
}
