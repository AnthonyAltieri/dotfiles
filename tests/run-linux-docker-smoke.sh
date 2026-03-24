#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-dotfiles-nix-smoke:ubuntu-24.04}"
DOCKERFILE="${REPO_ROOT}/tests/docker/ubuntu-lts/Dockerfile"

host_arch="$(uname -m)"
case "${host_arch}" in
  arm64|aarch64)
    default_profiles=(
      personal-aarch64-linux
      work-aarch64-linux
      sandbox-aarch64-linux
    )
    ;;
  x86_64|amd64)
    default_profiles=(
      personal-linux
      work-linux
      sandbox-x86_64-linux
    )
    ;;
  *)
    echo "Unsupported host architecture for Docker smoke tests: ${host_arch}" >&2
    exit 1
    ;;
esac

profiles=("$@")
if [[ "${#profiles[@]}" -eq 0 ]]; then
  profiles=("${default_profiles[@]}")
fi

docker build --pull -f "${DOCKERFILE}" -t "${IMAGE_NAME}" "${REPO_ROOT}"

for profile in "${profiles[@]}"; do
  echo "==> Running Docker smoke test for ${profile}"
  docker run --rm -e FULL_ACTIVATE="${FULL_ACTIVATE:-0}" "${IMAGE_NAME}" "${profile}"
done
