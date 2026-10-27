#!/bin/bash
# 在 WSL(Ubuntu-24.04) 内交叉编译 core/doh_proxy → HarmonyOS (OHOS) 原生库
#
# 背景：OHOS NDK（DevEco 自带）只提供 Windows 版 clang，且其包装脚本未给含空格路径加引号；
# 因此这里用 Ubuntu 自带 clang 18 + OHOS NDK 的 sysroot / clang resource-dir + lld 交叉编译。
# 说明详见 docs/ohos-native-strategy.md §0.0。
#
# 用法（在 Windows PowerShell 中）：
#   wsl.exe -d Ubuntu-24.04 -- bash /mnt/c/Users/iceblock/fluxdo/tools/build-doh-ohos.sh
#
# 产物：repo/ohos/entry/libs/{x86_64,arm64-v8a}/libdoh_proxy.so
set -euo pipefail

REPO_WIN="/mnt/c/Users/iceblock/fluxdo"
NDK="${OHOS_NDK:-/home/iceblock/ohos-ndk}"
RES="$NDK/llvm/lib/clang/15.0.4"
BIN="$HOME/ohos-bin"
LIBDIR="$BIN/lib"
BUILD="$REPO_WIN/.cache/doh-build"
STUB_O="$LIBDIR/unwind-stub-x86_64.o"
ARM_UNWIND="$NDK/llvm/lib/aarch64-linux-ohos/libunwind.a"

for t in clang cmake ar; do command -v "$t" >/dev/null || { echo "缺少 $t（apt: clang cmake binutils）"; exit 1; }; done
[ -x "$HOME/.cargo/bin/cargo" ] || { echo "缺少 rust（rustup 安装）"; exit 1; }
"$HOME/.cargo/bin/rustup" target list --installed | grep -q x86_64-unknown-linux-ohos || \
  "$HOME/.cargo/bin/rustup" target add x86_64-unknown-linux-ohos aarch64-unknown-linux-ohos

mkdir -p "$LIBDIR"

mk_wrapper() {
  local out="$1" arch="$2"
  cat > "$out" <<EOF
#!/bin/bash
exec /usr/bin/clang -target ${arch}-linux-ohos \\
  -resource-dir=$RES \\
  --sysroot=$NDK/sysroot \\
  -L$LIBDIR \\
  -L$NDK/sysroot/usr/lib/${arch}-linux-ohos \\
  -unwindlib=none -fuse-ld=lld "\$@"
EOF
  chmod +x "$out"
}
mk_wrapper "$BIN/clang-x86_64" x86_64
mk_wrapper "$BIN/clang-aarch64" aarch64

# x86_64 的 unwind 桩（NDK 只给 aarch64 提供 libunwind.a）
[ -f "$STUB_O" ] || bash "$REPO_WIN/tools/build-ohos-unwind-stub.sh"

cat > "$HOME/.cargo/config.toml" <<EOF
[target.x86_64-unknown-linux-ohos]
linker = "$BIN/clang-x86_64"
ar = "/usr/bin/ar"

[target.aarch64-unknown-linux-ohos]
linker = "$BIN/clang-aarch64"
ar = "/usr/bin/ar"
EOF

rm -rf "$BUILD"
cp -r "$REPO_WIN/repo/core/doh_proxy" "$BUILD"
cd "$BUILD"

build_arch() {
  local triple="$1" cc="$2" outdir="$3"
  local flags="-C panic=abort"
  case "$triple" in
    x86_64*)  flags="$flags -C link-arg=$STUB_O" ;;
    aarch64*) flags="$flags -C link-arg=$ARM_UNWIND" ;;
  esac
  echo "=== build $triple ==="
  env \
    "RUSTFLAGS=$flags" \
    "CC_${triple//-/_}=$cc" \
    "AR_${triple//-/_}=/usr/bin/ar" \
    "CARGO_TARGET_$(echo "$triple" | tr 'a-z-' 'A-Z_')_LINKER=$cc" \
    "$HOME/.cargo/bin/cargo" build --release --target "$triple" --lib 2>&1 | tail -5
  mkdir -p "$outdir"
  cp -f "target/$triple/release/libdoh_proxy.so" "$outdir/"
  file "$outdir/libdoh_proxy.so" | cut -c1-110
  echo "-- 未解析的 _Unwind 符号数：$(nm -D -u "$outdir/libdoh_proxy.so" 2>/dev/null | grep -c '_Unwind' || true)"
}

build_arch x86_64-unknown-linux-ohos "$BIN/clang-x86_64" "$REPO_WIN/repo/ohos/entry/libs/x86_64"
build_arch aarch64-unknown-linux-ohos "$BIN/clang-aarch64" "$REPO_WIN/repo/ohos/entry/libs/arm64-v8a"

echo "=== 产物 ==="
ls -l "$REPO_WIN/repo/ohos/entry/libs/"*/*.so
