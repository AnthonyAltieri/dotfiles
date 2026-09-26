# Authenticate a personal Claude profile and select it for this terminal.
cc-login() {
  if (( $# != 1 )) || [[ "$1" != (1|2) ]]; then
    print -u2 -- 'Usage: cc-login <1|2>'
    return 2
  fi

  local config_dir="$HOME/.claude"
  [[ "$1" == 2 ]] && config_dir="$HOME/.claude-anthropic2"
  local email
  local -a login_args=(auth login --claudeai)

  if [[ -f "$config_dir/.claude.json" ]]; then
    email="$(jq -r '
      .oauthAccount.emailAddress // ""
      | if type == "string" then . else error("Invalid Claude account email") end
    ' "$config_dir/.claude.json")" || return $?
    [[ -n "$email" ]] && login_args+=(--email "$email")
  fi

  CLAUDE_CONFIG_DIR="$config_dir" command claude "${login_args[@]}" || return $?
  export CLAUDE_CONFIG_DIR="$config_dir"
  print -r -- "Claude account $1 selected for this terminal."
}
