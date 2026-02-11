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

if [[ ! -f "${LLVM_BUNDLE}" ]]; then
  echo "LLVM bundle not found: ${LLVM_BUNDLE}" >&2
  exit 1
fi
if [[ ! -f "${PY_BUNDLE}" ]]; then
  echo "Python bundle not found: ${PY_BUNDLE}" >&2
  exit 1
fi

for helper in install_portable_envs.csh start_llvm_only.csh start_python_only.csh start_llvm_python.csh; do
  if [[ ! -f "${ARTIFACT_DIR}/${helper}" ]]; then
    echo "Missing helper script in artifact directory: ${helper}" >&2
    exit 1
  fi
done

echo "[verify-host] Testing bundles in offline Docker mode (--network none)"
docker run --rm --network none \
  --entrypoint /usr/local/bin/verify_bundle_inside_container.sh \
  -e LLVM_BUNDLE_FILE="${LLVM_BUNDLE_FILE}" \
  -e PY_BUNDLE_FILE="${PY_BUNDLE_FILE}" \
  -v "${ARTIFACT_DIR}:/artifacts:ro" \
  "${IMAGE_TAG}"
