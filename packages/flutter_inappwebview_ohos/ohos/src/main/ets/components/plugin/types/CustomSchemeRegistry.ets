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
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';

const LOG_TAG = 'CustomSchemeRegistry';
/** ArkWeb allows at most 10 custom schemes at a time. */
const MAX_CUSTOM_SCHEMES = 10;
/** customizeSchemes must run before any Web component is created; once one exists, it always fails with this code. */
const ERR_WEB_COMPONENT_EXISTS = 17100020;

/**
 * Registers InAppWebViewSettings.resourceCustomSchemes with ArkWeb so that
 * custom-scheme requests can be intercepted via onInterceptRequest.
 * Prefer calling this before any Web component is created.
 */
export default class CustomSchemeRegistry {
  private static registeredSchemes: Set<string> = new Set<string>();
  /** Schemes whose registration failed with ERR_WEB_COMPONENT_EXISTS; retries are guaranteed futile, so skip them. */
  private static skippedSchemes: Set<string> = new Set<string>();

  static register(schemes: Array<string> | null | undefined): void {
    if (schemes == null || schemes.length === 0) {
      return;
    }

    let toRegister: webview.WebCustomScheme[] = [];
    for (let i = 0; i < schemes.length; i++) {
      let scheme = schemes[i];
      if (scheme == null || scheme.length === 0) {
        continue;
      }
      let name = scheme.toLowerCase();
      if (CustomSchemeRegistry.registeredSchemes.has(name) || CustomSchemeRegistry.skippedSchemes.has(name)) {
        continue;
      }
      if (CustomSchemeRegistry.registeredSchemes.size + toRegister.length >= MAX_CUSTOM_SCHEMES) {
        Log.e(LOG_TAG, 'customizeSchemes limit reached (' + MAX_CUSTOM_SCHEMES + '), skip: ' + name);
        break;
      }
      toRegister.push({
        schemeName: name,
        isSupportCORS: true,
        isSupportFetch: true,
        isStandard: true
      });
    }

    if (toRegister.length === 0) {
      return;
    }

    try {
      webview.WebviewController.customizeSchemes(toRegister);
      for (let i = 0; i < toRegister.length; i++) {
        CustomSchemeRegistry.registeredSchemes.add(toRegister[i].schemeName);
      }
      let names: string[] = [];
      for (let i = 0; i < toRegister.length; i++) {
        names.push(toRegister[i].schemeName);
      }
      Log.i(LOG_TAG, 'customizeSchemes registered: ' + JSON.stringify(names));
    } catch (e) {
      if ((e as BusinessError)?.code === ERR_WEB_COMPONENT_EXISTS) {
        let skipped: string[] = [];
        for (let i = 0; i < toRegister.length; i++) {
          CustomSchemeRegistry.skippedSchemes.add(toRegister[i].schemeName);
          skipped.push(toRegister[i].schemeName);
        }
        Log.w(LOG_TAG, 'customizeSchemes skipped (' + ERR_WEB_COMPONENT_EXISTS + ': a Web component already exists,' +
          ' customizeSchemes only takes effect before the first one, registration stays process-global): ' +
          JSON.stringify(skipped));
      } else {
        Log.e(LOG_TAG, 'customizeSchemes failed: ' + JSON.stringify(e));
      }
    }
  }
}
