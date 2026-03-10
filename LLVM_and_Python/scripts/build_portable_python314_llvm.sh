#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14.3}"
LLVM_ENV_NAME="${LLVM_ENV_NAME:-llvm-toolchain}"
PY_ENV_NAME="${PY_ENV_NAME:-python314-opt}"
IMAGE_TAG="${IMAGE_TAG:-nx-offline-python314-builder:rh88}"
BASE_IMAGE="${BASE_IMAGE:-rockylinux:8.8}"
DOCKER_RETRY_COUNT="${DOCKER_RETRY_COUNT:-3}"
DOCKER_RETRY_DELAY_SEC="${DOCKER_RETRY_DELAY_SEC:-5}"

mkdir -p "${ARTIFACT_DIR}"

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
  echo "[host] Using temporary anonymous DOCKER_CONFIG for public registry pulls"
}

run_with_retry() {
  local attempt=1
  while true; do
    if "$@"; then
      return 0
    fi

    if (( attempt >= DOCKER_RETRY_COUNT )); then
      echo "[host] Command failed after ${attempt} attempt(s): $*" >&2
      return 1
    fi

    echo "[host] Command failed (attempt ${attempt}/${DOCKER_RETRY_COUNT}): $*" >&2
    echo "[host] Retrying in ${DOCKER_RETRY_DELAY_SEC}s..." >&2
    sleep "${DOCKER_RETRY_DELAY_SEC}"
    attempt=$((attempt + 1))
  done
}

require_docker_daemon
prepare_public_registry_access

echo "[host 1/4] Pulling base image ${BASE_IMAGE}"
run_with_retry docker pull "${BASE_IMAGE}"

echo "[host 1/4] Building Docker image ${IMAGE_TAG}"
run_with_retry docker build \
  --pull=false \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  -t "${IMAGE_TAG}" \
  -f "${ROOT_DIR}/docker/Dockerfile" \
  "${ROOT_DIR}"

echo "[host 2/4] Building portable LLVM + Python bundles"
docker run --rm \
  -e PYTHON_VERSION="${PYTHON_VERSION}" \
  -e LLVM_ENV_NAME="${LLVM_ENV_NAME}" \
  -e PY_ENV_NAME="${PY_ENV_NAME}" \
  -e WORK_DIR=/work \
  -e ARTIFACT_DIR=/work/artifacts \
  -v "${ROOT_DIR}:/work" \
  "${IMAGE_TAG}"

LLVM_BUNDLE="${ARTIFACT_DIR}/${LLVM_ENV_NAME}-rhel8.8.tar.gz"
PY_BUNDLE="${ARTIFACT_DIR}/${PY_ENV_NAME}-python-${PYTHON_VERSION}-rhel8.8.tar.gz"

if [[ ! -f "${LLVM_BUNDLE}" ]]; then
  echo "Expected LLVM bundle not found: ${LLVM_BUNDLE}" >&2
  exit 1
fi
if [[ ! -f "${PY_BUNDLE}" ]]; then
  echo "Expected Python bundle not found: ${PY_BUNDLE}" >&2
  exit 1
fi

echo "[host 3/4] Running offline simulation verification"
"${ROOT_DIR}/scripts/verify_offline_bundle.sh" "${LLVM_BUNDLE}" "${PY_BUNDLE}" "${IMAGE_TAG}"

echo "[host 4/4] Completed"
echo "LLVM bundle: ${LLVM_BUNDLE}"
echo "LLVM checksum: ${LLVM_BUNDLE}.sha256"
echo "Python bundle: ${PY_BUNDLE}"
echo "Python checksum: ${PY_BUNDLE}.sha256"
echo "Installer script: ${ARTIFACT_DIR}/install_portable_envs.csh"
echo "Env setup scripts: ${ARTIFACT_DIR}/start_llvm_only.csh ${ARTIFACT_DIR}/start_python_only.csh ${ARTIFACT_DIR}/start_llvm_python.csh"
