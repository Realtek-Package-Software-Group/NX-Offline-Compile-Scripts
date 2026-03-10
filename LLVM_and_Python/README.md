# NX-Offline-Compile-Scripts

在有網路的 WSL 環境中，使用 Docker (Rocky Linux 8.8) 建立可攜帶工具鏈，並且把 LLVM 與 Python 3.14.3 分開打包、分開安裝。

重點：
- LLVM 與 Python 3.14.3 產生兩個獨立 tar 包，離線時可安裝到不同路徑
- Python 3.14.3 由原始碼編譯，啟用
  - `--with-tail-call-interp`
  - `--enable-optimizations`
  - `--with-lto=thin`
- 離線安裝與環境設定腳本全部為 `csh`
- 環境模式三種：
  1. 只設定 LLVM 環境
  2. 只設定 Python 3.14 環境
  3. 同時設定 LLVM + Python 3.14 環境

## 目錄
- `docker/Dockerfile`
- `docker/build_inside_container.sh`
- `docker/verify_bundle_inside_container.sh`
- `scripts/build_portable_python314_llvm.sh`
- `scripts/verify_offline_bundle.sh`
- `scripts/offline/install_portable_envs.csh`
- `scripts/offline/start_llvm_only.csh`
- `scripts/offline/start_python_only.csh`
- `scripts/offline/start_llvm_python.csh`

## 1) 在線 WSL 建置（Docker）
```bash
./scripts/build_portable_python314_llvm.sh
```

可覆蓋參數：
```bash
PYTHON_VERSION=3.14.3 LLVM_ENV_NAME=llvm-toolchain PY_ENV_NAME=python314-opt ./scripts/build_portable_python314_llvm.sh
```

若 Docker Hub 網路不穩，build 腳本會先重試拉取 base image。可額外覆蓋：
```bash
BASE_IMAGE=rockylinux:8.8 DOCKER_RETRY_COUNT=5 DOCKER_RETRY_DELAY_SEC=10 ./scripts/build_portable_python314_llvm.sh
```

若公司內部有 registry mirror，也可改用自訂 base image：
```bash
BASE_IMAGE=my-registry.example.com/library/rockylinux:8.8 ./scripts/build_portable_python314_llvm.sh
```

完成後產物在 `artifacts/`：
- `${LLVM_ENV_NAME}-rhel8.8.tar.gz`
- `${LLVM_ENV_NAME}-rhel8.8.tar.gz.sha256`
- `${PY_ENV_NAME}-python-${PYTHON_VERSION}-rhel8.8.tar.gz`
- `${PY_ENV_NAME}-python-${PYTHON_VERSION}-rhel8.8.tar.gz.sha256`
- `llvm-tool-versions.txt`
- `python-build-metadata.txt`
- `install_portable_envs.csh`
- `start_llvm_only.csh`
- `start_python_only.csh`
- `start_llvm_python.csh`

## 2) 離線 RedHat 8.8 安裝（csh）
把 `artifacts/` 帶到離線機器。

```csh
cd artifacts
./install_portable_envs.csh /opt
```
預設安裝路徑：
- LLVM: `/opt/llvm21`
- Python: `/opt/python314`

安裝腳本會把 `start_llvm_only.csh`、`start_python_only.csh`、`start_llvm_python.csh`
複製到 `/opt`，並建立：
- `/opt/portable-llvm -> /opt/llvm21`
- `/opt/portable-python314 -> /opt/python314`

若要改目錄名稱，可先設定：
```csh
setenv LLVM_DIR_NAME llvm21
setenv PYTHON_DIR_NAME python314
./install_portable_envs.csh /opt
```

## 3) 離線環境設定（csh）
先 `cd` 到放置腳本的目錄（同目錄需有 `portable-llvm`、`portable-python314`）：
```csh
cd /project/PACKAGE/package/tools/toolchains
```

1. 只設定 LLVM：
```csh
source ./start_llvm_only.csh /opt/portable-llvm
clang --version
```
若要指定 `ccache` 目錄：
```csh
source ./start_llvm_only.csh /opt/portable-llvm /project/cache/ccache
echo $CCACHE_DIR
ccache -s
```
若不帶參數，預設使用目前目錄下 `./portable-llvm`：
```csh
source ./start_llvm_only.csh
```

2. 只設定 Python 3.14：
```csh
source ./start_python_only.csh /opt/portable-python314
python3.14 -V
python3.14 -c "import sys; print(sys.version)"
```
此模式只適合執行 Python，不會保留 `CC`、`CXX`、`LDFLAGS` 等編譯環境變數。

若不帶參數，預設使用目前目錄下 `./portable-python314`：
```csh
source ./start_python_only.csh
```

3. 同時設定 LLVM + Python 3.14：
```csh
source ./start_llvm_python.csh /opt/portable-llvm /opt/portable-python314
python3.14 -c "import sys; print(sys.version)"
clang --version
```
若要指定 `ccache` 目錄：
```csh
source ./start_llvm_python.csh /opt/portable-llvm /opt/portable-python314 /project/cache/ccache
echo $CCACHE_DIR
ccache -s
```
若不帶參數，預設使用目前目錄下 `./portable-llvm` 與 `./portable-python314`：
```csh
source ./start_llvm_python.csh
```

`ccache` 目錄優先順序如下：
1. `start_llvm_only.csh` / `start_llvm_python.csh` 的最後一個參數
2. `PORTABLE_CCACHE_DIR`
3. `CCACHE_DIR`
4. 預設值 `$HOME/.cache/nx-offline-ccache`

只要是會編譯 extension 的流程，例如 `numba.pycc`、`setuptools build_ext`、`Nuitka`，都應該使用 `start_llvm_python.csh`，不要用 `start_python_only.csh`。

## 4) venv + Nuitka / extension build
推薦順序是先設定 `LLVM + Python`，再啟用 venv，這樣 `python` 會指向 venv，同時仍保留 `clang` / `ccache` 編譯環境：

```csh
source /opt/start_llvm_python.csh /opt/portable-llvm /opt/portable-python314 /project/cache/ccache
python3.14 -m venv /project/myenv
source /project/myenv/bin/activate.csh

which python
echo $CC
echo $CCACHE_DIR
ccache -s

python -m nuitka --module your_module.py
```

如果 venv 已經存在，之後每次開新 shell 的順序仍然相同：
```csh
source /opt/start_llvm_python.csh /opt/portable-llvm /opt/portable-python314 /project/cache/ccache
source /project/myenv/bin/activate.csh
```

若只是執行既有 Python 程式、不做任何編譯，可以改用：
```csh
source /opt/start_python_only.csh /opt/portable-python314
source /project/myenv/bin/activate.csh
```

## 5) 單獨離線模擬驗證（本機 Docker）
```bash
./scripts/verify_offline_bundle.sh \
  artifacts/llvm-toolchain-rhel8.8.tar.gz \
  artifacts/python314-opt-python-3.14.3-rhel8.8.tar.gz
```

此驗證使用 `--network none`，檢查：
- Python configure flags 是否包含 3 個優化選項
- LLVM 主要工具是否存在可執行
- 三個 `csh` 環境設定腳本是否可成功設定環境
- `start_llvm_only.csh` / `start_llvm_python.csh` 是否可正確套用自訂 `ccache` 目錄
- 以可攜 Python 建立的 venv 在未先 source start 腳本時仍可啟動
