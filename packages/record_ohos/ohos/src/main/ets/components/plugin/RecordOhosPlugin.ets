/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
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
import bundleManager from '@ohos.bundle.bundleManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import { FlutterPlugin, FlutterPluginBinding, MethodChannel, } from '@ohos/flutter_ohos';
import { MethodCallHandlerImpl } from './MethodCallHandlerImpl';

export default class RecordOhosPlugin implements FlutterPlugin {
  private readonly TAG: string = 'RecordOhosPlugin';
  private readonly MESSAGES_CHANNEL = 'com.llfbandit.record/messages';
  private channel: MethodChannel | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "RecordOhosPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), this.MESSAGES_CHANNEL);
    // FluxDO 本地改动：**不在 attach 时申请麦克风权限**。
    // 上游实现会在这里无条件 checkPermission()，导致 App 一冷启动就弹
    // 「允许 FluxDO 访问你的麦克风」——与当前操作无关的索权，应用市场审核会判
    // 不合理。现在权限推迟到 Dart 侧查询 hasPermission()（用户点「录音」）时才检查/申请。
    let methodCallHandlerImpl: MethodCallHandlerImpl = new MethodCallHandlerImpl(
      binding.getBinaryMessenger(),
      (): Promise<boolean> => this.ensurePermission()
    );
    this.channel.setMethodCallHandler(methodCallHandlerImpl);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
      this.channel = null;
    }
  }

  /**
   * 确保已获得麦克风权限：已授予直接返回 true；否则现场向用户申请，并返回最终结果。
   *
   * 只在 Dart 侧调用 `hasPermission()` 时触发（用户点录音），冷启动不再索权。
   */
  async ensurePermission(): Promise<boolean> {
    const permissions: Array<Permissions> = ['ohos.permission.MICROPHONE'];
    // FluxDO 本地改动：留痕，便于用 hilog 证明「只在用户点录音时才走权限申请」，
    // 冷启动阶段不应出现这条日志。
    console.info(this.TAG + ' ensurePermission called on demand (user started recording)');
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId: number = bundleInfo.appInfo.accessTokenId;
      const grantStatus: abilityAccessCtrl.GrantStatus =
        await atManager.checkAccessToken(tokenId, permissions[0]);
      if (grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return true;
      }
      return await this.requestNecessaryPermissions(permissions);
    } catch (err) {
      console.error(this.TAG + ` ensurePermission failed, code is ${err.code}, message is ${err.message}`);
      return false;
    }
  }

  /**
   * 申请录音授权，返回是否全部授予。
   * @param permissions
   */
  async requestNecessaryPermissions(permissions: Array<Permissions>): Promise<boolean> {
    try {
      const context = getContext(this);
      const atManager = abilityAccessCtrl.createAtManager();
      const data = await atManager.requestPermissionsFromUser(context, permissions);
      const results: Array<number> = data.authResults;
      for (let i = 0; i < results.length; i++) {
        if (results[i] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      return results.length > 0;
    } catch (err) {
      console.error(this.TAG + ` requestPermissionsFromUser failed, code is ${err.name}, message is ${err.message}`);
      return false;
    }
  }
}