#!/bin/csh -f

if ( $#argv != 1 ) then
  echo "Usage: install_portable_envs.csh <install_root_prefix>"
  echo "Example: ./install_portable_envs.csh /opt"
  exit 1
endif

set install_root = "$1"
set script_dir = "$0:h"
if ( "$script_dir" == "" ) then
  set script_dir = "."
endif

set orig_cwd = "$cwd"
cd "$script_dir"
if ( $status != 0 ) then
  echo "Failed to resolve script directory: $script_dir"
  exit 1
endif
set script_dir_abs = "$cwd"
cd "$orig_cwd"

if ( $?LLVM_DIR_NAME ) then
  set llvm_dir_name = "$LLVM_DIR_NAME"
else
  set llvm_dir_name = "llvm21"
endif
if ( $?PYTHON_DIR_NAME ) then
  set python_dir_name = "$PYTHON_DIR_NAME"
else
  set python_dir_name = "python314"
endif

set llvm_bundle = ""
if ( $?LLVM_BUNDLE_FILE ) then
  set llvm_bundle = "$script_dir_abs/$LLVM_BUNDLE_FILE"
else
  set llvm_candidates = ( `find "$script_dir_abs" -maxdepth 1 -type f -name '*llvm*-rhel8.8.tar.gz' ! -name '*python*'` )
  if ( $#llvm_candidates == 1 ) then
    set llvm_bundle = "$llvm_candidates[1]"
  endif
endif

set python_bundle = ""
if ( $?PY_BUNDLE_FILE ) then
  set python_bundle = "$script_dir_abs/$PY_BUNDLE_FILE"
else
  set py_candidates = ( `find "$script_dir_abs" -maxdepth 1 -type f -name '*python*-rhel8.8.tar.gz' ! -name '*llvm*'` )
  if ( $#py_candidates == 1 ) then
    set python_bundle = "$py_candidates[1]"
  endif
endif

if ( "$llvm_bundle" == "" ) then
  echo "Cannot determine LLVM bundle under: $script_dir_abs"
  echo "Set LLVM_BUNDLE_FILE explicitly, e.g.:"
  echo "  setenv LLVM_BUNDLE_FILE llvm-toolchain-rhel8.8.tar.gz"
  exit 1
endif
if ( "$python_bundle" == "" ) then
  echo "Cannot determine Python bundle under: $script_dir_abs"
  echo "Set PY_BUNDLE_FILE explicitly, e.g.:"
  echo "  setenv PY_BUNDLE_FILE python314-opt-python-3.14.3-rhel8.8.tar.gz"
  exit 1
endif

if ( ! -f "$llvm_bundle" ) then
  echo "LLVM bundle not found: $llvm_bundle"
  exit 1
endif

if ( ! -f "$python_bundle" ) then
  echo "Python bundle not found: $python_bundle"
  exit 1
endif

mkdir -p "$install_root"
if ( $status != 0 ) then
  exit $status
endif

cd "$install_root"
if ( $status != 0 ) then
  echo "Cannot access install root: $install_root"
  exit 1
endif
set install_root_abs = "$cwd"
cd "$orig_cwd"

set llvm_prefix = "$install_root_abs/$llvm_dir_name"
set python_prefix = "$install_root_abs/$python_dir_name"
set launcher_dir = "$install_root_abs"

mkdir -p "$llvm_prefix"
mkdir -p "$python_prefix"

tar -xzf "$llvm_bundle" -C "$llvm_prefix"
if ( $status != 0 ) then
  exit $status
endif

tar -xzf "$python_bundle" -C "$python_prefix"
if ( $status != 0 ) then
  exit $status
endif

if ( -x "$llvm_prefix/bin/conda-unpack" && ! -e "$llvm_prefix/.conda_unpacked" ) then
  if ( $?LD_LIBRARY_PATH ) then
    env PATH="$llvm_prefix/bin:$PATH" LD_LIBRARY_PATH="$llvm_prefix/lib:$LD_LIBRARY_PATH" "$llvm_prefix/bin/conda-unpack"
  else
    env PATH="$llvm_prefix/bin:$PATH" LD_LIBRARY_PATH="$llvm_prefix/lib" "$llvm_prefix/bin/conda-unpack"
  endif
  if ( $status != 0 ) then
    exit $status
  endif
  touch "$llvm_prefix/.conda_unpacked"
endif

if ( -x "$python_prefix/bin/conda-unpack" && ! -e "$python_prefix/.conda_unpacked" ) then
  if ( $?LD_LIBRARY_PATH ) then
    env PATH="$python_prefix/bin:$PATH" LD_LIBRARY_PATH="$python_prefix/lib:$LD_LIBRARY_PATH" "$python_prefix/bin/conda-unpack"
  else
    env PATH="$python_prefix/bin:$PATH" LD_LIBRARY_PATH="$python_prefix/lib" "$python_prefix/bin/conda-unpack"
  endif
  if ( $status != 0 ) then
    exit $status
  endif
  touch "$python_prefix/.conda_unpacked"
endif

set patchelf_bin = ""
if ( -x "$llvm_prefix/bin/patchelf" ) then
  set patchelf_bin = "$llvm_prefix/bin/patchelf"
else if ( -x "/usr/bin/patchelf" ) then
  set patchelf_bin = "/usr/bin/patchelf"
endif

if ( "$patchelf_bin" != "" ) then
  if ( -x "$python_prefix/bin/python3.14" ) then
    "$patchelf_bin" --set-rpath '$ORIGIN/../lib' "$python_prefix/bin/python3.14"
    if ( $status != 0 ) then
      exit $status
    endif
  endif
else
  echo "Warning: patchelf not found; venv activation may need start_python_only.csh beforehand."
endif

foreach launcher (start_llvm_only.csh start_python_only.csh start_llvm_python.csh)
  set src = "$script_dir_abs/$launcher"
  set dst = "$launcher_dir/$launcher"
  if ( ! -f "$src" ) then
    echo "Missing launcher script beside installer: $src"
    exit 1
  endif
  if ( "$src" != "$dst" ) then
    cp "$src" "$dst"
    if ( $status != 0 ) then
      exit $status
    endif
  endif
  chmod +x "$dst"
end

ln -sfn "$llvm_prefix" "$launcher_dir/portable-llvm"
ln -sfn "$python_prefix" "$launcher_dir/portable-python314"

echo "Installed LLVM env at: $llvm_prefix"
echo "Installed Python env at: $python_prefix"
echo "Copied environment setup scripts to: $launcher_dir"
echo "Created defaults for no-argument setup:"
echo "  $launcher_dir/portable-llvm -> $llvm_prefix"
echo "  $launcher_dir/portable-python314 -> $python_prefix"
echo "Use environment setup scripts in current shell:"
echo "  cd $launcher_dir"
echo "  source ./start_llvm_only.csh"
echo "  source ./start_python_only.csh"
echo "  source ./start_llvm_python.csh"
