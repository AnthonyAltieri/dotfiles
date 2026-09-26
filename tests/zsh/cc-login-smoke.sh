#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home"

cat > "$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$CLAUDE_CONFIG_DIR" "$@" > "$CC_LOGIN_TEST_CALL"
exit "${CC_LOGIN_TEST_EXIT:-0}"
EOF
chmod +x "$WORK/bin/claude"

HOME="$WORK/home" PATH="$WORK/bin:$PATH" CC_LOGIN_TEST_CALL="$WORK/call" \
  zsh -efc '
    source "$1"

    # Each number routes login to its own profile, then selects it in this shell.
    for number dirname email in 1 .claude first@example.com 2 .claude-anthropic2 second@privaterelay.appleid.com; do
      config_dir="$HOME/$dirname"
      mkdir -p "$config_dir"
      printf '\''{"oauthAccount":{"emailAddress":"%s"}}\n'\'' "$email" > "$config_dir/.claude.json"
      cc-login "$number"
      expected="$(printf "%s\n" "$config_dir" auth login --claudeai --email "$email")"
      [[ "$(<"$CC_LOGIN_TEST_CALL")" == "$expected" ]]
      [[ "$CLAUDE_CONFIG_DIR" == "$config_dir" ]]
      [[ "$(sh -c '\''printf %s "$CLAUDE_CONFIG_DIR"'\'')" == "$config_dir" ]]
    done

    # Failed authentication must preserve the active profile and the exit code.
    export CC_LOGIN_TEST_EXIT=17
    result=0
    cc-login 1 || result=$?
    [[ "$result" == 17 && "$CLAUDE_CONFIG_DIR" == "$HOME/.claude-anthropic2" ]]
    unset CC_LOGIN_TEST_EXIT

    # Rejected arguments must not invoke the external login process.
    for args in "" "3" "1 extra"; do
      rm -f "$CC_LOGIN_TEST_CALL"
      result=0
      cc-login ${=args} 2>/dev/null || result=$?
      [[ "$result" == 2 && ! -e "$CC_LOGIN_TEST_CALL" ]]
    done

    # New profiles can log in without an email hint.
    rm "$HOME/.claude/.claude.json"
    cc-login 1
    expected="$(printf "%s\n" "$HOME/.claude" auth login --claudeai)"
    [[ "$(<"$CC_LOGIN_TEST_CALL")" == "$expected" ]]

    # Corrupt metadata must fail before OAuth and preserve the active profile.
    printf "%s\n" "{invalid" > "$HOME/.claude-anthropic2/.claude.json"
    rm "$CC_LOGIN_TEST_CALL"
    result=0
    cc-login 2 2>/dev/null || result=$?
    [[ "$result" != 0 && ! -e "$CC_LOGIN_TEST_CALL" && "$CLAUDE_CONFIG_DIR" == "$HOME/.claude" ]]
  ' _ "$ROOT/home/.config/zsh/functions/cc-login.zsh"

printf '%s\n' 'Claude numbered login smoke test passed.'
