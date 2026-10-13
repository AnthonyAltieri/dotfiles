# Sign a numbered Claude account into the single ~/.claude home.
#
# Every account shares ~/.claude, so only one is signed in at a time and the
# switch applies to every terminal. Each number remembers the email it last
# signed in with and prefills it on the login page.
cc-login() {
  if (( $# != 1 )) || [[ "$1" != (1|2) ]]; then
    print -u2 -- 'Usage: cc-login <1|2>'
    return 2
  fi

  local config_dir="$HOME/.claude"
  local accounts_file="${XDG_STATE_HOME:-$HOME/.local/state}/cc-login/accounts.json"
  local email
  local -a login_args=(auth login --claudeai)

  if [[ -f "$accounts_file" ]]; then
    email="$(jq -r --arg n "$1" '
      .[$n] // ""
      | if type == "string" then . else error("Invalid Claude account email") end
    ' "$accounts_file")" || return $?
    [[ -n "$email" ]] && login_args+=(--email "$email")
  fi

  CLAUDE_CONFIG_DIR="$config_dir" command claude "${login_args[@]}" || return $?
  export CLAUDE_CONFIG_DIR="$config_dir"

  email="$(jq -r '.oauthAccount.emailAddress // ""' "$config_dir/.claude.json" 2>/dev/null)"
  if [[ -n "$email" ]]; then
    mkdir -p "${accounts_file:h}"
    local updated
    updated="$({ [[ -f "$accounts_file" ]] && cat "$accounts_file" || print '{}'; } \
      | jq --arg n "$1" --arg email "$email" '.[$n] = $email')" \
      && print -r -- "$updated" > "$accounts_file"
  fi
  print -r -- "Claude account $1 signed in${email:+ as $email}."
}
