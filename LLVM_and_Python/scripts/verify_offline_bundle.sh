#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <llvm-bundle-tar.gz> <python-bundle-tar.gz> [docker-image-tag]" >&2
  exit 1
fi

LLVM_BUNDLE="$(realpath "$1")"
PY_BUNDLE="$(realpath "$2")"
IMAGE_TAG="${3:-${IMAGE_TAG:-nx-offline-python314-builder:rh88}}"
ARTIFACT_DIR="$(dirname "${LLVM_BUNDLE}")"
LLVM_BUNDLE_FILE="$(basename "${LLVM_BUNDLE}")"
PY_BUNDLE_FILE="$(basename "${PY_BUNDLE}")"

require_docker_daemon() {
  local docker_check_log
  docker_check_log="$(mktemp)"
  if docker version >"${docker_check_log}" 2>&1; then
    rm -f "${docker_check_log}"
    return 0
  fi

  cat >&2 <<'EOF'
Docker daemon is not reachable.

If you are running this script from WSL:
  1. Start Docker Desktop on Windows.
  2. Enable "Use the WSL 2 based engine".
  3. Enable WSL integration for the distro you are using.
  4. Wait until `docker version` shows both Client and Server.
  5. If Docker Desktop was already open, run `wsl --shutdown` on Windows and retry.
EOF
  cat "${docker_check_log}" >&2
  rm -f "${docker_check_log}"
  exit 1
}

prepare_public_registry_access() {
  if [[ "${NX_OFFLINE_USE_HOST_DOCKER_CONFIG:-0}" == "1" ]]; then
    return 0
  fi

  local temp_docker_config
  temp_docker_config="$(mktemp -d)"
  printf '{\n  "auths": {}\n}\n' > "${temp_docker_config}/config.json"
  export DOCKER_CONFIG="${temp_docker_config}"
  trap "rm -rf '${temp_docker_config}'" EXIT
  echo "[verify-host] Using temporary anonymous DOCKER_CONFIG for public registry access"
}

if [[ ! -f "${LLVM_BUNDLE}" ]]; then
  echo "LLVM bundle not found: ${LLVM_BUNDLE}" >&2
  exit 1
fi
if [[ ! -f "${PY_BUNDLE}" ]]; then
  echo "Python bundle not found: ${PY_BUNDLE}" >&2
  exit 1
fi

for helper in install_portable_envs.csh repair_python_sysconfig.py start_llvm_only.csh start_python_only.csh start_llvm_python.csh python-build-metadata.txt; do
  if [[ ! -f "${ARTIFACT_DIR}/${helper}" ]]; then
    echo "Missing helper script in artifact directory: ${helper}" >&2
    exit 1
  fi
done

require_docker_daemon
prepare_public_registry_access

echo "[verify-host] Testing bundles in offline Docker mode (--network none)"
docker run --rm --network none \
  --entrypoint /usr/local/bin/verify_bundle_inside_container.sh \
  -e LLVM_BUNDLE_FILE="${LLVM_BUNDLE_FILE}" \
  -e PY_BUNDLE_FILE="${PY_BUNDLE_FILE}" \
  -v "${ARTIFACT_DIR}:/artifacts:ro" \
  "${IMAGE_TAG}"
