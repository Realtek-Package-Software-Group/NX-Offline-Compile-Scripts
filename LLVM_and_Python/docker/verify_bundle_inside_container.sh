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
STAGE_DIR="${TEST_ROOT}/stage"
INSTALL_ROOT="${TEST_ROOT}/install"
LLVM_ENV_DIR="${INSTALL_ROOT}/portable-llvm"
PY_ENV_DIR="${INSTALL_ROOT}/portable-python314"

rm -rf "${TEST_ROOT}"
mkdir -p "${STAGE_DIR}" "${INSTALL_ROOT}"

echo "[verify 1/10] Staging installer inputs"
for helper in install_portable_envs.csh repair_python_sysconfig.py start_llvm_only.csh start_python_only.csh start_llvm_python.csh python-build-metadata.txt; do
  if [[ ! -f "/artifacts/${helper}" ]]; then
    echo "Missing helper in artifact directory: ${helper}" >&2
    exit 1
  fi
  cp "/artifacts/${helper}" "${STAGE_DIR}/${helper}"
done
chmod +x \
  "${STAGE_DIR}/install_portable_envs.csh" \
  "${STAGE_DIR}/repair_python_sysconfig.py" \
  "${STAGE_DIR}/start_llvm_only.csh" \
  "${STAGE_DIR}/start_python_only.csh" \
  "${STAGE_DIR}/start_llvm_python.csh"
ln -s "${LLVM_BUNDLE_PATH}" "${STAGE_DIR}/${LLVM_BUNDLE_FILE}"
ln -s "${PY_BUNDLE_PATH}" "${STAGE_DIR}/${PY_BUNDLE_FILE}"

echo "[verify 2/10] Installing portable environments"
/bin/csh -fc "cd ${STAGE_DIR}; ./install_portable_envs.csh ${INSTALL_ROOT}"

echo "[verify 3/10] Verifying Python configure flags"
LD_LIBRARY_PATH="${PY_ENV_DIR}/lib:${LLVM_ENV_DIR}/lib:${LD_LIBRARY_PATH:-}" \
"${PY_ENV_DIR}/bin/python3.14" - <<'PY'
import sysconfig
args = sysconfig.get_config_var("CONFIG_ARGS") or ""
for flag in ("--with-tail-call-interp", "--enable-optimizations", "--with-lto=thin"):
    if flag not in args:
        raise SystemExit(f"Missing configure option after unpack: {flag}")
print("Python configure flags verified")
PY

echo "[verify 4/10] Verifying Qt/X11 runtime libraries for PyQt/PySide"
required_qt_runtime_globs=(
  "libX11.so*"
  "libXcursor.so*"
  "libXrender.so*"
  "libXrandr.so*"
  "libXi.so*"
  "libxcb.so*"
  "libxcb-cursor.so*"
  "libxcb-icccm.so*"
  "libxcb-image.so*"
  "libxcb-keysyms.so*"
  "libxcb-render-util.so*"
  "libxcb-util.so*"
  "libxkbcommon.so*"
)
for pattern in "${required_qt_runtime_globs[@]}"; do
  if ! find "${PY_ENV_DIR}/lib" -maxdepth 1 -name "${pattern}" | grep -q .; then
    echo "Missing Qt/X11 runtime library after install: ${pattern}" >&2
    exit 1
  fi
done

echo "[verify 5/10] Verifying LLVM tools"
for tool in ccache clang clang++ ld.lld llvm-ar llvm-config llvm-profdata llc opt; do
  if [[ ! -x "${LLVM_ENV_DIR}/bin/${tool}" ]]; then
    echo "Missing LLVM tool in packed env: ${tool}" >&2
    exit 1
  fi
  LD_LIBRARY_PATH="${LLVM_ENV_DIR}/lib:${LD_LIBRARY_PATH:-}" \
  "${LLVM_ENV_DIR}/bin/${tool}" --version | head -n 1
done

cat > "${TEST_ROOT}/compiler_smoke.py" <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import shlex
import subprocess
import sysconfig
import tempfile

workdir = Path(tempfile.mkdtemp(prefix="portable-compiler-smoke-"))
source = workdir / "smoke.c"
object_file = workdir / "smoke.o"
shared_object = workdir / f"smoke{sysconfig.get_config_var('EXT_SUFFIX') or '.so'}"

source.write_text("int smoke_value(void) { return 42; }\n", encoding="utf-8")

cc = os.environ.get("CC") or sysconfig.get_config_var("CC")
ldshared = os.environ.get("LDSHARED") or sysconfig.get_config_var("LDSHARED")
cppflags = os.environ.get("CPPFLAGS", "")
cflags = os.environ.get("CFLAGS") or sysconfig.get_config_var("CFLAGS") or ""
ccshared = sysconfig.get_config_var("CCSHARED") or ""
ldflags = os.environ.get("LDFLAGS", "")

if not cc or not ldshared:
    raise SystemExit("missing CC or LDSHARED for compiler smoke test")
if os.environ.get("CC") and len(shlex.split(os.environ["CC"])) != 1:
    raise SystemExit(f"CC must be a single executable path for Nuitka/SCons compatibility: {os.environ['CC']}")

compile_cmd = shlex.split(cc) + shlex.split(cflags) + shlex.split(cppflags) + shlex.split(ccshared)
for include_dir in (sysconfig.get_path("include"), sysconfig.get_path("platinclude")):
    if include_dir:
        compile_cmd.append(f"-I{include_dir}")
compile_cmd += ["-c", str(source), "-o", str(object_file)]

link_cmd = shlex.split(ldshared) + shlex.split(ldflags) + [str(object_file), "-o", str(shared_object)]

subprocess.check_call(compile_cmd)
subprocess.check_call(link_cmd)
print(shared_object)
PY

echo "[verify 6/10] CSH env setup smoke test: LLVM only"
/bin/csh -fc "cd ${INSTALL_ROOT}; source ./start_llvm_only.csh ${INSTALL_ROOT}/portable-llvm ${TEST_ROOT}/ccache-llvm-only; if ( \"\$PATH\" =~ *\"/portable-llvm/bin\"* ) exit 2; endif; if ( ! \$?CCACHE_DIR ) exit 3; endif; if ( \"\$CCACHE_DIR\" != \"${TEST_ROOT}/ccache-llvm-only\" ) exit 4; endif; clang --version >/dev/null; ccache --version >/dev/null"

echo "[verify 7/10] CSH env setup smoke test: Python only"
/bin/csh -fc "cd ${INSTALL_ROOT}; source ./start_python_only.csh; python3.14 -c 'import sys; print(sys.version)'; pip --version > ${TEST_ROOT}/pip-version.txt; pip3 --version > ${TEST_ROOT}/pip3-version.txt"
grep -q "${INSTALL_ROOT}/python314" "${TEST_ROOT}/pip-version.txt"
grep -q "${INSTALL_ROOT}/python314" "${TEST_ROOT}/pip3-version.txt"

echo "[verify 8/10] CSH env setup smoke test: LLVM + Python"
/bin/csh -fc "cd ${INSTALL_ROOT}; source ./start_llvm_python.csh ${INSTALL_ROOT}/portable-llvm ${INSTALL_ROOT}/portable-python314 ${TEST_ROOT}/ccache-llvm-python; if ( ! \$?CCACHE_DIR ) exit 3; endif; if ( \"\$CCACHE_DIR\" != \"${TEST_ROOT}/ccache-llvm-python\" ) exit 4; endif; python3.14 -c 'import sys,sysconfig; print(sys.executable); print(sysconfig.get_config_var(\"CONFIG_ARGS\"))'"

echo "[verify 9/10] Compiler smoke test for relocated Python"
/bin/csh -fc "cd ${INSTALL_ROOT}; source ./start_llvm_python.csh; python3.14 ${TEST_ROOT}/compiler_smoke.py"

echo "[verify 10/10] Venv activation without start script"
/bin/csh -fc "cd ${INSTALL_ROOT}; source ./start_python_only.csh; python3.14 -m venv ${TEST_ROOT}/venv-smoke"
/bin/csh -fc "set prompt='> '; source ${TEST_ROOT}/venv-smoke/bin/activate.csh; python -V >/dev/null"

echo "Offline verification succeeded"
