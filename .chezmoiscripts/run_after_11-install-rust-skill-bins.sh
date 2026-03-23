#!/bin/bash
set -euo pipefail

if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    . "${HOME}/.cargo/env"
fi

if ! command -v cargo &>/dev/null; then
    echo "cargo is required to install Rust skill binaries into ~/.local/bin" >&2
    exit 1
fi

install_root="${HOME}/.local"
target_root="${HOME}/.local/share/codex-skill-targets"

mkdir -p "${install_root}/bin" "${target_root}"

package_dirs="$(
    {
        for manifest in "${HOME}/.codex/skills"/*/scripts/Cargo.toml; do
            [[ -f "${manifest}" ]] || continue
            skill_name="$(basename "$(dirname "$(dirname "${manifest}")")")"
            printf '%s\t%s\n' "${skill_name}" "$(dirname "${manifest}")"
        done

        for manifest in "${HOME}/.claude/skills"/*/scripts/Cargo.toml; do
            [[ -f "${manifest}" ]] || continue
            skill_name="$(basename "$(dirname "$(dirname "${manifest}")")")"
            printf '%s\t%s\n' "${skill_name}" "$(dirname "${manifest}")"
        done
    } | awk -F '\t' '!seen[$1]++ { print $1 "\t" $2 }'
)"

if [[ -z "${package_dirs}" ]]; then
    echo "No Rust-backed skill packages found under ~/.codex or ~/.claude" >&2
    exit 0
fi

while IFS=$'\t' read -r skill_name package_dir; do
    [[ -n "${skill_name}" && -n "${package_dir}" ]] || continue

    export CARGO_TARGET_DIR="${target_root}/${skill_name}"
    mkdir -p "${CARGO_TARGET_DIR}"

    echo "Installing ${skill_name} binaries into ${install_root}/bin..."
    cargo install --quiet --locked --path "${package_dir}" --root "${install_root}" --force
done <<< "${package_dirs}"
