#!/bin/bash
# 在 WSL 内交叉编译 core/net_core（fluxdo_net：rama + BoringSSL）→ HarmonyOS (OHOS) 原生库 libfluxdo_net.so
#
# 用法（Windows 侧）：
#   wsl bash /mnt/c/Users/iceblock/fluxdo/repo/ohos/tools/build-netcore-ohos.sh [x86_64|aarch64|all]
#
# 设计要点：
#  - OHOS NDK 取 DevEco 自带的 Windows 版（只用其中的 sysroot / libc++ / libunwind / compiler-rt 与 cmake 无关部分），
#    编译器用 WSL 宿主 clang 18（NDK 自带 clang 是 Windows .exe，WSL 无法执行）。
#  - 不读取、不改写 ~/.cargo/config.toml 与 ~/ohos-bin；包装器、工具链文件全部生成在 $WORK 下，
#    编译参数用环境变量传入。
#  - BoringSSL（rama-boring-sys）与 aws-lc-sys（shadowsocks-crypto 经 aws-lc-rs 引入）共用同一份
#    自写 CMake 工具链文件，避免 NDK 的 ohos.toolchain.cmake 指向 Windows clang.exe。
#  - C++ 运行库静态链接（libc++_static.a + libc++abi.a，后者由 build.rs 的 ohos 补丁追加），
#    libunwind 链 NDK 真实的 libunwind.a（release 配置 panic=unwind，FFI 靠 catch_unwind，不能用桩）。
#  - 产物目录与 CARGO_TARGET_DIR 放在 WSL 本地盘，不在仓库里生成 target/。
#
# 环境变量（可选）：OHOS_NATIVE（NDK native 目录）、WORK（构建根目录）、CARGO_BIN
set -euo pipefail

ARCH_ARG="${1:-all}"

REPO="/mnt/c/Users/iceblock/fluxdo/repo"
CRATE="$REPO/core/net_core"
NDK="${OHOS_NATIVE:-/mnt/c/Users/iceblock/DevEcoStudio/sdk/default/openharmony/native}"
WORK="${WORK:-$HOME/fluxdo-build}"
TARGET_DIR="$WORK/net_core-target"
WRAP="$WORK/ohos-cc"
CARGO="${CARGO_BIN:-$HOME/.cargo/bin/cargo}"
SYSROOT="$NDK/sysroot"
RES="$NDK/llvm/lib/clang/15.0.4"
LIBCXX_INC="$NDK/llvm/include/libcxx-ohos/include/c++/v1"
LIBCLANG_DIR="${LIBCLANG_PATH:-/usr/lib/llvm-18/lib}"

die() { echo "!! $*" >&2; exit 1; }

# ---------- 预检 ----------
for t in clang clang++ cmake perl openssl ar nm readelf file sha256sum; do
  command -v "$t" >/dev/null || die "缺少 $t"
done
[ -x "$CARGO" ] || die "缺少 cargo：$CARGO"
[ -d "$SYSROOT/usr/include" ] || die "NDK sysroot 不存在：$SYSROOT（可设 OHOS_NATIVE）"
[ -d "$RES" ] || die "缺少 clang resource-dir：$RES"
[ -d "$LIBCXX_INC" ] || die "缺少 libc++ 头文件：$LIBCXX_INC"
ls "$LIBCLANG_DIR"/libclang*.so* >/dev/null 2>&1 || die "缺少 libclang（apt: libclang-18-dev）：$LIBCLANG_DIR"
command -v go >/dev/null || echo "-- 注意：宿主没有 go；BoringSSL 若在配置阶段要求 go 会失败，届时再处理"

case "$ARCH_ARG" in
  x86_64|aarch64) ARCHS=("$ARCH_ARG") ;;
  all) ARCHS=(x86_64 aarch64) ;;
  *) die "用法：$0 [x86_64|aarch64|all]" ;;
esac

mkdir -p "$WRAP" "$TARGET_DIR"

# ---------- build.rs 需要的 CA 证书 ----------
# 与 build.rs 的 openssl 回退一致，但提前生成可避免 build.rs 往 assets/、android/ 目录写副本（证书在 .gitignore 中）。
if [ ! -f "$CRATE/certs/ca.crt" ] || [ ! -f "$CRATE/certs/ca.key" ]; then
  echo "=== 生成占位 CA 证书（certs/ 已被 .gitignore）==="
  mkdir -p "$CRATE/certs"
  ( cd "$CRATE" && \
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout certs/ca.key -out certs/ca.crt -days 3650 -nodes \
      -subj "/CN=DOH Proxy CA/O=DOH Proxy/C=CN" && \
    openssl x509 -in certs/ca.crt -outform DER -out certs/ca.der )
else
  echo "-- certs/ca.crt 已存在，复用"
fi

# ---------- 每个架构生成包装器与工具链文件 ----------
gen_wrappers() {
  local arch="$1"
  local libdir="$NDK/llvm/lib/${arch}-linux-ohos"
  local common="-target ${arch}-linux-ohos --sysroot=$SYSROOT -D__MUSL__ -Wno-unused-command-line-argument"

  # 编译用：不指定 resource-dir，使用宿主 clang 自带内建头（intrinsics 与 clang 18 配套）
  # zstd 的 dictBuilder/cover.c：定义了 __linux__ 且没有 __ANDROID__ 时会开 _GNU_SOURCE 并调用 qsort_r，
  # 而 OHOS musl 只有 qsort。仅对这个文件追加 -D__ANDROID__，让它走 C90 qsort 兜底
  # （字典训练运行时用不到，不可重入问题无影响）。不能放进全局 CFLAGS，否则会污染 BoringSSL / aws-lc 的平台判断。
  cat > "$WRAP/cc-$arch" <<EOF
#!/bin/bash
extra=()
for a in "\$@"; do
  case "\$a" in
    *dictBuilder/cover.c) extra=(-D__ANDROID__) ;;
  esac
done
exec /usr/bin/clang $common "\${extra[@]}" "\$@"
EOF
  cat > "$WRAP/cxx-$arch" <<EOF
#!/bin/bash
exec /usr/bin/clang++ $common -nostdinc++ -isystem $LIBCXX_INC "\$@"
EOF
  # 链接用：compiler-rt / crt 取 NDK 的 resource-dir；NDK libc++/libunwind 目录放最前，
  # 使 Rust 的 -lunwind 命中真实 libunwind.a 而不是空桩
  cat > "$WRAP/ld-$arch" <<EOF
#!/bin/bash
exec /usr/bin/clang -target ${arch}-linux-ohos \\
  -resource-dir=$RES \\
  --sysroot=$SYSROOT \\
  -L$libdir \\
  -L$SYSROOT/usr/lib/${arch}-linux-ohos \\
  -unwindlib=none --rtlib=compiler-rt -fuse-ld=lld \\
  -Wno-unused-command-line-argument "\$@"
EOF
  chmod +x "$WRAP/cc-$arch" "$WRAP/cxx-$arch" "$WRAP/ld-$arch"

  local proc="$arch"
  cat > "$WRAP/toolchain-$arch.cmake" <<EOF
# 自动生成：OHOS 交叉编译工具链（宿主 clang + NDK sysroot）
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $proc)
set(CMAKE_C_COMPILER   $WRAP/cc-$arch)
set(CMAKE_CXX_COMPILER $WRAP/cxx-$arch)
set(CMAKE_ASM_COMPILER $WRAP/cc-$arch)
set(CMAKE_AR /usr/bin/ar CACHE FILEPATH "")
set(CMAKE_RANLIB /usr/bin/ranlib CACHE FILEPATH "")
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_FLAGS_INIT "-fPIC -ffunction-sections -fdata-sections")
set(CMAKE_CXX_FLAGS_INIT "-fPIC -ffunction-sections -fdata-sections")
set(CMAKE_ASM_FLAGS_INIT "-fPIC")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
EOF
}

build_arch() {
  local arch="$1" triple abi
  case "$arch" in
    x86_64)  triple=x86_64-unknown-linux-ohos;  abi=x86_64 ;;
    aarch64) triple=aarch64-unknown-linux-ohos; abi=arm64-v8a ;;
  esac
  local libdir="$NDK/llvm/lib/${arch}-linux-ohos"
  for f in libc++_static.a libc++abi.a libunwind.a; do
    [ -f "$libdir/$f" ] || die "NDK 缺少 $libdir/$f"
  done
  gen_wrappers "$arch"

  local t_="${triple//-/_}"
  local U; U="$(echo "$triple" | tr 'a-z-' 'A-Z_')"
  local outdir="$REPO/ohos/entry/libs/$abi"
  mkdir -p "$outdir"

  echo "=== build $triple （CARGO_TARGET_DIR=$TARGET_DIR）==="
  (
    cd "$CRATE"
    export "CC_${t_}=$WRAP/cc-$arch"
    export "CXX_${t_}=$WRAP/cxx-$arch"
    export "AR_${t_}=/usr/bin/ar"
    export "CARGO_TARGET_${U}_LINKER=$WRAP/ld-$arch"
    # BoringSSL：C++ 运行库静态；工具链文件同时给 boring-sys 与 aws-lc-sys（它们按目标三元组读取）
    export "BORING_BSSL_RUST_CPPLIB_${t_}=c++_static"
    export "CMAKE_TOOLCHAIN_FILE_${t_}=$WRAP/toolchain-$arch.cmake"
    export "AWS_LC_SYS_CMAKE_TOOLCHAIN_FILE_${t_}=$WRAP/toolchain-$arch.cmake"
    # zstd-sys 的 qsort_r 问题由 cc 包装器针对 cover.c 处理（见 gen_wrappers），两个 ABI 都生效
    export "CFLAGS_${t_}=${CFLAGS_EXTRA:-}"
    # bindgen：宿主 libclang + OHOS sysroot（boring-sys 在有工具链文件时不会自己加 sysroot）
    export LIBCLANG_PATH="$LIBCLANG_DIR"
    export "BINDGEN_EXTRA_CLANG_ARGS_${t_}=--target=$triple --sysroot=$SYSROOT -D__MUSL__"
    export CARGO_TARGET_DIR="$TARGET_DIR"
    # 防止 aws-lc-sys 误走 NDK 自带工具链文件（指向 Windows clang.exe）
    unset OHOS_NDK_HOME OHOS_SDK_NATIVE
    "$CARGO" build --release --lib --locked --target "$triple"
  ) 2>&1 | tee "$WORK/build-netcore-$arch.log" | tail -n "${TAIL_LINES:-60}"
  [ "${PIPESTATUS[0]}" -eq 0 ] || die "$triple 编译失败，完整日志：$WORK/build-netcore-$arch.log"

  local so="$TARGET_DIR/$triple/release/libfluxdo_net.so"
  [ -f "$so" ] || die "未找到产物 $so"
  cp -f "$so" "$outdir/libfluxdo_net.so"

  echo "--- 产物：$outdir/libfluxdo_net.so"
  ls -l "$outdir/libfluxdo_net.so"
  file "$outdir/libfluxdo_net.so" | cut -c1-160
  sha256sum "$outdir/libfluxdo_net.so"
  echo "-- 未解析 _Unwind 符号数：$(nm -D -u "$outdir/libfluxdo_net.so" 2>/dev/null | grep -c '_Unwind' || true)"
  echo "-- 导出 fluxdo_net_* 符号数：$(nm -D --defined-only "$outdir/libfluxdo_net.so" 2>/dev/null | grep -c 'fluxdo_net_' || true)"
  echo "-- 未解析的 C++ 符号数（应为 0，说明 libc++ 已静态链入）：$(nm -D -u "$outdir/libfluxdo_net.so" 2>/dev/null | grep -c '_ZN\|_ZS\|_Zn' || true)"
  echo "-- DT_NEEDED："
  readelf -d "$outdir/libfluxdo_net.so" | grep NEEDED || true
}

for a in "${ARCHS[@]}"; do build_arch "$a"; done

echo "=== 完成 ==="
ls -l "$REPO"/ohos/entry/libs/*/libfluxdo_net.so
