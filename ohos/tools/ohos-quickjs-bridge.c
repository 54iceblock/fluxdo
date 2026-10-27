/**
 * HarmonyOS QuickJS 桥（cook 渲染用，持久上下文）
 *
 * 用法：
 *   void* h = ohos_js_new();                       // 新建 runtime+context
 *   char* r = ohos_js_eval(h, "code", &err);       // 执行（需 ohos_js_free 释放 r/err）
 *   ohos_js_dispose(h);                            // 释放
 *
 * 持久上下文是必须的：cook 流程先 eval 整个 bundle 定义全局对象（__fluxdoCook 等），
 * 之后每次渲染再调用这些全局，逐个语句新建 runtime 会丢全局。
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "quickjs.h"

typedef struct OhosJsHandle {
  JSRuntime* rt;
  JSContext* ctx;
} OhosJsHandle;

static char* dup_cstr(const char* s) {
  if (s == NULL) return NULL;
  size_t n = strlen(s) + 1;
  char* p = (char*)malloc(n);
  if (p != NULL) memcpy(p, s, n);
  return p;
}

void* ohos_js_new(void) {
  OhosJsHandle* h = (OhosJsHandle*)malloc(sizeof(OhosJsHandle));
  if (h == NULL) return NULL;
  h->rt = JS_NewRuntime();
  if (h->rt == NULL) {
    free(h);
    return NULL;
  }
  JS_SetMaxStackSize(h->rt, 8 * 1024 * 1024);
  h->ctx = JS_NewContext(h->rt);
  if (h->ctx == NULL) {
    JS_FreeRuntime(h->rt);
    free(h);
    return NULL;
  }
  return (void*)h;
}

/** 执行 JS；成功返回结果字符串，失败返回 NULL 并把原因写入 out_err。 */
char* ohos_js_eval(void* handle, const char* code, char** out_err) {
  if (out_err != NULL) *out_err = NULL;
  OhosJsHandle* h = (OhosJsHandle*)handle;
  if (h == NULL || h->ctx == NULL) {
    if (out_err != NULL) *out_err = dup_cstr("invalid handle");
    return NULL;
  }
  if (code == NULL) {
    if (out_err != NULL) *out_err = dup_cstr("empty code");
    return NULL;
  }

  JSValue val = JS_Eval(h->ctx, code, strlen(code), "cook.js", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(val)) {
    JSValue exc = JS_GetException(h->ctx);
    const char* msg = JS_ToCString(h->ctx, exc);
    if (out_err != NULL) *out_err = dup_cstr(msg == NULL ? "unknown JS error" : msg);
    if (msg != NULL) JS_FreeCString(h->ctx, msg);
    JS_FreeValue(h->ctx, exc);
    JS_FreeValue(h->ctx, val);
    return NULL;
  }

  char* result = NULL;
  const char* str = JS_ToCString(h->ctx, val);
  if (str != NULL) {
    result = dup_cstr(str);
    JS_FreeCString(h->ctx, str);
  } else if (out_err != NULL) {
    *out_err = dup_cstr("JS_ToCString failed");
  }
  JS_FreeValue(h->ctx, val);
  return result;
}

void ohos_js_dispose(void* handle) {
  OhosJsHandle* h = (OhosJsHandle*)handle;
  if (h == NULL) return;
  if (h->ctx != NULL) JS_FreeContext(h->ctx);
  if (h->rt != NULL) JS_FreeRuntime(h->rt);
  free(h);
}

void ohos_js_free(void* p) {
  if (p != NULL) free(p);
}

/** QuickJS 版本字符串，便于启动时确认库可用。 */
const char* ohos_js_version(void) {
  return JS_GetVersion();
}
