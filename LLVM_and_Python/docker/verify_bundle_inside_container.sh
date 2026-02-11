#!/usr/bin/env bash
set -euo pipefail

LLVM_BUNDLE_FILE="${LLVM_BUNDLE_FILE:-}"
PY_BUNDLE_FILE="${PY_BUNDLE_FILE:-}"

if [[ -z "${LLVM_BUNDLE_FILE}" || -z "${PY_BUNDLE_FILE}" ]]; then
  echo "LLVM_BUNDLE_FILE and PY_BUNDLE_FILE are required" >&2
  exit 1
fi

LLVM_BUNDLE_PATH="/artifacts/${LLVM_BUNDLE_FILE}"
PY_BUNDLE_PATH="/artifacts/${PY_BUNDLE_FILE}"

if [[ ! -f "${LLVM_BUNDLE_PATH}" ]]; then
  echo "LLVM bundle not found: ${LLVM_BUNDLE_PATH}" >&2
  exit 1
fi
if [[ ! -f "${PY_BUNDLE_PATH}" ]]; then
  echo "Python bundle not found: ${PY_BUNDLE_PATH}" >&2
  exit 1
fi

TEST_ROOT="/tmp/offline-check"
LLVM_ENV_DIR="${TEST_ROOT}/llvm"
PY_ENV_DIR="${TEST_ROOT}/python"

rm -rf "${TEST_ROOT}"
mkdir -p "${LLVM_ENV_DIR}" "${PY_ENV_DIR}"

echo "[verify 1/8] Extracting LLVM bundle"
tar -xzf "${LLVM_BUNDLE_PATH}" -C "${LLVM_ENV_DIR}"

echo "[verify 2/8] Extracting Python bundle"
tar -xzf "${PY_BUNDLE_PATH}" -C "${PY_ENV_DIR}"

if [[ -x "${LLVM_ENV_DIR}/bin/conda-unpack" ]]; then
  PATH="${LLVM_ENV_DIR}/bin:${PATH}" \
  LD_LIBRARY_PATH="${LLVM_ENV_DIR}/lib:${LD_LIBRARY_PATH:-}" \
  "${LLVM_ENV_DIR}/bin/conda-unpack"
fi
if [[ -x "${PY_ENV_DIR}/bin/conda-unpack" ]]; then
  PATH="${PY_ENV_DIR}/bin:${PATH}" \
  LD_LIBRARY_PATH="${PY_ENV_DIR}/lib:${LLVM_ENV_DIR}/lib:${LD_LIBRARY_PATH:-}" \
  "${PY_ENV_DIR}/bin/conda-unpack"
fi

# Backward compatibility for existing bundles built before RUNPATH normalization.
if [[ -x "${LLVM_ENV_DIR}/bin/patchelf" && -x "${PY_ENV_DIR}/bin/python3.14" ]]; then
  "${LLVM_ENV_DIR}/bin/patchelf" --set-rpath '$ORIGIN/../lib' "${PY_ENV_DIR}/bin/python3.14"
fi

echo "[verify 3/8] Verifying Python configure flags"
LD_LIBRARY_PATH="${PY_ENV_DIR}/lib:${LLVM_ENV_DIR}/lib:${LD_LIBRARY_PATH:-}" \
"${PY_ENV_DIR}/bin/python3.14" - <<'PY'
import sysconfig
args = sysconfig.get_config_var("CONFIG_ARGS") or ""
for flag in ("--with-tail-call-interp", "--enable-optimizations", "--with-lto=thin"):
    if flag not in args:
        raise SystemExit(f"Missing configure option after unpack: {flag}")
print("Python configure flags verified")
PY

echo "[verify 4/8] Verifying LLVM tools"
for tool in clang clang++ ld.lld llvm-ar llvm-config llvm-profdata llc opt; do
  if [[ ! -x "${LLVM_ENV_DIR}/bin/${tool}" ]]; then
    echo "Missing LLVM tool in packed env: ${tool}" >&2
    exit 1
  fi
  "${LLVM_ENV_DIR}/bin/${tool}" --version | head -n 1
done

cp /artifacts/start_llvm_only.csh "${TEST_ROOT}/start_llvm_only.csh"
cp /artifacts/start_python_only.csh "${TEST_ROOT}/start_python_only.csh"
cp /artifacts/start_llvm_python.csh "${TEST_ROOT}/start_llvm_python.csh"
chmod +x \
  "${TEST_ROOT}/start_llvm_only.csh" \
  "${TEST_ROOT}/start_python_only.csh" \
  "${TEST_ROOT}/start_llvm_python.csh"

ln -sfn "${LLVM_ENV_DIR}" "${TEST_ROOT}/portable-llvm"
ln -sfn "${PY_ENV_DIR}" "${TEST_ROOT}/portable-python314"

echo "[verify 5/8] CSH env setup smoke test: LLVM only"
/bin/csh -fc "cd ${TEST_ROOT}; source ./start_llvm_only.csh; if ( \"$PATH\" =~ *\"/portable-llvm/bin\"* ) exit 2; endif; clang --version >/dev/null"

echo "[verify 6/8] CSH env setup smoke test: Python only"
/bin/csh -fc "cd ${TEST_ROOT}; source ./start_python_only.csh; python3.14 -c 'import sys; print(sys.version)'"

echo "[verify 7/8] CSH env setup smoke test: LLVM + Python"
/bin/csh -fc "cd ${TEST_ROOT}; source ./start_llvm_python.csh; python3.14 -c 'import sys,sysconfig; print(sys.executable); print(sysconfig.get_config_var(\"CONFIG_ARGS\"))'"

echo "[verify 8/8] Venv activation without start script"
/bin/csh -fc "cd ${TEST_ROOT}; source ./start_python_only.csh; python3.14 -m venv ./venv-smoke"
/bin/csh -fc "set prompt='> '; source ${TEST_ROOT}/venv-smoke/bin/activate.csh; python -V >/dev/null"

echo "Offline verification succeeded"
