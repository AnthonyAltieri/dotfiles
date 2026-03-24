#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_NAME="${IMAGE_NAME:-dotfiles-nix-smoke:ubuntu-24.04}"
DOCKERFILE="${REPO_ROOT}/tests/docker/ubuntu-lts/Dockerfile"

host_arch="$(uname -m)"
case "${host_arch}" in
  arm64|aarch64)
    linux_suffix="aarch64-linux"
    ;;
  x86_64|amd64)
    linux_suffix="x86_64-linux"
    ;;
  *)
    echo "Unsupported host architecture for Docker smoke tests: ${host_arch}" >&2
    exit 1
    ;;
esac

resolve_profile() {
  local profile="$1"
  case "${profile}" in
    personal)
      if [[ "${linux_suffix}" == "aarch64-linux" ]]; then
        echo "personal-aarch64-linux"
      else
        echo "personal-linux"
      fi
      ;;
    work)
      if [[ "${linux_suffix}" == "aarch64-linux" ]]; then
        echo "work-aarch64-linux"
      else
        echo "work-linux"
      fi
      ;;
    sandbox)
      echo "sandbox-${linux_suffix}"
      ;;
    personal-linux|personal-aarch64-linux|work-linux|work-aarch64-linux|sandbox-x86_64-linux|sandbox-aarch64-linux)
      echo "${profile}"
      ;;
    *)
      echo "Unsupported smoke-test profile: ${profile}" >&2
      exit 1
      ;;
  esac
}

profiles=("$@")
if [[ "${#profiles[@]}" -eq 0 ]]; then
  profiles=(
    personal
    work
    sandbox
  )
fi

docker build --pull -f "${DOCKERFILE}" -t "${IMAGE_NAME}" "${REPO_ROOT}"

for profile in "${profiles[@]}"; do
  resolved_profile="$(resolve_profile "${profile}")"
  echo "==> Running Docker smoke test for ${profile} (${resolved_profile})"
  docker run --rm -e FULL_ACTIVATE="${FULL_ACTIVATE:-0}" "${IMAGE_NAME}" "${profile}"
done
