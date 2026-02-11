#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ARTIFACT_DIR:-${ROOT_DIR}/artifacts}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14.3}"
LLVM_ENV_NAME="${LLVM_ENV_NAME:-llvm-toolchain}"
PY_ENV_NAME="${PY_ENV_NAME:-python314-opt}"
IMAGE_TAG="${IMAGE_TAG:-nx-offline-python314-builder:rh88}"

mkdir -p "${ARTIFACT_DIR}"

echo "[host 1/4] Building Docker image ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" -f "${ROOT_DIR}/docker/Dockerfile" "${ROOT_DIR}"

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
