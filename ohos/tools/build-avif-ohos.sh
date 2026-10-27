#!/bin/bash
# 在 WSL 内交叉编译 libavif + dav1d + AVIF 解码包装 → HarmonyOS 原生库
#
# 产物：repo/ohos/entry/libs/<abi>/libohos_avif.so
# 依赖：WSL 内 clang/lld/cmake/meson/ninja/nasm（apt 安装）+ OHOS NDK sysroot
set -euo pipefail

REPO_WIN="/mnt/c/Users/iceblock/fluxdo"
# NDK：优先 $OHOS_NDK；否则用 WSL 本地副本；都没有时直接用 Windows 侧 DevEco SDK
# 的 native 目录（布局相同：sysroot/ + llvm/lib/clang/15.0.4）。
if [ -n "${OHOS_NDK:-}" ]; then
  NDK="$OHOS_NDK"
elif [ -d /home/iceblock/ohos-ndk/sysroot ]; then
  NDK=/home/iceblock/ohos-ndk
else
  NDK=/mnt/c/Users/iceblock/DevEcoStudio/sdk/default/openharmony/native
fi
[ -d "$NDK/sysroot" ] || { echo "!! 找不到 OHOS NDK sysroot：$NDK"; exit 1; }
BIN="$HOME/ohos-bin"
STUB_O="$BIN/lib/unwind-stub-x86_64.o"
ARM_UNWIND="$NDK/llvm/lib/aarch64-linux-ohos/libunwind.a"
WORK="$REPO_WIN/.cache/avif-build"

# 智能包装器：编译调用不注入链接参数（否则 meson 的
# -Werror=unused-command-line-argument 会报错），仅在链接时注入。
mk_wrapper() {
  local out="$1" arch="$2"
  cat > "$out" <<EOF
#!/bin/bash
# OHOS $arch clang 包装器（编译/链接自适应）
is_link=1
for a in "\$@"; do
  case "\$a" in
    -c|-E|-S|-M|-MM) is_link=0 ;;
  esac
done
COMMON="-target ${arch}-linux-ohos --sysroot=$NDK/sysroot -resource-dir=$NDK/llvm/lib/clang/15.0.4"
if [ "\$is_link" = "1" ]; then
  exec /usr/bin/clang \$COMMON -L$BIN/lib -L$NDK/sysroot/usr/lib/${arch}-linux-ohos \\
    -unwindlib=none -fuse-ld=lld "\$@"
fi
exec /usr/bin/clang \$COMMON "\$@"
EOF
  chmod +x "$out"
}
mk_wrapper "$BIN/clang-x86_64" x86_64
mk_wrapper "$BIN/clang-aarch64" aarch64

build_abi() {
  local arch="$1"                 # x86_64 | aarch64
  local cpu_family="$2"           # x86_64 | aarch64
  local outdir="$3"
  local cc="$BIN/clang-$arch"
  local prefix="$WORK/prefix-$arch"
  local bdir="$WORK/build-$arch"

  echo "================ build AVIF for $arch ================"
  rm -rf "$bdir" "$prefix"
  mkdir -p "$bdir" "$prefix"

  # ---------- 1) dav1d ----------
  if [ ! -f "$prefix/lib/libdav1d.a" ]; then
    cat > "$bdir/ohos-cross-$arch.ini" <<EOF
[binaries]
c = '$cc'
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = '$cpu_family'
cpu = '$cpu_family'
endian = 'little'
EOF
    echo "--- meson setup dav1d ($arch) ---"
    meson setup "$bdir/dav1d" "$REPO_WIN/.cache/dav1d" \
      --cross-file "$bdir/ohos-cross-$arch.ini" \
      --buildtype release --default-library static \
      -Denable_tools=false -Denable_tests=false -Denable_examples=false \
      -Denable_asm=false -Denable_docs=false \
      --prefix "$prefix" > "$bdir/dav1d-setup.log" 2>&1 || {
        echo "!! meson setup failed"; tail -25 "$bdir/dav1d-setup.log"; return 1; }
    echo "--- ninja install dav1d ($arch) ---"
    ninja -C "$bdir/dav1d" install > "$bdir/dav1d-build.log" 2>&1 || {
      echo "!! dav1d build failed"; tail -25 "$bdir/dav1d-build.log"; return 1; }
  fi
  ls -l "$prefix/lib/libdav1d.a"

  # ---------- 2) libavif ----------
  if [ ! -f "$prefix/lib/libavif.a" ]; then
    cat > "$bdir/ohos-toolchain-$arch.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $cpu_family)
set(CMAKE_C_COMPILER "$cc")
set(CMAKE_CXX_COMPILER "$cc")
set(CMAKE_AR "/usr/bin/ar")
set(CMAKE_RANLIB "/usr/bin/ranlib")
set(CMAKE_FIND_ROOT_PATH "$prefix" "$NDK/sysroot")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF
    echo "--- cmake configure libavif ($arch) ---"
    cmake -S "$REPO_WIN/.cache/libavif" -B "$bdir/libavif" \
      -DCMAKE_TOOLCHAIN_FILE="$bdir/ohos-toolchain-$arch.cmake" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DBUILD_SHARED_LIBS=OFF \
      -DAVIF_CODEC_DAV1D=SYSTEM \
      -DDAV1D_INCLUDE_DIR="$prefix/include" \
      -DDAV1D_LIBRARY="$prefix/lib/libdav1d.a" \
      -DAVIF_LIBYUV=OFF \
      -DAVIF_BUILD_APPS=OFF -DAVIF_BUILD_TESTS=OFF -DAVIF_BUILD_EXAMPLES=OFF \
      -DAVIF_ENABLE_WERROR=OFF -DAVIF_GTEST=OFF -DAVIF_ENABLE_SHARPYUV=OFF \
      > "$bdir/libavif-cfg.log" 2>&1 || {
        echo "!! libavif configure failed"; tail -30 "$bdir/libavif-cfg.log"; return 1; }
    echo "--- cmake build libavif ($arch) ---"
    cmake --build "$bdir/libavif" --target avif -j"$(nproc)" > "$bdir/libavif-build.log" 2>&1 || {
      echo "!! libavif build failed"; tail -30 "$bdir/libavif-build.log"; return 1; }
  fi
  # libavif 静态库位置（cmake target avif 产物）
  local avif_lib
  avif_lib=$(find "$bdir/libavif" -name 'libavif*.a' | head -1)
  [ -n "$avif_lib" ] || { echo "!! 未找到 libavif.a"; return 1; }

  # ---------- 3) 包装 .so ----------
  echo "--- 编译 libohos_avif.so ($arch) ---"
  local extra=""
  case "$arch" in
    x86_64)  extra="$STUB_O" ;;
    aarch64) extra="$ARM_UNWIND" ;;
  esac
  "$cc" -shared -fPIC -O2 \
    -I "$REPO_WIN/.cache/libavif/include" -I "$prefix/include" \
    "$REPO_WIN/tools/ohos-avif-decode.c" \
    "$avif_lib" "$prefix/lib/libdav1d.a" "$extra" \
    -lm -o "$outdir/libohos_avif.so" 2> "$bdir/wrapper-build.log" || {
      echo "!! wrapper 编译失败"; tail -25 "$bdir/wrapper-build.log"; return 1; }

  mkdir -p "$outdir"
  file "$outdir/libohos_avif.so" | cut -c1-120
  echo "-- 导出符号："
  nm -D --defined-only "$outdir/libohos_avif.so" | grep ohos_avif || true
  echo "-- 未解析 _Unwind：$(nm -D -u "$outdir/libohos_avif.so" 2>/dev/null | grep -c '_Unwind' || true)"
}

build_abi x86_64 x86_64 "$REPO_WIN/repo/ohos/entry/libs/x86_64"
build_abi aarch64 aarch64 "$REPO_WIN/repo/ohos/entry/libs/arm64-v8a"

echo "=== 产物 ==="
ls -l "$REPO_WIN/repo/ohos/entry/libs/"*/libohos_avif.so 2>/dev/null || echo "无产物"
