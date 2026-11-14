#!/bin/bash
# 生成 x86_64-linux-ohos 的 unwind 符号桩（x86_64 NDK 不带 libunwind.a；aarch64 用真实 libunwind.a，不需要桩）
# 使用者：build-avif-ohos.sh、build-quickjs-ohos.sh、build-native-animated-image-ohos.sh（x86_64 链接）
# 注意：libfluxdo_net.so（build-netcore-ohos.sh）不使用本桩——它依赖 panic=unwind，链接真实的 NDK libunwind.a
# 历史：rhttp / DOH 代理已于 v0.2.30 同步中删除，不再由本脚本服务
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

echo ">>> 桩已就绪：现在可运行 build-avif-ohos.sh / build-quickjs-ohos.sh / build-native-animated-image-ohos.sh（x86_64 会链接 $STUB_O）"
