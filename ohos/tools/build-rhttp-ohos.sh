#!/bin/bash
# 交叉编译 rhttp 的 Rust 核心（flutter_rust_bridge 2.12.0）到 HarmonyOS
# 依赖 WSL 里已配置好的 OHOS 交叉环境（见 tools/build-doh-ohos.sh）
set -euo pipefail

REPO_WIN="/mnt/c/Users/iceblock/fluxdo"
PKG="$REPO_WIN/.pub-cache/git/rhttp_plus-02eb4114b57c108e76a9ed526b6118bc048b5604/rhttp"
VENDORED="$REPO_WIN/repo/packages/rhttp/rust"
BIN="$HOME/ohos-bin"
NDK="${OHOS_NDK:-/home/iceblock/ohos-ndk}"
BUILD="$REPO_WIN/.cache/rhttp-build"
STUB_O="$BIN/lib/unwind-stub-x86_64.o"
ARM_UNWIND="$NDK/llvm/lib/aarch64-linux-ohos/libunwind.a"

for t in clang cmake ar; do command -v "$t" >/dev/null || { echo "缺少 $t"; exit 1; }; done
[ -x "$HOME/.cargo/bin/cargo" ] || { echo "缺少 rust"; exit 1; }
[ -f "$STUB_O" ] || { echo "缺少 unwind 桩：先跑 tools/build-ohos-unwind-stub.sh"; exit 1; }

# 优先用 vendored 源码（与 app 依赖一致），否则回退 pub-cache
SRC="$VENDORED"
[ -d "$SRC" ] || SRC="$PKG/rust"

rm -rf "$BUILD"
mkdir -p "$BUILD"
cp -r "$SRC/." "$BUILD/"
cd "$BUILD"

cat > "$HOME/.cargo/config.toml" <<EOF
[target.x86_64-unknown-linux-ohos]
linker = "$BIN/clang-x86_64"
ar = "/usr/bin/ar"

[target.aarch64-unknown-linux-ohos]
linker = "$BIN/clang-aarch64"
ar = "/usr/bin/ar"
EOF

build_arch() {
  local triple="$1" cc="$2" outdir="$3"
  local flags="--cfg reqwest_unstable -C panic=abort"
  case "$triple" in
    x86_64*)  flags="$flags -C link-arg=$STUB_O" ;;
    aarch64*) flags="$flags -C link-arg=$ARM_UNWIND" ;;
  esac
  echo "=== build $triple (RUSTFLAGS=$flags) ==="
  env \
    "RUSTFLAGS=$flags" \
    "CC_${triple//-/_}=$cc" \
    "AR_${triple//-/_}=/usr/bin/ar" \
    "CARGO_TARGET_$(echo "$triple" | tr 'a-z-' 'A-Z_')_LINKER=$cc" \
    "$HOME/.cargo/bin/cargo" build --release --target "$triple" --lib 2>&1 | tail -6
  mkdir -p "$outdir"
  if [ -f "target/$triple/release/librhttp.so" ]; then
    cp -f "target/$triple/release/librhttp.so" "$outdir/"
    file "$outdir/librhttp.so" | cut -c1-110
    echo "-- 未解析的 _Unwind 符号数：$(nm -D -u "$outdir/librhttp.so" 2>/dev/null | grep -c '_Unwind' || true)"
  else
    echo "!! 未找到 target/$triple/release/librhttp.so"
  fi
}

build_arch x86_64-unknown-linux-ohos "$BIN/clang-x86_64" "$REPO_WIN/repo/ohos/entry/libs/x86_64"
build_arch aarch64-unknown-linux-ohos "$BIN/clang-aarch64" "$REPO_WIN/repo/ohos/entry/libs/arm64-v8a"

echo "=== 产物 ==="
ls -l "$REPO_WIN/repo/ohos/entry/libs/"*/librhttp.so 2>/dev/null || echo "无 librhttp.so"
