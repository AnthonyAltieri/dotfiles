{
  home.sessionVariables = {
    DOTFILES_PROFILE = "personal";
  };

  # Codex workers spawned by the orchestrator skills run in the workspace-write
  # sandbox. They need Bazel's output root, the Docker socket, and outbound
  # network for `git push` / `gh pr create`. Roots are home-relative so the
  # role applies to any login user.
  dotfiles.codexWorkspaceWriteSandbox = {
    networkAccess = true;
    writableRoots = [
      ".cache/bazel"
      ".docker/run"
      "/var/run/docker.sock"
    ];
  };
}
