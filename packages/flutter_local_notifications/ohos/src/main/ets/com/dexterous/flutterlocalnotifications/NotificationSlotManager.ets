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

import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { Log } from '@ohos/flutter_ohos';
import NotificationSlotDetails from './models/NotificationSlotDetails';
import { NotificationSlotAction } from './models/NotificationSlotAction';
import { NSlot } from './utils/OhosTypeAliases';

const TAG: string = 'NotificationSlotManager';

/** Manages OHOS notification slot lifecycle and cached slot actions. */
export class NotificationSlotManager {
  /** OHOS NotificationSlot has no slotAction field; track values set via addNotificationSlot. */
  private slotActionByType: Map<number, NotificationSlotAction> = new Map();

  /** Clears cached notification slot actions when the engine detaches. */
  reset(): void {
    this.slotActionByType.clear();
  }

  /**
   * Returns the slot action previously stored for a slot type.
   *
   * @param slotType OHOS notification slot type value.
   * @returns Stored slot action or undefined when not set.
   */
  getStoredSlotAction(slotType: number): NotificationSlotAction | undefined {
    return this.slotActionByType.get(slotType);
  }

  /**
   * Creates or updates a notification slot from slot details.
   *
   * @param notificationSlotDetails Slot configuration from Dart.
   */
  async addNotificationSlot(notificationSlotDetails: NotificationSlotDetails): Promise<void> {
    try {
      await this.removeNotificationSlot(notificationSlotDetails.slotType);
    } catch (e) {
      Log.w(TAG, 'removeNotificationSlot-->slot may not exist, proceed to add: ' + JSON.stringify(e));
    }
    let notificationSlot: NSlot = this.buildNotificationSlot(notificationSlotDetails);
    Log.i(TAG, 'addNotificationSlot-->request: ' + JSON.stringify(notificationSlot));
    const slotType: number = notificationSlotDetails.slotType;
    await this.ensureNotificationKitSlot(slotType);
    await new Promise<void>((resolve, reject) => {
      reminderAgentManager.addNotificationSlot(notificationSlot, (err: BusinessError) => {
        if (err?.code) {
          Log.e(TAG, 'addNotificationSlot-->err code:' + err.code + ' message:' + err.message);
          reject(err);
        } else {
          Log.i(TAG, 'addNotificationSlot-->success');
          this.slotActionByType.set(slotType,
            notificationSlotDetails.slotAction ?? NotificationSlotAction.CreateIfNotExists);
          resolve();
        }
      });
    });
  }

  /**
   * Ensures a slot type exists in NotificationKit before applying custom slot settings.
   *
   * @param slotType OHOS notification slot type value.
   */
  private async ensureNotificationKitSlot(slotType: number): Promise<void> {
    await new Promise<void>((resolve, reject) => {
      notificationManager.addSlot(slotType, (err: BusinessError) => {
        if (err?.code) {
          Log.w(TAG, 'ensureNotificationKitSlot-->addSlot code:' + err.code + ' message:' + err.message);
          reject(err);
        } else {
          Log.i(TAG, 'ensureNotificationKitSlot-->addSlot success');
          resolve();
        }
      });
    }).catch(() => {
      // Slot may already exist after removeSlot or system defaults; proceed to update settings.
    });
  }

  private buildNotificationSlot(notificationSlotDetails: NotificationSlotDetails): NSlot {
    let notificationSlot: NSlot = {
      notificationType: notificationSlotDetails.slotType,
      desc: notificationSlotDetails.description ?? '',
      enabled: true
    };
    if (notificationSlotDetails.importance != undefined) {
      notificationSlot.level = notificationSlotDetails.importance;
    }
    if (notificationSlotDetails.showBadge != undefined) {
      notificationSlot.badgeFlag = notificationSlotDetails.showBadge;
    }
    if (notificationSlotDetails.bypassDnd != undefined) {
      notificationSlot.bypassDnd = notificationSlotDetails.bypassDnd;
    }
    if (notificationSlotDetails.lockscreenVisibility != undefined) {
      notificationSlot.lockscreenVisibility = notificationSlotDetails.lockscreenVisibility;
    }
    if (notificationSlotDetails.enableVibration != undefined) {
      notificationSlot.vibrationEnabled = notificationSlotDetails.enableVibration;
    }
    if (notificationSlotDetails.sound) {
      // TODO slot当前api12版本readonly状态，参数暂未处理对接
      notificationSlot.sound = notificationSlotDetails.sound;
    }
    if (notificationSlotDetails.enableLights != undefined) {
      notificationSlot.lightEnabled = notificationSlotDetails.enableLights;
    }
    if (notificationSlotDetails.ledColor != undefined) {
      notificationSlot.lightColor = notificationSlotDetails.ledColor;
    }
    if (notificationSlotDetails.vibrationPattern) {
      notificationSlot.vibrationValues = notificationSlotDetails.vibrationPattern;
    }
    return notificationSlot;
  }

  /**
   * Removes a notification slot by type.
   *
   * @param slotType OHOS notification slot type value.
   */
  async removeNotificationSlot(slotType: number): Promise<void> {
    Log.d(TAG, 'removeNotificationSlot-->slotType: ' + slotType);
    await new Promise<void>((resolve) => {
      notificationManager.removeSlot(slotType, (err: BusinessError) => {
        if (err?.code) {
          Log.w(TAG, 'removeNotificationSlot-->notificationManager code:' + err.code +
            ' message:' + err.message);
        } else {
          Log.i(TAG, 'removeNotificationSlot-->notificationManager success');
          this.slotActionByType.delete(slotType);
        }
        resolve();
      });
    });
    await new Promise<void>((resolve) => {
      reminderAgentManager.removeNotificationSlot(slotType, (err: BusinessError) => {
        if (err?.code) {
          Log.w(TAG, 'removeNotificationSlot-->reminderAgent code:' + err.code +
            ' message:' + err.message);
        } else {
          Log.i(TAG, 'removeNotificationSlot-->reminderAgent success');
        }
        resolve();
      });
    });
  }

  /**
   * Returns all notification slots registered for the application.
   *
   * @returns Array of notification slots.
   */
  async getAllNotificationSlots(): Promise<NSlot[]> {
    try {
      let slotList: NSlot[] = await notificationManager.getSlots();
      Log.i(TAG, 'getAllNotificationSlots-->success, data: ' + JSON.stringify(slotList));
      return slotList;
    } catch (err) {
      Log.e(TAG, 'getAllNotificationSlots-->err msg:' + JSON.stringify(err));
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  /**
   * Returns a notification slot for the given type.
   *
   * @param slotType OHOS notification slot type value.
   * @returns Matching slot or undefined when not found.
   */
  async getNotificationSlotByType(slotType: number): Promise<NSlot | undefined> {
    Log.d(TAG, 'getNotificationSlotByType-->slotType: ' + slotType);
    try {
      let notificationSlot: NSlot = await notificationManager.getSlot(slotType);
      Log.i(TAG, 'getNotificationSlotByType-->success, data: ' + JSON.stringify(notificationSlot));
      return notificationSlot;
    } catch (err) {
      Log.e(TAG, 'getNotificationSlotByType-->err msg:' + JSON.stringify(err));
      return undefined;
    }
  }

  /**
   * Determines whether a slot should be added or updated before publishing.
   *
   * @param slotType OHOS notification slot type value.
   * @param slotAction Desired slot action from Dart.
   * @returns true when the slot operation should proceed.
   */
  async canAddNotificationSlot(slotType: number,
    slotAction: NotificationSlotAction | undefined): Promise<boolean> {
    let notificationSlot: NSlot | undefined = await this.getNotificationSlotByType(slotType);
    return ((notificationSlot == undefined &&
      (slotAction == undefined ||
        slotAction == NotificationSlotAction.CreateIfNotExists)) ||
      (notificationSlot != undefined &&
        slotAction == NotificationSlotAction.Update));
  }

  /**
   * Ensures the notification slot exists when required by notification details.
   *
   * @param slotDetails Parsed slot configuration.
   */
  async ensureSlotForDetails(slotDetails: NotificationSlotDetails): Promise<void> {
    if (await this.canAddNotificationSlot(slotDetails.slotType, slotDetails.slotAction)) {
      await this.removeNotificationSlot(slotDetails.slotType);
      await this.addNotificationSlot(slotDetails);
    }
  }
}
