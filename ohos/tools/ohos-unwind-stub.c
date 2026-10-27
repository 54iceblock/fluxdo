/*
 * HarmonyOS x86_64 的 NDK 不提供 libunwind.a（aarch64 有）。
 *
 * Rust 的 std 会引用 _Unwind_* 符号（backtrace/panic 支持），缺库时
 * dlopen 会报 "Error relocating ... _Unwind_Resume: symbol not found"。
 *
 * 我们以 panic=abort 编译 cdylib，正常情况下不会真正展开栈；
 * 这里提供最小符号桩让动态库能加载，backtrace 退化为空（可接受）。
 * aarch64 构建直接链接 NDK 自带的真实 libunwind.a，不使用本桩。
 */
#include <stdint.h>
#include <stdlib.h>
#include <unwind.h>

_Unwind_Reason_Code _Unwind_Backtrace(_Unwind_Trace_Fn trace, void *arg) {
  (void)trace;
  (void)arg;
  return _URC_END_OF_STACK;
}

void *_Unwind_FindEnclosingFunction(void *pc) {
  (void)pc;
  return 0;
}

uintptr_t _Unwind_GetCFA(struct _Unwind_Context *ctx) {
  (void)ctx;
  return 0;
}

uintptr_t _Unwind_GetIP(struct _Unwind_Context *ctx) {
  (void)ctx;
  return 0;
}

uintptr_t _Unwind_GetIPInfo(struct _Unwind_Context *ctx, int *ip_before_insn) {
  (void)ctx;
  if (ip_before_insn != 0) {
    *ip_before_insn = 0;
  }
  return 0;
}

void _Unwind_SetIP(struct _Unwind_Context *ctx, uintptr_t value) {
  (void)ctx;
  (void)value;
}

uintptr_t _Unwind_GetGR(struct _Unwind_Context *ctx, int index) {
  (void)ctx;
  (void)index;
  return 0;
}

void _Unwind_SetGR(struct _Unwind_Context *ctx, int index, uintptr_t value) {
  (void)ctx;
  (void)index;
  (void)value;
}

void _Unwind_Resume(struct _Unwind_Exception *exc) {
  (void)exc;
  abort();
}

_Unwind_Reason_Code _Unwind_RaiseException(struct _Unwind_Exception *exc) {
  (void)exc;
  abort();
}

void _Unwind_DeleteException(struct _Unwind_Exception *exc) { (void)exc; }

void *_Unwind_GetLanguageSpecificData(struct _Unwind_Context *ctx) {
  (void)ctx;
  return 0;
}

uintptr_t _Unwind_GetRegionStart(struct _Unwind_Context *ctx) {
  (void)ctx;
  return 0;
}

uintptr_t _Unwind_GetTextRelBase(struct _Unwind_Context *ctx) {
  (void)ctx;
  return 0;
}

uintptr_t _Unwind_GetDataRelBase(struct _Unwind_Context *ctx) {
  (void)ctx;
  return 0;
}
