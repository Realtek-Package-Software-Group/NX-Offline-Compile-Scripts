#!/bin/csh -f

if ( $#argv != 0 && $#argv != 2 ) then
  echo "Usage: source start_llvm_python.csh [llvm_prefix python_prefix]"
  exit 1
endif

if ( $#argv == 2 ) then
  set llvm_prefix = "$1"
  set python_prefix = "$2"
else
  set llvm_prefix = "$cwd/portable-llvm"
  set python_prefix = "$cwd/portable-python314"
  echo "No prefixes specified, using defaults:"
  echo "  llvm_prefix=$llvm_prefix"
  echo "  python_prefix=$python_prefix"
endif

if ( ! -d "$llvm_prefix" ) then
  echo "LLVM prefix not found: $llvm_prefix"
  if ( $#argv == 0 ) then
    echo "Hint: put portable LLVM under ./portable-llvm or pass explicit paths."
  endif
  exit 1
endif

if ( ! -d "$python_prefix" ) then
  echo "Python prefix not found: $python_prefix"
  if ( $#argv == 0 ) then
    echo "Hint: put portable Python under ./portable-python314 or pass explicit paths."
  endif
  exit 1
endif

if ( ! $?PORTABLE_ORIG_PATH ) then
  setenv PORTABLE_ORIG_PATH "$PATH"
endif
if ( ! $?PORTABLE_ORIG_LD_LIBRARY_PATH ) then
  if ( $?LD_LIBRARY_PATH ) then
    setenv PORTABLE_ORIG_LD_LIBRARY_PATH "$LD_LIBRARY_PATH"
  else
    setenv PORTABLE_ORIG_LD_LIBRARY_PATH "__EMPTY__"
  endif
endif
if ( ! $?PORTABLE_ORIG_LIBRARY_PATH ) then
  if ( $?LIBRARY_PATH ) then
    setenv PORTABLE_ORIG_LIBRARY_PATH "$LIBRARY_PATH"
  else
    setenv PORTABLE_ORIG_LIBRARY_PATH "__EMPTY__"
  endif
endif
if ( ! $?PORTABLE_ORIG_CPATH ) then
  if ( $?CPATH ) then
    setenv PORTABLE_ORIG_CPATH "$CPATH"
  else
    setenv PORTABLE_ORIG_CPATH "__EMPTY__"
  endif
endif
if ( ! $?PORTABLE_ORIG_PKG_CONFIG_PATH ) then
  if ( $?PKG_CONFIG_PATH ) then
    setenv PORTABLE_ORIG_PKG_CONFIG_PATH "$PKG_CONFIG_PATH"
  else
    setenv PORTABLE_ORIG_PKG_CONFIG_PATH "__EMPTY__"
  endif
endif

set llvm_bin = "$llvm_prefix/.llvm-bin"
mkdir -p "$llvm_bin"
foreach binpath ( "$llvm_prefix"/bin/* )
  if ( ! -x "$binpath" ) continue
  set base = "$binpath:t"
  if ( "$base" =~ python* ) continue
  if ( "$base" =~ pip* ) continue
  if ( "$base" =~ idle* ) continue
  if ( "$base" =~ pydoc* ) continue
  if ( "$base" =~ 2to3* ) continue
  ln -sfn "$binpath" "$llvm_bin/$base"
end

setenv PATH "$python_prefix/bin:${llvm_bin}:$PORTABLE_ORIG_PATH"
if ( "$PORTABLE_ORIG_LD_LIBRARY_PATH" == "__EMPTY__" ) then
  setenv LD_LIBRARY_PATH "$python_prefix/lib:$llvm_prefix/lib"
else
  setenv LD_LIBRARY_PATH "$python_prefix/lib:$llvm_prefix/lib:$PORTABLE_ORIG_LD_LIBRARY_PATH"
endif

if ( -x "$llvm_prefix/bin/conda-unpack" && ! -e "$llvm_prefix/.conda_unpacked" ) then
  "$llvm_prefix/bin/conda-unpack"
  if ( $status != 0 ) then
    exit $status
  endif
  touch "$llvm_prefix/.conda_unpacked"
endif

if ( -x "$python_prefix/bin/conda-unpack" && ! -e "$python_prefix/.conda_unpacked" ) then
  "$python_prefix/bin/conda-unpack"
  if ( $status != 0 ) then
    exit $status
  endif
  touch "$python_prefix/.conda_unpacked"
endif

set py_bin = "$python_prefix/bin/python3.14"
if ( ! -x "$py_bin" ) then
  set py_bin = "$python_prefix/bin/python3"
endif
if ( ! -x "$py_bin" ) then
  set py_bin = "$python_prefix/bin/python"
endif
if ( ! -x "$py_bin" ) then
  echo "No python executable found under: $python_prefix/bin"
  exit 1
endif

if ( "$PORTABLE_ORIG_LIBRARY_PATH" == "__EMPTY__" ) then
  setenv LIBRARY_PATH "$python_prefix/lib:$llvm_prefix/lib"
else
  setenv LIBRARY_PATH "$python_prefix/lib:$llvm_prefix/lib:$PORTABLE_ORIG_LIBRARY_PATH"
endif
if ( "$PORTABLE_ORIG_CPATH" == "__EMPTY__" ) then
  setenv CPATH "$python_prefix/include:$llvm_prefix/include"
else
  setenv CPATH "$python_prefix/include:$llvm_prefix/include:$PORTABLE_ORIG_CPATH"
endif
if ( "$PORTABLE_ORIG_PKG_CONFIG_PATH" == "__EMPTY__" ) then
  setenv PKG_CONFIG_PATH "$python_prefix/lib/pkgconfig:$llvm_prefix/lib/pkgconfig"
else
  setenv PKG_CONFIG_PATH "$python_prefix/lib/pkgconfig:$llvm_prefix/lib/pkgconfig:$PORTABLE_ORIG_PKG_CONFIG_PATH"
endif
setenv CC "$llvm_prefix/bin/clang"
setenv CXX "$llvm_prefix/bin/clang++"
setenv AR "$llvm_prefix/bin/llvm-ar"
setenv NM "$llvm_prefix/bin/llvm-nm"
setenv RANLIB "$llvm_prefix/bin/llvm-ranlib"
setenv LD "$llvm_prefix/bin/ld.lld"
setenv PORTABLE_LLVM_PREFIX "$llvm_prefix"
setenv PORTABLE_PYTHON_PREFIX "$python_prefix"
setenv PORTABLE_ENV_MODE "llvm+python"

echo "LLVM + Python environments configured in current shell."
echo "PORTABLE_LLVM_PREFIX=$PORTABLE_LLVM_PREFIX"
echo "PORTABLE_PYTHON_PREFIX=$PORTABLE_PYTHON_PREFIX"
