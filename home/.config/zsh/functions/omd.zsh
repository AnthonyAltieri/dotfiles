# Open a local file in Obsidian, including files outside a vault.
omd() {
  emulate -L zsh

  if (( $# != 1 )); then
    print -u2 -- 'Usage: omd <file path>'
    return 2
  fi

  if [[ ! -f "$1" || ! -r "$1" ]]; then
    print -ru2 -- "omd: not a readable file: $1"
    return 1
  fi

  local note_file="${1:A}"
  local obsidian_cli="${commands[obsidian]:-/Applications/Obsidian.app/Contents/MacOS/obsidian-cli}"
  if [[ ! -x "$obsidian_cli" ]]; then
    print -u2 -- 'omd: Obsidian CLI unavailable; install Obsidian and enable Settings > General > Command line interface.'
    return 127
  fi

  local cli_output cli_status=0
  cli_output="$("$obsidian_cli" open "path=file:$note_file")" || cli_status=$?
  # Obsidian can report command errors on stdout with exit code zero.
  if (( cli_status != 0 )) || [[ "$cli_output" == Error:* ]]; then
    [[ -z "$cli_output" ]] || print -ru2 -- "$cli_output"
    return $(( cli_status == 0 ? 1 : cli_status ))
  fi

  [[ -z "$cli_output" ]] || print -r -- "$cli_output"
  if [[ "$OSTYPE" == darwin* ]]; then
    command open -a Obsidian
  fi
}
