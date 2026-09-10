{ pkgs, ... }:
{
  home.packages = with pkgs; [
    awscli2
    docker
    glow
    postgresql
    ripgrep
  ];

  home.sessionVariables = {
    DOTFILES_COMMON = "1";
  };

  dotfiles.agentMcpServers.linear = "https://mcp.linear.app/mcp";

  programs.zsh.oh-my-zsh = {
    enable = true;
    plugins = [
      "git"
      "npm"
      "z"
    ];
    theme = "robbyrussell";
  };
}
