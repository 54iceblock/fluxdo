#!/bin/bash
# 交叉编译 QuickJS（quickjs-ng）+ 最小桥接 → HarmonyOS 原生库 libohos_quickjs.so
# 依赖 WSL 内已有的 OHOS clang 包装器（~/ohos-bin/clang-<arch>，见 tools/ohos/build-doh-ohos.sh）
set -euo pipefail

REPO_WIN="${FLUXDO_WS:-/mnt/c/Users/you/fluxdo}"
BIN="$HOME/ohos-bin"
NDK="${OHOS_NDK:-/home/you/ohos-ndk}"
SRC="$REPO_WIN/.cache/quickjs-ng"
BUILD="$REPO_WIN/.cache/qjs-build"
STUB_O="$BIN/lib/unwind-stub-x86_64.o"
ARM_UNWIND="$NDK/llvm/lib/aarch64-linux-ohos/libunwind.a"

[ -f "$SRC/quickjs.c" ] || { echo "缺少 QuickJS 源码：$SRC"; exit 1; }
mkdir -p "$BUILD"

build_arch() {
  local arch="$1" outdir="$2"
  local cc="$BIN/clang-$arch"
  local extra=""
  case "$arch" in
    x86_64)  extra="$STUB_O" ;;
    aarch64) extra="$ARM_UNWIND" ;;
  esac
  local objdir="$BUILD/obj-$arch"
  rm -rf "$objdir"; mkdir -p "$objdir"

  echo "================ build QuickJS for $arch ================"
  local sources=(
    "$SRC/quickjs.c"
    "$SRC/dtoa.c"
    "$SRC/libregexp.c"
    "$SRC/libunicode.c"
  )
  local objs=()
  for src in "${sources[@]}"; do
    local name
    name=$(basename "$src" .c)
    "$cc" -c -O2 -fPIC -D_GNU_SOURCE -DCONFIG_VERSION=\"ohos\" \
      -I "$SRC" "$src" -o "$objdir/$name.o"
    objs+=("$objdir/$name.o")
  done
  "$cc" -c -O2 -fPIC -D_GNU_SOURCE -I "$SRC" \
    "$REPO_WIN/tools/ohos/ohos-quickjs-bridge.c" -o "$objdir/bridge.o"
  objs+=("$objdir/bridge.o")

  mkdir -p "$outdir"
  "$cc" -shared -o "$outdir/libohos_quickjs.so" "${objs[@]}" "$extra" -lm
  file "$outdir/libohos_quickjs.so" | cut -c1-120
  echo "-- 导出 ohos_js_*："
  nm -D --defined-only "$outdir/libohos_quickjs.so" | grep ohos_js || true
  echo "-- 未解析 _Unwind：$(nm -D -u "$outdir/libohos_quickjs.so" 2>/dev/null | grep -c '_Unwind' || true)"
}

build_arch x86_64 "$REPO_WIN/repo/ohos/entry/libs/x86_64"
build_arch aarch64 "$REPO_WIN/repo/ohos/entry/libs/arm64-v8a"

echo "=== 产物 ==="
ls -l "$REPO_WIN/repo/ohos/entry/libs/"*/libohos_quickjs.so 2>/dev/null || echo "无产物"
