/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
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

import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodChannel,
  NewWantListener
} from '@ohos/flutter_ohos';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import { BusinessError } from '@kit.BasicServicesKit';
import MethodCallHandlerImpl from './MethodCallHandlerImpl';
import { NotificationManager } from './NotificationManager';
import { AppContext } from './utils/AppContext';

export default class FlutterLocalNotificationsPlugin implements FlutterPlugin, AbilityAware, NewWantListener {
  private channel: MethodChannel | null = null;
  private binding?: AbilityPluginBinding;
  private methodCallHandler: MethodCallHandlerImpl | null = null;
  private readonly appContext: AppContext = new AppContext();
  private readonly notificationManager: NotificationManager = new NotificationManager(this.appContext);

  constructor() {
  }

  /**
   * Handles notification action taps delivered while the ability is running.
   *
   * @param want Incoming Want from the notification action.
   * @param launchParams Ability launch parameters.
   */
  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    try {
      if (!this.channel) {
        return;
      }
      this.methodCallHandler?.onNewWant(want, this.channel);
    } catch (e) {
      Log.e('FlutterLocalNotificationsPlugin', 'onNewWant-->error: ' + JSON.stringify(e));
    }
  }

  /**
   * Binds the plugin to the host UIAbility and stores launch context.
   *
   * @param binding Ability plugin binding from the Flutter engine.
   */
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.binding = binding;
    let launchWant: Want | undefined = binding?.getAbility()?.launchWant;
    this.methodCallHandler?.initLaunchWant(launchWant);
    this.appContext.setAbility(binding.getAbility());
    binding.addOnNewWantListener(this);
    if (launchWant != undefined && this.channel != null) {
      this.methodCallHandler?.onNewWant(launchWant, this.channel);
    }
  }

  /** Clears ability context when the plugin detaches from the ability. */
  onDetachedFromAbility(): void {
    this.methodCallHandler?.initLaunchWant(undefined);
    this.methodCallHandler?.resetPermissionState();
    this.appContext.setAbility(undefined);
    this.binding?.removeOnNewWantListener(this);
    this.binding = undefined;
  }

  /**
   * Returns the plugin class name for Flutter engine registration.
   *
   * @returns Plugin class name string.
   */
  getUniqueClassName(): string {
    return 'FlutterLocalNotificationsPlugin';
  }

  /**
   * Registers the MethodChannel when the Flutter engine attaches.
   *
   * @param binding Flutter plugin binding.
   */
  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'dexterous.com/flutter/local_notifications');
    this.methodCallHandler = new MethodCallHandlerImpl(this.appContext, this.notificationManager);
    this.channel.setMethodCallHandler(this.methodCallHandler);
  }

  /**
   * Tears down the MethodChannel when the Flutter engine detaches.
   *
   * @param binding Flutter plugin binding.
   */
  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
    this.methodCallHandler?.dispose();
    this.methodCallHandler = null;
    this.appContext.setAbility(undefined);
    void this.notificationManager.cancelAllReminders().catch((e: BusinessError) => {
      Log.e('FlutterLocalNotificationsPlugin', 'cancelAllReminders-->error: ' + JSON.stringify(e));
    });
  }
}