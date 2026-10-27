#!/bin/bash
# 生成 x86_64-linux-ohos 的 unwind 符号桩并重新编译 librhttp / libdoh_proxy
# （aarch64 用 NDK 自带真实 libunwind.a，不需要桩）
set -euo pipefail
REPO_WIN="/mnt/c/Users/iceblock/fluxdo"
BIN="$HOME/ohos-bin"
STUB_C="$REPO_WIN/tools/ohos-unwind-stub.c"
STUB_O="$BIN/lib/unwind-stub-x86_64.o"
mkdir -p "$BIN/lib"

echo "=== 编译桩 ==="
"$BIN/clang-x86_64" -O2 -fPIC -c "$STUB_C" -o "$STUB_O"
file "$STUB_O"

echo "=== 检查桩导出的符号 ==="
nm --defined-only "$STUB_O" | grep _Unwind | head -20

echo ">>> 现在请用带 -C link-arg=$STUB_O 的 RUSTFLAGS 重新构建 rhttp/doh"
