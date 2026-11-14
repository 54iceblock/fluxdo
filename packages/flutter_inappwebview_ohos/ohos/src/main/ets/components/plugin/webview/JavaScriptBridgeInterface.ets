/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import { Log } from '@ohos/flutter_ohos';
import JavaScriptBridgeJS from '../plugin_scripts_js/JavaScriptBridgeJS';
import OnZoomScaleChangedJS from '../plugin_scripts_js/OnZoomScaleChangedJS';
import OnJsBeforeUnloadJS from '../plugin_scripts_js/OnJsBeforeUnloadJS';
import PrintJobSettings from '../print_job/PrintJobSettings';
import InAppWebView from './in_app_webview/InAppWebView';
import Util from '../Util';
import FrameUrlMatcher from './FrameUrlMatcher';
import { uri } from '@kit.ArkTS';
import { CallJsHandlerCallback, PrintRequestCallback } from './WebViewChannelDelegate';
import {
  WebMessageListenerPostMessagePayload,
  webMessageCompatFromJsMessage
} from './web_message/WebMessageListenerTypes';
import WebMessageCompatExt from '../types/WebMessageCompatExt';

const LOG_TAG = "JSBridgeInterface";

interface CallAsyncJavaScriptPayload {
  resultUuid: string;
}

interface EvaluateJavaScriptWithContentWorldPayload {
  resultUuid: string;
  value?: Object;
}

interface ZoomScaleChangedJsPayload {
  oldScale: number;
  newScale: number;
}

export default class JavaScriptBridgeInterface {
  private inAppWebView: InAppWebView | null;
  // 来源日志限频计数：key = handler|frameUrl|isMainFrame
  private callLogCounts: Map<string, number> = new Map<string, number>();

  constructor(inAppWebView: InAppWebView) {
    this.inAppWebView = inAppWebView;
  }

  private getWebMessageListenerSourceOrigin(): string | null {
    if (this.inAppWebView == null) {
      return null;
    }
    let url: string | null = this.inAppWebView.getUrl();
    if (url == null || url.length === 0) {
      return null;
    }
    try {
      let parsed: uri.URI = new uri.URI(url);
      let origin: string = parsed.scheme + '://' + parsed.host;
      if (parsed.port != null && parsed.port !== '' && parsed.port !== '-1') {
        origin += ':' + parsed.port;
      }
      return origin;
    } catch (e) {
      return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    }
  }

  _hideContextMenu(): void {
    if (this.inAppWebView == null) {
      return;
    }
    this.inAppWebView.hideContextMenu()
  }

  /** 去掉 fragment，避免 #hash 变化导致主文档 URL 比较失败。 */
  private stripFragment(url: string): string {
    let idx = url.indexOf('#');
    return idx >= 0 ? url.substring(0, idx) : url;
  }

  /** 由 URL 解析 scheme://host[:port]；解析失败返回 null。 */
  private originOf(url: string): string | null {
    try {
      let parsed: uri.URI = new uri.URI(url);
      if (!parsed.scheme || !parsed.host) {
        return null;
      }
      let origin: string = parsed.scheme + '://' + parsed.host;
      if (parsed.port != null && parsed.port !== '' && parsed.port !== '-1') {
        origin += ':' + parsed.port;
      }
      return origin;
    } catch (e) {
      return null;
    }
  }

  /**
   * FluxDO 改动：取本次 JavaScriptProxy 调用方 frame 的 URL。
   * getLastJavascriptProxyCallingFrameUrl 返回「最近一次」调用方，必须在 _callHandler
   * 入口同步调用（此处之前没有任何 await），且在 UI 线程。取不到返回 null。
   */
  private readCallingFrameUrl(): string | null {
    if (this.inAppWebView == null) {
      return null;
    }
    try {
      let url: string = this.inAppWebView.getController().getLastJavascriptProxyCallingFrameUrl();
      return (url != null && url.length > 0) ? url : null;
    } catch (e) {
      Log.w(LOG_TAG, "getLastJavascriptProxyCallingFrameUrl failed: " + e);
      return null;
    }
  }

  /**
   * 判断调用方 frame 是否主框架：调用方 frame URL 与主文档 URL 相等（忽略 fragment），
   * 或（真机 HarmonyOS 7 / API 26 实测，ROM 把 frame URL 截断为「最后一个 / 为止」的目录形式，
   * 如 /apps/<uuid>?embed_mode=true → /apps/）等于主文档的目录形式。规则见 FrameUrlMatcher。
   * ArkWeb 没有「调用方是否主框架」的直接接口（WebResourceRequest.isMainFrame 只用于请求拦截）。
   * 局限：iframe 与主文档同 origin 同目录（或完全相同 URL）会被误判为主框架；
   * 不同目录或跨 origin 的 iframe 可区分。
   * 另一侧：主文档 URL 取不到、或与 frame URL 表示不一致（如 loadData 的 data: URL），
   * 会判为非主框架——这是 fail-closed 方向。
   * 取不到 frame URL 时返回 null（不确定），由 Dart 侧拒绝。
   */
  private computeIsMainFrame(frameUrl: string | null): boolean | null {
    if (frameUrl == null || this.inAppWebView == null) {
      return null;
    }
    let candidates: string[] = [];
    try {
      candidates.push(this.inAppWebView.getUrl());
    } catch (e) {
    }
    try {
      candidates.push(this.inAppWebView.getController().getUrl());
    } catch (e) {
    }
    for (let c of candidates) {
      if (FrameUrlMatcher.isSameDocumentOrDirectoryForm(frameUrl, c)) {
        return true;
      }
    }
    return false;
  }

  _callHandler(handlerName: string, callHandlerID: string, args: string): void {
    if (this.inAppWebView == null) {
      return;
    }
    // 必须最先取来源：getLastJavascriptProxyCallingFrameUrl 只记录最近一次调用。
    const callingFrameUrl: string | null = this.readCallingFrameUrl();
    const callingOrigin: string | null = callingFrameUrl != null ? this.originOf(callingFrameUrl) : null;
    const callingIsMainFrame: boolean | null = this.computeIsMainFrame(callingFrameUrl);
    // 真机验证证据：非主框架 / 来源未知的调用，以及小程序 handler 的所有调用都留 hilog。
    // flutter_ohos 的 Log 默认级别为 WARN，Log.i 在 release 中会被丢弃，故用 Log.w；
    // 同一 handler+frameUrl+isMainFrame 组合仅首次与之后每 50 次记录一条，避免 250ms 轮询刷屏。
    if (callingIsMainFrame !== true || handlerName.startsWith('fluxdoMiniApp')) {
      const logKey: string = handlerName + "|" + callingFrameUrl + "|" + callingIsMainFrame;
      const seen: number = (this.callLogCounts.get(logKey) ?? 0) + 1;
      this.callLogCounts.set(logKey, seen);
      if (seen === 1 || seen % 50 === 0) {
        Log.w(LOG_TAG, "callHandler " + handlerName + " frameUrl=" + callingFrameUrl +
          " origin=" + callingOrigin + " isMainFrame=" + callingIsMainFrame + " count=" + seen);
      }
    }
    if (handlerName == "__onPopupWindowClose") {
      // Popup opened via about:blank may not be engine-bound (setWebController(null)
      // to avoid renderer stall). Bridge window.close() to onCloseWindow.
      if (this.inAppWebView.channelDelegate != null) {
        this.inAppWebView.channelDelegate.onCloseWindow();
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    }
    if (handlerName == "__windowOpenAboutBlank") {
      // loadData pages may miss document-start hooks; HTML-embedded hook calls
      // the native proxy directly when ArkWeb skips onWindowNew for about:blank.
      if (this.inAppWebView.inAppWebViewClient != null) {
        this.inAppWebView.inAppWebViewClient.synthesizeAboutBlankCreateWindow();
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    }
    if (handlerName == "onPrintRequest") {
      let settings = new PrintJobSettings();
      settings.handledByClient = true;
      let printJobId = this.inAppWebView.printCurrentPage(settings);
      if (printJobId != null && this.inAppWebView != null && this.inAppWebView.channelDelegate != null) {
        this.inAppWebView.channelDelegate.onPrintRequest(this.inAppWebView.getUrl(), printJobId, new InnerPrintRequestCallback(this.inAppWebView, printJobId));
      }
      return;
    } else if (handlerName == "callAsyncJavaScript") {
      try {
        let jsonArray: CallAsyncJavaScriptPayload[] = JSON.parse(args) as CallAsyncJavaScriptPayload[];
        let jsonObject: CallAsyncJavaScriptPayload = jsonArray[0];
        let resultUuid: string = jsonObject.resultUuid;
        if (!resultUuid) {
          Log.e(LOG_TAG, "callAsyncJavaScript: Failed to extract resultUuid from args: " + args);
          return;
        }
        let callAsyncJavaScriptCallback = this.inAppWebView.callAsyncJavaScriptCallbacks.get(resultUuid);
        if (callAsyncJavaScriptCallback != null) {
          callAsyncJavaScriptCallback.onReceiveValue(JSON.stringify(jsonObject));
          this.inAppWebView.callAsyncJavaScriptCallbacks.delete(resultUuid);
        } else {
          Log.w(LOG_TAG, "callAsyncJavaScript: No callback found for resultUuid: " + resultUuid);
        }
      } catch (e) {
        Log.e(LOG_TAG, "callAsyncJavaScript error", e);
      }
      return;
    } else if (handlerName == "evaluateJavaScriptWithContentWorld") {
      try {
        let jsonArray: EvaluateJavaScriptWithContentWorldPayload[] =
          JSON.parse(args) as EvaluateJavaScriptWithContentWorldPayload[];
        let jsonObject: EvaluateJavaScriptWithContentWorldPayload = jsonArray[0];
        let resultUuid: string = jsonObject.resultUuid;
        if (!resultUuid) {
          Log.e(LOG_TAG, "evaluateJavaScriptWithContentWorld: Failed to extract resultUuid from args: " + args);
          return;
        }
        let evaluateJavaScriptCallback = this.inAppWebView.evaluateJavaScriptContentWorldCallbacks.get(resultUuid);
        if (evaluateJavaScriptCallback != null) {
          let value: Object | undefined = jsonObject.value;
          evaluateJavaScriptCallback.onReceiveValue(value != null ? value.toString() : "null");
          this.inAppWebView.evaluateJavaScriptContentWorldCallbacks.delete(resultUuid);
        } else {
          Log.w(LOG_TAG, "evaluateJavaScriptWithContentWorld: No callback found for resultUuid: " + resultUuid);
        }
      } catch (e) {
        Log.e(LOG_TAG, "evaluateJavaScriptWithContentWorld error", e);
      }
      return;
    } else if (handlerName == "onWebMessageListenerPostMessageReceived") {
      try {
        let jsonArray: WebMessageListenerPostMessagePayload[] =
          JSON.parse(args) as WebMessageListenerPostMessagePayload[];
        let payload: WebMessageListenerPostMessagePayload = jsonArray[0];
        let jsObjectName: string = payload.jsObjectName;
        let message: WebMessageCompatExt = webMessageCompatFromJsMessage(payload.message);
        let sourceOrigin: string | null = this.getWebMessageListenerSourceOrigin();
        this.inAppWebView.dispatchWebMessageListenerPostMessage(
          jsObjectName, message, sourceOrigin, true);
      } catch (e) {
        Log.e(LOG_TAG, "onWebMessageListenerPostMessageReceived error", e);
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    } else if (handlerName == OnJsBeforeUnloadJS.HANDLER_NAME) {
      if (this.inAppWebView != null) {
        this.inAppWebView.hasBeforeUnloadHandler = true;
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    } else if (handlerName == OnZoomScaleChangedJS.HANDLER_NAME) {
      try {
        let jsonArray: ZoomScaleChangedJsPayload[] = JSON.parse(args) as ZoomScaleChangedJsPayload[];
        let event: ZoomScaleChangedJsPayload = jsonArray[0];
        let oldScale = Number(event.oldScale);
        let newScale = Number(event.newScale);
        if (!Number.isNaN(oldScale) && !Number.isNaN(newScale)) {
          let normalizedNewScale = newScale / Util.getPixelDensity();
          if (Math.abs(this.inAppWebView.zoomScale - normalizedNewScale) >= 0.01 &&
            this.inAppWebView.channelDelegate != null) {
            this.inAppWebView.zoomScale = normalizedNewScale;
            this.inAppWebView.channelDelegate.onZoomScaleChanged(oldScale, newScale);
          }
        }
      } catch (e) {
        Log.e(LOG_TAG, "", e);
      }
      new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID).defaultBehaviour("null");
      return;
    }
    if (this.inAppWebView.channelDelegate != null) {
      this.inAppWebView.channelDelegate.onCallJsHandler(handlerName, args,
        new InnerCallJsHandlerCallback(this.inAppWebView, callHandlerID),
        callingFrameUrl, callingOrigin, callingIsMainFrame);
    }
  }

  getMethodList(): Array<string> {
    return ["_hideContextMenu", "_callHandler"];
  }

  dispose() {
    this.inAppWebView = null;
  }
}

class InnerPrintRequestCallback extends PrintRequestCallback {
  private inAppWebView: InAppWebView;
  private printJobId: string;

  constructor(inAppWebView: InAppWebView, printJobId: string) {
    super();
    this.inAppWebView = inAppWebView;
    this.printJobId = printJobId;
  }

  nonNullSuccess(handledByClient: boolean): boolean {
    return !handledByClient;
  }

  defaultBehaviour(handledByClient: boolean | null) {
    // Keep the PrintJobController channel alive until Dart calls dispose().
    // Integration tests capture the controller in onPrintRequest and invoke
    // getInfo/cancel/restart even when returning false.
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null) {
    Log.e(LOG_TAG, errorCode + ", " + ((errorMessage != null) ? errorMessage : ""));
    this.defaultBehaviour(null);
  }
}

class InnerCallJsHandlerCallback extends CallJsHandlerCallback {
  private inAppWebView: InAppWebView;
  private _callHandlerID: string;

  constructor(inAppWebView: InAppWebView, _callHandlerID: string) {
    super();
    this.inAppWebView = inAppWebView;
    this._callHandlerID = _callHandlerID;
  }

  defaultBehaviour(json: Object | null) {
    if (this.inAppWebView == null) {
      // The webview has already been disposed, ignore.
      return;
    }
    const handlerIdNum = Number(this._callHandlerID);
    if (isNaN(handlerIdNum)) {
      Log.w(LOG_TAG, "Invalid callHandlerID, expected numeric value: " + this._callHandlerID);
      return;
    }

    const handlerId = JSON.stringify(this._callHandlerID);
    // json 参数已经是 Dart 侧通过 jsonEncode 编码后的 JSON 字符串
    // 不要再调用 JSON.stringify，否则会导致双重序列化
    // 这与 Android 实现一致，直接拼接 json 字符串到 JS 代码
    let jsonPayload: string = (json != null) ? String(json) : 'null';
    let sourceCode = "if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "] != null) { " +
      "window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "].resolve(" + jsonPayload + "); " +
      "delete window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "]; " +
      "}";
    this.inAppWebView.getController().runJavaScriptExt(sourceCode);
  }

  error(errorCode: string, errorMessage: string, errorDetails: Object | null) {
    let message = errorCode + ((errorMessage != null) ? ", " + errorMessage : "");
    Log.e(LOG_TAG, message);

    if (this.inAppWebView == null) {
      // The webview has already been disposed, ignore.
      return;
    }
    const handlerIdNum = Number(this._callHandlerID);
    if (isNaN(handlerIdNum)) {
      Log.w(LOG_TAG, "Invalid callHandlerID, expected numeric value: " + this._callHandlerID);
      return;
    }

    const handlerId = JSON.stringify(this._callHandlerID);
    let sourceCode = "if (window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "] != null) { " +
      "window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "].reject(new Error(" + JSON.stringify(message) + ")); " +
      "delete window." + JavaScriptBridgeJS.JAVASCRIPT_BRIDGE_NAME + "[" + handlerId + "]; " +
      "}";
    this.inAppWebView.getController().runJavaScriptExt(sourceCode);
  }
}