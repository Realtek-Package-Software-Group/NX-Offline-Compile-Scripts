#!/bin/csh -f

if ( $#argv > 2 ) then
  echo "Usage: source start_llvm_only.csh [llvm_prefix] [ccache_dir]"
  exit 1
endif

set requested_ccache_dir = ""

if ( $#argv == 1 ) then
  set llvm_prefix = "$1"
else if ( $#argv == 2 ) then
  set llvm_prefix = "$1"
  set requested_ccache_dir = "$2"
else
  set llvm_prefix = "$cwd/portable-llvm"
  echo "No llvm_prefix specified, using default: $llvm_prefix"
endif

if ( ! -d "$llvm_prefix" ) then
  echo "LLVM prefix not found: $llvm_prefix"
  if ( $#argv == 0 ) then
    echo "Hint: put portable LLVM under ./portable-llvm or pass an explicit path."
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

if ( -x "$llvm_prefix/bin/conda-unpack" && ! -e "$llvm_prefix/.conda_unpacked" ) then
  if ( "$PORTABLE_ORIG_LD_LIBRARY_PATH" == "__EMPTY__" ) then
    env PATH="$llvm_prefix/bin:$PORTABLE_ORIG_PATH" LD_LIBRARY_PATH="$llvm_prefix/lib" "$llvm_prefix/bin/conda-unpack"
  else
    env PATH="$llvm_prefix/bin:$PORTABLE_ORIG_PATH" LD_LIBRARY_PATH="$llvm_prefix/lib:$PORTABLE_ORIG_LD_LIBRARY_PATH" "$llvm_prefix/bin/conda-unpack"
  endif
  if ( $status != 0 ) then
    exit $status
  endif
  touch "$llvm_prefix/.conda_unpacked"
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

set ccache_bin = ""
set ccache_wrap_bin = ""
if ( -x "$llvm_prefix/bin/ccache" ) then
  set ccache_bin = "$llvm_prefix/bin/ccache"
  set ccache_wrap_bin = "$llvm_prefix/.llvm-ccache-bin"
  mkdir -p "$ccache_wrap_bin"
  set ccache_dir = ""
  if ( "$requested_ccache_dir" != "" ) then
    set ccache_dir = "$requested_ccache_dir"
  else if ( $?PORTABLE_CCACHE_DIR ) then
    set ccache_dir = "$PORTABLE_CCACHE_DIR"
  else if ( $?CCACHE_DIR ) then
    set ccache_dir = "$CCACHE_DIR"
  endif
  if ( "$ccache_dir" == "" ) then
    if ( $?HOME ) then
      set ccache_dir = "$HOME/.cache/nx-offline-ccache"
    else
      set ccache_dir = "$cwd/.ccache"
    endif
  endif
  if ( "$ccache_dir" == "" ) then
    set ccache_dir = "$cwd/.ccache"
  endif
  mkdir -p "$ccache_dir"
  if ( $status == 0 ) then
    setenv CCACHE_DIR "$ccache_dir"
    setenv PORTABLE_CCACHE_DIR "$ccache_dir"
  else
    echo "Warning: unable to create ccache directory: $ccache_dir"
  endif
  if ( ! $?CCACHE_COMPILERCHECK ) then
    setenv CCACHE_COMPILERCHECK content
  endif
  setenv PORTABLE_CCACHE_BIN "$ccache_bin"
  cat > "$ccache_wrap_bin/clang" << EOF
#!/bin/sh
exec "$ccache_bin" "$llvm_prefix/bin/clang" "\$@"
EOF
  cat > "$ccache_wrap_bin/clang++" << EOF
#!/bin/sh
exec "$ccache_bin" "$llvm_prefix/bin/clang++" "\$@"
EOF
  chmod +x "$ccache_wrap_bin/clang" "$ccache_wrap_bin/clang++"
endif

if ( "$ccache_wrap_bin" != "" ) then
  setenv PATH "${ccache_wrap_bin}:${llvm_bin}:$PORTABLE_ORIG_PATH"
else
  setenv PATH "${llvm_bin}:$PORTABLE_ORIG_PATH"
endif
if ( "$PORTABLE_ORIG_LD_LIBRARY_PATH" == "__EMPTY__" ) then
  setenv LD_LIBRARY_PATH "$llvm_prefix/lib"
else
  setenv LD_LIBRARY_PATH "$llvm_prefix/lib:$PORTABLE_ORIG_LD_LIBRARY_PATH"
endif

if ( "$PORTABLE_ORIG_LIBRARY_PATH" == "__EMPTY__" ) then
  setenv LIBRARY_PATH "$llvm_prefix/lib"
else
  setenv LIBRARY_PATH "$llvm_prefix/lib:$PORTABLE_ORIG_LIBRARY_PATH"
endif
if ( "$PORTABLE_ORIG_CPATH" == "__EMPTY__" ) then
  setenv CPATH "$llvm_prefix/include"
else
  setenv CPATH "$llvm_prefix/include:$PORTABLE_ORIG_CPATH"
endif
if ( "$PORTABLE_ORIG_PKG_CONFIG_PATH" == "__EMPTY__" ) then
  setenv PKG_CONFIG_PATH "$llvm_prefix/lib/pkgconfig"
else
  setenv PKG_CONFIG_PATH "$llvm_prefix/lib/pkgconfig:$PORTABLE_ORIG_PKG_CONFIG_PATH"
endif
if ( "$ccache_bin" != "" ) then
  setenv CC "$ccache_wrap_bin/clang"
  setenv CXX "$ccache_wrap_bin/clang++"
else
  setenv CC "$llvm_prefix/bin/clang"
  setenv CXX "$llvm_prefix/bin/clang++"
endif
setenv AR "$llvm_prefix/bin/llvm-ar"
setenv NM "$llvm_prefix/bin/llvm-nm"
setenv RANLIB "$llvm_prefix/bin/llvm-ranlib"
setenv LD "$llvm_prefix/bin/ld.lld"
setenv PORTABLE_LLVM_PREFIX "$llvm_prefix"
setenv PORTABLE_ENV_MODE "llvm"

if ( $?PORTABLE_PYTHON_PREFIX ) unsetenv PORTABLE_PYTHON_PREFIX
if ( $?PYTHONHOME ) unsetenv PYTHONHOME
if ( $?PYTHONPATH ) unsetenv PYTHONPATH
if ( $?VIRTUAL_ENV ) unsetenv VIRTUAL_ENV

echo "LLVM environment configured in current shell."
echo "PORTABLE_LLVM_PREFIX=$PORTABLE_LLVM_PREFIX"
if ( $?PORTABLE_CCACHE_DIR ) echo "PORTABLE_CCACHE_DIR=$PORTABLE_CCACHE_DIR"
rehash
