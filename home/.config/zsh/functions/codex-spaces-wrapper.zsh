# Codex + spaces wrapper.
# Adapted from Alex Fazio's article:
#   https://x.com/alxfazio/status/2035093597238784486

_codex_spaces_usage() {
  emulate -L zsh

  print -u2 'usage: codex [--name <workspace-name>] --spaces [repo-path ...] [-- extra-codex-args...]'
}

_codex_has_spaces_flag() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit

  local arg

  for arg in "$@"; do
    case "$arg" in
      --spaces) return 0 ;;
      --) break ;;
    esac
  done

  return 1
}

_codex_current_repo() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit

  git rev-parse --show-toplevel 2>/dev/null || {
    print -u2 'codex spaces wrapper: not inside a Git repo'
    return 1
  }
}

_codex_spaces_base_args() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit

  if [[ -n "${CODEX_SPACES_BASE_DIR:-}" ]]; then
    reply=(--base-dir "$CODEX_SPACES_BASE_DIR")
  else
    reply=()
  fi
}

_codex_resolve_repo_paths() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit

  local repo_arg repo_path
  reply=()

  for repo_arg in "$@"; do
    repo_path="$(git -C "$repo_arg" rev-parse --show-toplevel 2>/dev/null)" || {
      print -u2 "codex spaces wrapper: not a Git repo: $repo_arg"
      return 1
    }
    reply+=("$repo_path")
  done
}

_codex_repo_has_branch_name() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit pipefail

  local repo_path="$1"
  local branch_name="$2"
  local remote_branch

  git -C "$repo_path" show-ref --verify --quiet "refs/heads/$branch_name" && return 0

  while IFS= read -r remote_branch; do
    [[ "${remote_branch#*/}" == "$branch_name" ]] && return 0
  done < <(git -C "$repo_path" for-each-ref --format='%(refname:short)' refs/remotes)

  return 1
}

_codex_assert_branch_name_available() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit

  local branch_name="$1"
  local repo_path
  local -a collisions

  shift
  collisions=()

  for repo_path in "$@"; do
    if _codex_repo_has_branch_name "$repo_path" "$branch_name"; then
      collisions+=("$repo_path")
    fi
  done

  (( ${#collisions[@]} == 0 )) && return 0

  print -u2 "codex spaces wrapper: branch name already exists: $branch_name"
  printf '%s\n' "${collisions[@]}" | sed 's/^/  - /' >&2
  return 1
}

_codex_space_target_from_json() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit pipefail

  local space_json="$1"

  printf '%s\n' "$space_json" |
    jq -r 'if (.repos | length) == 1 then .repos[0].worktree_path else .workspace_dir end'
}

codex() {
  emulate -L zsh
  setopt local_options no_sh_wordsplit

  local arg name="" target_dir space_json
  local -i has_spaces=0
  local -a argv_copy repos repo_paths codex_args spaces_args base_args

  if ! _codex_has_spaces_flag "$@"; then
    command codex "$@"
    return
  fi

  argv_copy=("$@")
  repos=()
  codex_args=()

  while (( ${#argv_copy[@]} > 0 )); do
    arg="${argv_copy[1]}"
    argv_copy=("${argv_copy[@]:1}")

    case "$arg" in
      --)
        codex_args=("${argv_copy[@]}")
        break
        ;;
      --spaces)
        (( has_spaces == 0 )) || {
          print -u2 'codex spaces wrapper: `--spaces` may only be provided once'
          return 2
        }
        has_spaces=1
        ;;
      --name=*)
        [[ -n "${arg#--name=}" ]] || {
          print -u2 'codex spaces wrapper: `--name` requires a non-empty value'
          return 2
        }
        [[ -z "$name" ]] || {
          print -u2 'codex spaces wrapper: `--name` may only be provided once'
          return 2
        }
        name="${arg#--name=}"
        ;;
      --name)
        (( ${#argv_copy[@]} > 0 )) || {
          print -u2 'codex spaces wrapper: `--name` requires a value'
          return 2
        }
        [[ -z "$name" ]] || {
          print -u2 'codex spaces wrapper: `--name` may only be provided once'
          return 2
        }
        name="${argv_copy[1]}"
        argv_copy=("${argv_copy[@]:1}")
        [[ -n "$name" ]] || {
          print -u2 'codex spaces wrapper: `--name` requires a non-empty value'
          return 2
        }
        ;;
      -*)
        print -u2 "codex spaces wrapper: unsupported wrapper argument before \`--\`: $arg"
        _codex_spaces_usage
        return 2
        ;;
      *)
        repos+=("$arg")
        ;;
    esac
  done

  (( has_spaces == 1 )) || {
    command codex "$@"
    return
  }

  if (( ${#repos[@]} == 0 )); then
    repo_paths=("$( _codex_current_repo )") || return 1
  else
    _codex_resolve_repo_paths "${repos[@]}" || return 1
    repo_paths=("${reply[@]}")
  fi

  _codex_spaces_base_args || return 1
  base_args=("${reply[@]}")

  spaces_args=("${base_args[@]}" --json)
  if [[ -n "$name" ]]; then
    _codex_assert_branch_name_available "$name" "${repo_paths[@]}" || return 1
    spaces_args+=(--name "$name" --branch "$name")
  fi

  space_json="$(spaces create "${spaces_args[@]}" "${repo_paths[@]}")" || return 1
  target_dir="$(_codex_space_target_from_json "$space_json")" || return 1

  [[ -n "$target_dir" && -d "$target_dir" ]] || {
    print -u2 'codex spaces wrapper: failed to resolve new space target'
    return 1
  }

  command codex -C "$target_dir" "${codex_args[@]}"
}
