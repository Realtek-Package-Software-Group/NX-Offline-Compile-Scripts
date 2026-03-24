#!/bin/csh -f

if ( $#argv > 1 ) then
  echo "Usage: source start_python_only.csh [python_prefix]"
  exit 1
endif

if ( $#argv == 1 ) then
  set python_prefix = "$1"
else
  set python_prefix = "$cwd/portable-python314"
  echo "No python_prefix specified, using default: $python_prefix"
endif

if ( ! -d "$python_prefix" ) then
  echo "Python prefix not found: $python_prefix"
  if ( $#argv == 0 ) then
    echo "Hint: put portable Python under ./portable-python314 or pass an explicit path."
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

setenv PATH "$python_prefix/bin:$PORTABLE_ORIG_PATH"
if ( "$PORTABLE_ORIG_LD_LIBRARY_PATH" == "__EMPTY__" ) then
  setenv LD_LIBRARY_PATH "$python_prefix/lib"
else
  setenv LD_LIBRARY_PATH "$python_prefix/lib:$PORTABLE_ORIG_LD_LIBRARY_PATH"
endif

if ( -x "$python_prefix/bin/conda-unpack" ) then
  if ( -e "$python_prefix/.conda_unpacked" ) then
  else if ( -w "$python_prefix" ) then
    "$python_prefix/bin/conda-unpack"
    if ( $status != 0 ) then
      exit $status
    endif
    touch "$python_prefix/.conda_unpacked"
  else
    echo "Warning: skipping python conda-unpack because prefix is not writable: $python_prefix"
  endif
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
  setenv LIBRARY_PATH "$python_prefix/lib"
else
  setenv LIBRARY_PATH "$python_prefix/lib:$PORTABLE_ORIG_LIBRARY_PATH"
endif
if ( "$PORTABLE_ORIG_CPATH" == "__EMPTY__" ) then
  setenv CPATH "$python_prefix/include"
else
  setenv CPATH "$python_prefix/include:$PORTABLE_ORIG_CPATH"
endif
if ( "$PORTABLE_ORIG_PKG_CONFIG_PATH" == "__EMPTY__" ) then
  setenv PKG_CONFIG_PATH "$python_prefix/lib/pkgconfig"
else
  setenv PKG_CONFIG_PATH "$python_prefix/lib/pkgconfig:$PORTABLE_ORIG_PKG_CONFIG_PATH"
endif
setenv PORTABLE_PYTHON_PREFIX "$python_prefix"
setenv PORTABLE_ENV_MODE "python"

if ( $?PORTABLE_LLVM_PREFIX ) unsetenv PORTABLE_LLVM_PREFIX
if ( $?CC ) unsetenv CC
if ( $?CXX ) unsetenv CXX
if ( $?CPP ) unsetenv CPP
if ( $?AR ) unsetenv AR
if ( $?NM ) unsetenv NM
if ( $?RANLIB ) unsetenv RANLIB
if ( $?LD ) unsetenv LD
if ( $?ARFLAGS ) unsetenv ARFLAGS
if ( $?CPPFLAGS ) unsetenv CPPFLAGS
if ( $?CFLAGS ) unsetenv CFLAGS
if ( $?CXXFLAGS ) unsetenv CXXFLAGS
if ( $?LDFLAGS ) unsetenv LDFLAGS
if ( $?LDSHARED ) unsetenv LDSHARED
if ( $?LDCXXSHARED ) unsetenv LDCXXSHARED
if ( $?PORTABLE_CCACHE_BIN ) unsetenv PORTABLE_CCACHE_BIN
if ( $?PORTABLE_CCACHE_DIR ) unsetenv PORTABLE_CCACHE_DIR

echo "Python environment configured in current shell."
echo "PORTABLE_PYTHON_PREFIX=$PORTABLE_PYTHON_PREFIX"
echo "Compilation workflows such as numba.pycc require start_llvm_python.csh."
rehash
