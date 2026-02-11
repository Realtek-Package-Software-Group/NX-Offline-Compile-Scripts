#!/usr/bin/env bash
set -euo pipefail

PYTHON_VERSION="${PYTHON_VERSION:-3.14.3}"
WORK_DIR="${WORK_DIR:-/work}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${WORK_DIR}/artifacts}"
BUILD_DIR="${BUILD_DIR:-${WORK_DIR}/.build}"
MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-/opt/micromamba}"

LLVM_ENV_NAME="${LLVM_ENV_NAME:-llvm-toolchain}"
PY_ENV_NAME="${PY_ENV_NAME:-python314-opt}"

LLVM_ENV_PREFIX="${MAMBA_ROOT_PREFIX}/envs/${LLVM_ENV_NAME}"
PY_ENV_PREFIX="${MAMBA_ROOT_PREFIX}/envs/${PY_ENV_NAME}"

PYTHON_TARBALL="Python-${PYTHON_VERSION}.tar.xz"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_TARBALL}"
PYTHON_SRC_DIR="${BUILD_DIR}/Python-${PYTHON_VERSION}"

LLVM_BUNDLE_NAME="${LLVM_ENV_NAME}-rhel8.8.tar.gz"
PY_BUNDLE_NAME="${PY_ENV_NAME}-python-${PYTHON_VERSION}-rhel8.8.tar.gz"
LLVM_BUNDLE_PATH="${ARTIFACT_DIR}/${LLVM_BUNDLE_NAME}"
PY_BUNDLE_PATH="${ARTIFACT_DIR}/${PY_BUNDLE_NAME}"

mkdir -p "${ARTIFACT_DIR}" "${BUILD_DIR}"

export MAMBA_ROOT_PREFIX
export CONDA_PKGS_DIRS="${BUILD_DIR}/conda-pkgs"

if [[ -f "${MAMBA_ROOT_PREFIX}/etc/profile.d/mamba.sh" ]]; then
  # shellcheck source=/dev/null
  source "${MAMBA_ROOT_PREFIX}/etc/profile.d/mamba.sh"
fi

if ! command -v micromamba >/dev/null 2>&1; then
  echo "micromamba not found" >&2
  exit 1
fi

ensure_env_packages() {
  local env_name="$1"
  shift
  if ! micromamba env list | awk '{print $1}' | grep -qx "${env_name}"; then
    micromamba create -y -n "${env_name}" -c conda-forge "$@"
  else
    micromamba install -y -n "${env_name}" -c conda-forge "$@"
  fi
}

llvm_base_pkgs=(
  clang
  clangxx
  llvm
  llvmdev
  llvm-tools
  lld
  llvm-openmp
  cmake
  ninja
  make
  pkg-config
  patchelf
)

llvm_optional_pkgs=(
  clang-tools
  compiler-rt
  lldb
  libcxx
  libcxxabi
  libunwind
  libclang
  libclang-cpp
  libtirpc
)

python_base_pkgs=(
  bzip2
  ca-certificates
  expat
  gdbm
  libffi
  libnsl
  libuuid
  ncurses
  openssl
  pkg-config
  readline
  sqlite
  tk
  xz
  zlib
  zstd
)

echo "[1/10] Creating/updating LLVM environment: ${LLVM_ENV_NAME}"
ensure_env_packages "${LLVM_ENV_NAME}" "${llvm_base_pkgs[@]}"

echo "[2/10] Installing optional LLVM packages when available"
for pkg in "${llvm_optional_pkgs[@]}"; do
  if micromamba install -y -n "${LLVM_ENV_NAME}" -c conda-forge "${pkg}" >/tmp/micromamba-${pkg}.log 2>&1; then
    echo "  - installed ${pkg}"
  else
    echo "  - skipped ${pkg} (not available for this platform/channel)"
  fi
done

echo "[3/10] Creating/updating Python runtime environment: ${PY_ENV_NAME}"
ensure_env_packages "${PY_ENV_NAME}" "${python_base_pkgs[@]}"

eval "$(micromamba shell hook -s bash)"
micromamba activate "${LLVM_ENV_NAME}"

echo "[4/10] Downloading Python ${PYTHON_VERSION} source"
rm -rf "${PYTHON_SRC_DIR}" "${BUILD_DIR}/${PYTHON_TARBALL}"
curl -fL "${PYTHON_URL}" -o "${BUILD_DIR}/${PYTHON_TARBALL}"
tar -xJf "${BUILD_DIR}/${PYTHON_TARBALL}" -C "${BUILD_DIR}"

pushd "${PYTHON_SRC_DIR}" >/dev/null

echo "[5/10] Configuring CPython against separate Python prefix"
export PATH="${LLVM_ENV_PREFIX}/bin:${PY_ENV_PREFIX}/bin:${PATH}"
export CC="${LLVM_ENV_PREFIX}/bin/clang"
export CXX="${LLVM_ENV_PREFIX}/bin/clang++"
export AR="${LLVM_ENV_PREFIX}/bin/llvm-ar"
export NM="${LLVM_ENV_PREFIX}/bin/llvm-nm"
export RANLIB="${LLVM_ENV_PREFIX}/bin/llvm-ranlib"
export LD="${LLVM_ENV_PREFIX}/bin/ld.lld"
export LLVM_PROFDATA="${LLVM_ENV_PREFIX}/bin/llvm-profdata"
export CPPFLAGS="-I${PY_ENV_PREFIX}/include"
export CFLAGS="-O3 -fPIC"
export CXXFLAGS="-O3 -fPIC"
export LDFLAGS="-L${PY_ENV_PREFIX}/lib -Wl,-rpath,${PY_ENV_PREFIX}/lib -L${LLVM_ENV_PREFIX}/lib -Wl,-rpath,${LLVM_ENV_PREFIX}/lib -fuse-ld=lld"
export PKG_CONFIG_PATH="${PY_ENV_PREFIX}/lib/pkgconfig:${LLVM_ENV_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}"

./configure \
  --prefix="${PY_ENV_PREFIX}" \
  --with-openssl="${PY_ENV_PREFIX}" \
  --with-openssl-rpath=auto \
  --with-tail-call-interp \
  --enable-optimizations \
  --with-lto=thin \
  --enable-shared \
  --with-ensurepip=install

echo "[6/10] Building and installing CPython (PGO + ThinLTO)"
make -j"$(nproc)"
make install

popd >/dev/null

if [[ ! -x "${PY_ENV_PREFIX}/bin/python3.14" ]]; then
  echo "Expected ${PY_ENV_PREFIX}/bin/python3.14 not found" >&2
  exit 1
fi
ln -sfn python3.14 "${PY_ENV_PREFIX}/bin/python3"
ln -sfn python3 "${PY_ENV_PREFIX}/bin/python"

echo "[7/10] Normalizing Python RUNPATH for portable venv usage"
if [[ -x "${LLVM_ENV_PREFIX}/bin/patchelf" ]]; then
  "${LLVM_ENV_PREFIX}/bin/patchelf" --set-rpath '$ORIGIN/../lib' "${PY_ENV_PREFIX}/bin/python3.14"
else
  echo "Warning: patchelf not available; python3.14 RUNPATH left as-is"
fi

echo "[8/10] Running build-time validation"
LD_LIBRARY_PATH="${PY_ENV_PREFIX}/lib:${LLVM_ENV_PREFIX}/lib:${LD_LIBRARY_PATH:-}" \
"${PY_ENV_PREFIX}/bin/python3.14" - <<'PY'
import json
import sys
import sysconfig

config_args = sysconfig.get_config_var("CONFIG_ARGS") or ""
required = [
    "--with-tail-call-interp",
    "--enable-optimizations",
    "--with-lto=thin",
]
missing = [flag for flag in required if flag not in config_args]
if missing:
    raise SystemExit(f"Missing config flags in CONFIG_ARGS: {missing}\\n{config_args}")
print(json.dumps({
    "python_version": sys.version,
    "python_binary": sys.executable,
    "config_args": config_args,
}, indent=2))
PY

required_tools=(
  clang
  clang++
  ld.lld
  lld
  llvm-ar
  llvm-config
  llvm-nm
  llvm-objdump
  llvm-profdata
  llvm-ranlib
  llvm-readelf
  llvm-symbolizer
  llc
  opt
)

for tool in "${required_tools[@]}"; do
  if [[ ! -x "${LLVM_ENV_PREFIX}/bin/${tool}" ]]; then
    echo "Missing required LLVM tool: ${tool}" >&2
    exit 1
  fi
done

{
  echo "# LLVM Tool Versions"
  for tool in "${required_tools[@]}"; do
    ver="$(${LLVM_ENV_PREFIX}/bin/${tool} --version 2>/dev/null | head -n 1 || true)"
    echo "${tool}: ${ver}"
  done
} > "${ARTIFACT_DIR}/llvm-tool-versions.txt"

{
  echo "# Python Build Metadata"
  echo "python_env_name=${PY_ENV_NAME}"
  echo "python_version=${PYTHON_VERSION}"
  echo "python_bin=bin/python3.14"
} > "${ARTIFACT_DIR}/python-build-metadata.txt"

echo "[9/10] Packing LLVM environment"
rm -f "${LLVM_BUNDLE_PATH}"
conda-pack -p "${LLVM_ENV_PREFIX}" -o "${LLVM_BUNDLE_PATH}"

echo "[10/10] Packing Python environment"
rm -f "${PY_BUNDLE_PATH}"
conda-pack -p "${PY_ENV_PREFIX}" -o "${PY_BUNDLE_PATH}"

cp "${WORK_DIR}/scripts/offline/install_portable_envs.csh" "${ARTIFACT_DIR}/install_portable_envs.csh"
cp "${WORK_DIR}/scripts/offline/start_llvm_only.csh" "${ARTIFACT_DIR}/start_llvm_only.csh"
cp "${WORK_DIR}/scripts/offline/start_python_only.csh" "${ARTIFACT_DIR}/start_python_only.csh"
cp "${WORK_DIR}/scripts/offline/start_llvm_python.csh" "${ARTIFACT_DIR}/start_llvm_python.csh"
# Remove legacy helper names from previous single-prefix workflow.
rm -f \
  "${ARTIFACT_DIR}/install_portable_env.sh" \
  "${ARTIFACT_DIR}/start_portable_env.sh" \
  "${ARTIFACT_DIR}/start_portable_python.sh" \
  "${ARTIFACT_DIR}/portable-python-bin.txt"
chmod +x \
  "${ARTIFACT_DIR}/install_portable_envs.csh" \
  "${ARTIFACT_DIR}/start_llvm_only.csh" \
  "${ARTIFACT_DIR}/start_python_only.csh" \
  "${ARTIFACT_DIR}/start_llvm_python.csh"

(
  cd "${ARTIFACT_DIR}"
  sha256sum "${LLVM_BUNDLE_NAME}" > "${LLVM_BUNDLE_NAME}.sha256"
  sha256sum "${PY_BUNDLE_NAME}" > "${PY_BUNDLE_NAME}.sha256"
)

echo "[11/11] Build complete"
echo "LLVM bundle: ${LLVM_BUNDLE_PATH}"
echo "Python bundle: ${PY_BUNDLE_PATH}"
echo "LLVM checksum: ${LLVM_BUNDLE_PATH}.sha256"
echo "Python checksum: ${PY_BUNDLE_PATH}.sha256"
