{
  # The Rex app's look and behavior. Machine identity (the tailnet hostname, saved
  # servers) and app state stay app-owned. Changes made in Rex's Settings last until
  # the next switch, so copy any you want to keep into this file.
  targets.darwin.defaults."com.superlogical.rex" = {
    "Workspace.darkThemeID" = "charcoal-atelier";
    "Workspace.lightThemeID" = "charcoal-atelier";
    "Workspace.interfaceStyle" = "useTheme";
    "Workspace.inactivePaneFadeMode" = "both";
    "Workspace.usesStandardInactiveWindowPaneStyles" = true;
    "Workspace.playsProgramActivitySounds" = false;
    "Workspace.sidebarCollapsed" = false;
    "Workspace.sidebarPosition" = "left";
    "Workspace.tabStyle" = "vertical";
    "Workspace.tabIconCount" = 3;
    "Workspace.tabIconTintMode" = "off";
    "Workspace.terminalFontName" = "BerkeleyMono";
    "Workspace.terminalFallbackFontNames" = [ "BerkeleyMono" ];
    "Workspace.terminalFontPointSize" = 14.0;
    "Workspace.terminalAllowsLigatures" = false;
    "Workspace.terminalCursorStyle" = "bar";
    "Workspace.terminalCursorBlinkUsesCustomInterval" = false;
    "Workspace.terminalCursorBlinkIntervalMilliseconds" = 500;
    "rex.agents.names-sessions" = true;
  };
}
