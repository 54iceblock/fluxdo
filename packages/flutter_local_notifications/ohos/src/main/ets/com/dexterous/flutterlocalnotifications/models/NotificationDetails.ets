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

import { MethodCall } from '@ohos/flutter_ohos';
import { LocalNotificationsConstants } from '../LocalNotificationsConstants';
import { DateTimeComponents } from './DateTimeComponents';
import { NotificationAction } from './NotificationAction';
import { NotificationPlatformSpecificsParser } from './NotificationPlatformSpecificsParser';
import { NotificationSlotAction } from './NotificationSlotAction';
import { RepeatInterval } from './RepeatInterval';
import { SoundSource } from './SoundSource';
import { DefaultStyleInformation } from './styles/DefaultStyleInformation';
import { PictureSource } from './styles/PictureSource';

export default class NotificationDetails {
  slotType?: number;
  slotDesc?: string;
  slotAction?: NotificationSlotAction;
  slotShowBadge?: boolean;
  importance?: number;
  lockscreenVisibility?: number;
  bypassDnd?: boolean;
  id?: number;
  title: string = "";
  body: string = "";
  subText?: string;
  payload?: string;
  repeatInterval?: RepeatInterval;
  repeatIntervalMilliseconds?: number;
  timeZoneName?: string;
  scheduledDateTime?: string;
  matchDateTimeComponents?: DateTimeComponents;
  autoCancel?: boolean;
  ongoing?: boolean;
  onlyAlertOnce?: boolean;
  style?: number;
  styleInformation?: DefaultStyleInformation;
  actions?: Array<NotificationAction>;
  tag?: string;
  groupKey?: string;
  showProgress?: boolean;
  maxProgress?: number;
  progress?: number;
  badgeNumber?: number;
  playSound?: boolean;
  sound?: string;
  /** OHOS API 12: NotificationSlot.sound is readonly after creation; slot sound may not apply. */
  soundSource?: SoundSource;
  enableVibration?: boolean;
  vibrationPattern?: Array<number>;
  enableLights?: boolean;
  ledColor?: number;
  colorized?: boolean;
  color?: number;

  timeoutAfter?: number;
  showWhen?: boolean;
  when?: number;
  usesChronometer?: boolean;
  chronometerCountDown?: boolean;
  icon?: string;
  isFloatingIcon?: boolean;

  largeIcon?: string | Uint8Array;
  largeIconSource?: PictureSource;

  public usesTimerRepeat(): boolean {
    if (this.repeatIntervalMilliseconds != undefined && this.repeatIntervalMilliseconds > 0) {
      return true;
    }
    return this.repeatInterval === RepeatInterval.EveryMinute ||
      this.repeatInterval === RepeatInterval.Hourly;
  }

  /**
   * Parses a MethodChannel payload into a [NotificationDetails] instance.
   *
   * @param call Incoming MethodChannel call from Dart.
   * @returns Parsed notification details model.
   */
  public static from(call: MethodCall): NotificationDetails {
    try {
      let notificationDetails: NotificationDetails = new NotificationDetails();
      notificationDetails.title = call.argument(LocalNotificationsConstants.TITLE) ?? "";
      notificationDetails.body = call.argument(LocalNotificationsConstants.BODY) ?? "";
      let rawId: string | number | undefined = call.argument(LocalNotificationsConstants.ID);
      if (rawId != null && rawId !== '') {
        let parsedId: number = Number(rawId);
        if (Number.isNaN(parsedId)) {
          throw new Error("id must be a number");
        }
        notificationDetails.id = parsedId;
      }
      let rawPayload: Object | undefined = call.argument(LocalNotificationsConstants.PAYLOAD);
      if (rawPayload != null) {
        notificationDetails.payload = String(rawPayload);
      }
      if (call.hasArgument(LocalNotificationsConstants.REPEAT_INTERVAL)) {
        notificationDetails.repeatInterval = NotificationDetails.parseRepeatInterval(
          call.argument(LocalNotificationsConstants.REPEAT_INTERVAL) as number);
      }
      if (call.hasArgument(LocalNotificationsConstants.TIMEZONE_NAME)) {
        notificationDetails.timeZoneName =
          call.argument(LocalNotificationsConstants.TIMEZONE_NAME) as (string | undefined);
      }
      if (call.hasArgument(LocalNotificationsConstants.SCHEDULED_DATETIME)) {
        notificationDetails.scheduledDateTime =
          call.argument(LocalNotificationsConstants.SCHEDULED_DATETIME) as (string | undefined);
      }
      if (call.hasArgument(LocalNotificationsConstants.MATCH_DATETIME_COMPONENTS)) {
        notificationDetails.matchDateTimeComponents = NotificationDetails.parseDateTimeComponents(
          call.argument(LocalNotificationsConstants.MATCH_DATETIME_COMPONENTS) as number);
      }
      if (call.hasArgument(LocalNotificationsConstants.REPEAT_INTERVAL_MILLISECONDS)) {
        notificationDetails.repeatIntervalMilliseconds =
          call.argument(LocalNotificationsConstants.REPEAT_INTERVAL_MILLISECONDS) as number;
      }
      NotificationPlatformSpecificsParser.readPlatformSpecifics(call, notificationDetails);
      return notificationDetails;
    } catch (e) {
      throw new Error(`NotificationDetails.from failed: ${JSON.stringify(e)}`);
    }
  }

  private static parseRepeatInterval(raw: number | undefined): RepeatInterval | undefined {
    if (raw == undefined) {
      return undefined;
    }
    switch (raw) {
      case 0:
        return RepeatInterval.EveryMinute;
      case 1:
        return RepeatInterval.Hourly;
      case 2:
        return RepeatInterval.Daily;
      case 3:
        return RepeatInterval.Weekly;
      default:
        return undefined;
    }
  }

  private static parseDateTimeComponents(raw: number | undefined): DateTimeComponents | undefined {
    if (raw == undefined) {
      return undefined;
    }
    switch (raw) {
      case 0:
        return DateTimeComponents.Time;
      case 1:
        return DateTimeComponents.DayOfWeekAndTime;
      case 2:
        return DateTimeComponents.DayOfMonthAndTime;
      case 3:
        return DateTimeComponents.DateAndTime;
      default:
        return undefined;
    }
  }

  /**
   * Parses slot action from Dart enum index.
   *
   * @param raw Raw value from MethodChannel.
   * @returns Parsed slot action or undefined when invalid.
   */
  public static parseSlotAction(raw: number | undefined): NotificationSlotAction | undefined {
    if (raw == undefined) {
      return undefined;
    }
    if (raw === NotificationSlotAction.CreateIfNotExists || raw === NotificationSlotAction.Update) {
      return raw as NotificationSlotAction;
    }
    return undefined;
  }

  /**
   * Parses lockscreen visibility from Dart bool or OHOS visibility level (0�?).
   *
   * @param raw Raw value from MethodChannel (boolean or number).
   * @returns OHOS lockscreen visibility level, or undefined when invalid.
   */
  public static parseLockscreenVisibility(raw: Object | undefined): number | undefined {
    if (raw == undefined) {
      return undefined;
    }
    if (typeof raw === 'boolean') {
      return raw ? 2 : 3;
    }
    if (typeof raw === 'number') {
      if (raw >= 0 && raw <= 3) {
        return raw;
      }
      return undefined;
    }
    let parsed: number = Number(raw);
    if (!Number.isNaN(parsed) && parsed >= 0 && parsed <= 3) {
      return parsed;
    }
    return undefined;
  }
}
