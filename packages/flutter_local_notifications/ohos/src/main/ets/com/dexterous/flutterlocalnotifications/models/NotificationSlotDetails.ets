/*
 * Copyright (c) 2024 Shenzhen Kaihong Digital Industry Development Co., Ltd.
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

import { MethodCall } from '@ohos/flutter_ohos';
import { LocalNotificationsConstants } from '../LocalNotificationsConstants';
import NotificationDetails from './NotificationDetails';
import { NotificationPlatformSpecificsParser } from './NotificationPlatformSpecificsParser';
import { NotificationSlotAction } from './NotificationSlotAction';
import { SoundSource } from './SoundSource';
import { notificationManager } from '@kit.NotificationKit';

export default class NotificationSlotDetails {
  slotType: number = 0;
  description?: string;
  showBadge?: boolean;
  importance?: number;
  playSound?: boolean;
  sound?: string;
  soundSource?: SoundSource;
  enableVibration?: boolean;
  vibrationPattern?: Array<number>;
  slotAction?: NotificationSlotAction;
  enableLights?: boolean;
  ledColor?: number;
  lockscreenVisibility?: number;
  bypassDnd?: boolean;

  private static readOptionalString(call: MethodCall, key: string): string | undefined {
    let value: Object | null | undefined = call.argument(key);
    if (value === undefined || value === null) {
      return undefined;
    }
    return typeof value === 'string' ? value : undefined;
  }

  private static readOptionalBoolean(call: MethodCall, key: string): boolean | undefined {
    let value: Object | null | undefined = call.argument(key);
    if (value === undefined || value === null) {
      return undefined;
    }
    return typeof value === 'boolean' ? value : undefined;
  }

  private static readOptionalNumber(call: MethodCall, key: string): number | undefined {
    let value: Object | null | undefined = call.argument(key);
    if (value === undefined || value === null) {
      return undefined;
    }
    return typeof value === 'number' ? value : undefined;
  }

  private static readOptionalNumberArray(call: MethodCall, key: string): Array<number> | undefined {
    let value: Object | null | undefined = call.argument(key);
    if (value === undefined || value === null || !Array.isArray(value)) {
      return undefined;
    }
    return value as Array<number>;
  }

  /**
   * Parses a MethodChannel map into [NotificationSlotDetails].
   *
   * @param call Incoming MethodChannel call from Dart.
   * @returns Parsed notification slot details.
   */
  public static from(call: MethodCall): NotificationSlotDetails {
    let notificationSlotDetails: NotificationSlotDetails = new NotificationSlotDetails();
    notificationSlotDetails.slotType =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.SLOT_TYPE) ?? 0;
    notificationSlotDetails.description =
      NotificationSlotDetails.readOptionalString(call, LocalNotificationsConstants.DESCRIPTION);
    notificationSlotDetails.showBadge =
      NotificationSlotDetails.readOptionalBoolean(call, LocalNotificationsConstants.SHOW_BADGE);
    notificationSlotDetails.importance =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.IMPORTANCE);
    notificationSlotDetails.playSound =
      NotificationSlotDetails.readOptionalBoolean(call, LocalNotificationsConstants.PLAY_SOUND);
    notificationSlotDetails.sound =
      NotificationSlotDetails.readOptionalString(call, LocalNotificationsConstants.SOUND);
    let soundSourceRaw: number | undefined =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.SOUND_SOURCE);
    notificationSlotDetails.soundSource = NotificationPlatformSpecificsParser.parseSoundSource(soundSourceRaw);
    notificationSlotDetails.enableVibration =
      NotificationSlotDetails.readOptionalBoolean(call, LocalNotificationsConstants.ENABLE_VIBRATION);
    notificationSlotDetails.vibrationPattern =
      NotificationSlotDetails.readOptionalNumberArray(call, LocalNotificationsConstants.VIBRATION_PATTERN);
    let slotActionRaw: number | undefined =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.SLOT_ACTION);
    notificationSlotDetails.slotAction = NotificationDetails.parseSlotAction(slotActionRaw);
    notificationSlotDetails.enableLights =
      NotificationSlotDetails.readOptionalBoolean(call, LocalNotificationsConstants.ENABLE_LIGHTS);
    let alpha: number | undefined =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.LED_COLOR_ALPHA);
    let red: number | undefined =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.LED_COLOR_RED);
    let green: number | undefined =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.LED_COLOR_GREEN);
    let blue: number | undefined =
      NotificationSlotDetails.readOptionalNumber(call, LocalNotificationsConstants.LED_COLOR_BLUE);
    if (alpha !== undefined && red !== undefined && green !== undefined && blue !== undefined) {
      notificationSlotDetails.ledColor = (alpha << 24) | (red << 16) | (green << 8) | blue;
    }
    notificationSlotDetails.lockscreenVisibility = NotificationDetails.parseLockscreenVisibility(
      call.argument(LocalNotificationsConstants.LOCKSCREEN_VISIBILITY));
    notificationSlotDetails.bypassDnd =
      NotificationSlotDetails.readOptionalBoolean(call, LocalNotificationsConstants.BYPASS_DND);
    return notificationSlotDetails;
  }

  /**
   * Builds slot details from parsed [NotificationDetails].
   *
   * @param notificationDetails Parsed notification payload.
   * @returns Slot details derived from notification specifics.
   */
  public static fromNotificationDetails(notificationDetails: NotificationDetails): NotificationSlotDetails {
    let notificationSlotDetails: NotificationSlotDetails = new NotificationSlotDetails();
    notificationSlotDetails.slotType = notificationDetails.slotType ?? notificationManager.SlotType.UNKNOWN_TYPE;
    notificationSlotDetails.description = notificationDetails.slotDesc;
    notificationSlotDetails.showBadge = notificationDetails.slotShowBadge;
    notificationSlotDetails.importance = notificationDetails.importance;
    notificationSlotDetails.playSound = notificationDetails.playSound;
    notificationSlotDetails.sound = notificationDetails.sound;
    notificationSlotDetails.soundSource = notificationDetails.soundSource;
    notificationSlotDetails.enableVibration = notificationDetails.enableVibration;
    notificationSlotDetails.vibrationPattern = notificationDetails.vibrationPattern;
    notificationSlotDetails.slotAction = notificationDetails.slotAction;
    notificationSlotDetails.enableLights = notificationDetails.enableLights;
    notificationSlotDetails.ledColor = notificationDetails.ledColor;
    notificationSlotDetails.lockscreenVisibility = notificationDetails.lockscreenVisibility;
    notificationSlotDetails.bypassDnd = notificationDetails.bypassDnd;
    return notificationSlotDetails;
  }
}
