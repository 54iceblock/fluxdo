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

import { Log, MethodCall, MethodResult } from '@ohos/flutter_ohos';
import { notificationManager } from '@kit.NotificationKit';
import { LocalNotificationsConstants } from './LocalNotificationsConstants';
import { NotificationManager } from './NotificationManager';
import NotificationSlotDetails from './models/NotificationSlotDetails';
import { NotificationSlotAction } from './models/NotificationSlotAction';
import { SoundSource } from './models/SoundSource';
import { NSlot } from './utils/OhosTypeAliases';
import { readErrorMessage } from './utils/ErrorUtil';

const TAG: string = 'MethodCallSlotHandler';

/** Handles notification slot MethodChannel operations. */
export class MethodCallSlotHandler {
  private readonly notificationManager: NotificationManager;

  constructor(notificationManager: NotificationManager) {
    this.notificationManager = notificationManager;
  }

  /**
   * Adds or updates a notification slot from Dart MethodChannel arguments.
   *
   * @param call Method call containing slot configuration.
   * @param result Flutter result callback.
   */
  async addNotificationSlot(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let notificationSlotDetails: NotificationSlotDetails = NotificationSlotDetails.from(call);
      if (notificationSlotDetails.slotType == undefined ||
        Number.isNaN(Number(notificationSlotDetails.slotType))) {
        result.error(LocalNotificationsConstants.ERROR_INVALID_PARAMETERS, 'slotType is required', null);
        return;
      }
      Log.d(TAG, 'addNotificationSlot-->request: ' + JSON.stringify(notificationSlotDetails));
      await this.notificationManager.addNotificationSlot(notificationSlotDetails);
      result.success(null);
    } catch (e) {
      result.error(LocalNotificationsConstants.ERROR_SLOT_OPERATION_FAILED, readErrorMessage(e), null);
      Log.e(TAG, 'addNotificationSlot-->err msg: ' + JSON.stringify(e));
    }
  }

  /**
   * Removes a notification slot by slot type.
   *
   * @param call Method call containing slotType argument.
   * @param result Flutter result callback.
   */
  async deleteNotificationSlot(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let slotType: number | undefined = this.readSlotTypeArgument(call);
      if (slotType == undefined) {
        result.error(LocalNotificationsConstants.ERROR_INVALID_PARAMETERS, 'slotType is required', null);
        return;
      }
      Log.d(TAG, 'deleteNotificationSlot-->slotType: ' + slotType);
      await this.notificationManager.removeNotificationSlot(slotType);
      result.success(null);
    } catch (e) {
      result.error(LocalNotificationsConstants.ERROR_SLOT_OPERATION_FAILED, readErrorMessage(e), null);
      Log.e(TAG, 'deleteNotificationSlot-->err msg: ' + JSON.stringify(e));
    }
  }

  /**
   * Reads slotType from a MethodChannel map or a legacy scalar argument.
   *
   * @param call Incoming MethodChannel call from Dart.
   * @returns Parsed slot type or undefined when missing/invalid.
   */
  private readSlotTypeArgument(call: MethodCall): number | undefined {
    let rawSlotType: Object | undefined = call.argument(LocalNotificationsConstants.SLOT_TYPE);
    if (rawSlotType == null || rawSlotType === '') {
      let directArgument: Object | undefined = call.args;
      if (typeof directArgument === 'number') {
        rawSlotType = directArgument;
      } else {
        return undefined;
      }
    }
    let slotType: number = Number(rawSlotType);
    if (Number.isNaN(slotType)) {
      return undefined;
    }
    return slotType;
  }

  /**
   * Returns all notification slots configured for the application.
   *
   * @param result Flutter result callback for the slot list response.
   */
  async getNotificationSlots(result: MethodResult): Promise<void> {
    try {
      Log.d(TAG, 'getNotificationSlots-->request: ');
      let notificationSlots: NSlot[] = await this.notificationManager.getAllNotificationSlots();
      let slotDetailsList: Map<string, Object>[] = [];
      for (let notificationSlot of notificationSlots) {
        let map: Map<string, Object> = new Map();
        let slotSound: string = notificationSlot.sound ?? '';
        let slotType: number = notificationSlot.notificationType ??
          notificationManager.SlotType.UNKNOWN_TYPE;
        map.set(LocalNotificationsConstants.SLOT_TYPE, slotType);
        map.set(LocalNotificationsConstants.DESCRIPTION, notificationSlot.desc ?? '');
        map.set(LocalNotificationsConstants.SHOW_BADGE, notificationSlot.badgeFlag ?? false);
        map.set(LocalNotificationsConstants.IMPORTANCE,
          notificationSlot.level ?? notificationManager.SlotLevel.LEVEL_DEFAULT);
        map.set(LocalNotificationsConstants.PLAY_SOUND, notificationSlot.sound != null);
        map.set(LocalNotificationsConstants.SOUND, slotSound);
        map.set(LocalNotificationsConstants.SOUND_SOURCE, this.resolveSlotSoundSource(slotSound));
        map.set(LocalNotificationsConstants.ENABLE_VIBRATION, notificationSlot.vibrationEnabled ?? false);
        map.set(LocalNotificationsConstants.VIBRATION_PATTERN, notificationSlot.vibrationValues ?? []);
        map.set(LocalNotificationsConstants.ENABLE_LIGHTS, notificationSlot.lightEnabled ?? false);
        if (notificationSlot.lightColor != undefined) {
          map.set(LocalNotificationsConstants.LED_COLOR, notificationSlot.lightColor);
        }
        map.set(LocalNotificationsConstants.LOCKSCREEN_VISIBILITY,
          notificationSlot.lockscreenVisibility ?? 0);
        map.set(LocalNotificationsConstants.BYPASS_DND, notificationSlot.bypassDnd ?? false);
        let storedSlotAction: NotificationSlotAction | undefined =
          this.notificationManager.getStoredSlotAction(slotType);
        if (storedSlotAction != undefined) {
          map.set(LocalNotificationsConstants.SLOT_ACTION, storedSlotAction);
        }
        slotDetailsList.push(map);
      }
      Log.d(TAG, 'getNotificationSlots-->data: ' + JSON.stringify(slotDetailsList));
      result.success(slotDetailsList);
    } catch (e) {
      Log.e(TAG, 'getNotificationSlots-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, readErrorMessage(e), null);
    }
  }

  private resolveSlotSoundSource(sound: string | undefined): number {
    if (sound == null || sound.length === 0) {
      return SoundSource.RawResource;
    }
    if (sound.includes('://') || sound.startsWith('/')) {
      return SoundSource.Uri;
    }
    return SoundSource.RawResource;
  }
}
