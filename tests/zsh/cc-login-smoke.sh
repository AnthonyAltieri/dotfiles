#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home/.claude"

# A claude stub that records its call and, on success, signs in as
# $CC_LOGIN_TEST_EMAIL by writing the account into the config dir.
cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$CLAUDE_CONFIG_DIR" "$@" > "$CC_LOGIN_TEST_CALL"
[[ "${CC_LOGIN_TEST_EXIT:-0}" == 0 ]] || exit "$CC_LOGIN_TEST_EXIT"
printf '{"oauthAccount":{"emailAddress":"%s"}}\n' "$CC_LOGIN_TEST_EMAIL" > "$CLAUDE_CONFIG_DIR/.claude.json"
EOF
chmod +x "$WORK/bin/claude"

HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH" CC_LOGIN_TEST_CALL="$WORK/call" \
  zsh -efc '
    source "$1"
    accounts="$XDG_STATE_HOME/cc-login/accounts.json"

    # Both numbers sign in to the single ~/.claude home. A first login has no
    # email hint; the signed-in email is remembered for that number.
    for number email in 1 first@example.com 2 second@privaterelay.appleid.com; do
      CC_LOGIN_TEST_EMAIL="$email" cc-login "$number" >/dev/null
      [[ "$(<"$CC_LOGIN_TEST_CALL")" == "$(printf "%s\n" "$HOME/.claude" auth login --claudeai)" ]]
      [[ "$CLAUDE_CONFIG_DIR" == "$HOME/.claude" ]]
      [[ "$(jq -r --arg n "$number" ".[\$n]" "$accounts")" == "$email" ]]
    done

    # Later logins prefill the number'"'"'s own email, not the last account'"'"'s.
    CC_LOGIN_TEST_EMAIL=first@example.com cc-login 1 >/dev/null
    expected="$(printf "%s\n" "$HOME/.claude" auth login --claudeai --email first@example.com)"
    [[ "$(<"$CC_LOGIN_TEST_CALL")" == "$expected" ]]

    # Failed authentication preserves the exit code and the remembered emails.
    before="$(<"$accounts")"
    result=0
    CC_LOGIN_TEST_EXIT=17 cc-login 2 || result=$?
    [[ "$result" == 17 && "$(<"$accounts")" == "$before" ]]

    # Rejected arguments must not invoke the external login process.
    for args in "" "3" "1 extra"; do
      rm -f "$CC_LOGIN_TEST_CALL"
      result=0
      cc-login ${=args} 2>/dev/null || result=$?
      [[ "$result" == 2 && ! -e "$CC_LOGIN_TEST_CALL" ]]
    done

    # A corrupt accounts file fails before OAuth.
    printf "%s\n" "{invalid" > "$accounts"
    result=0
    cc-login 2 2>/dev/null || result=$?
    [[ "$result" != 0 && ! -e "$CC_LOGIN_TEST_CALL" ]]
  ' _ "$ROOT/home/.config/zsh/functions/cc-login.zsh"

printf '%s\n' 'Claude numbered login smoke test passed.'
