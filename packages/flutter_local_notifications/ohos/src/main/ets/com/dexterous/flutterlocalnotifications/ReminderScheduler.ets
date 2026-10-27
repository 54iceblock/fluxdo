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

import { bundleManager } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { Log } from '@ohos/flutter_ohos';
import { LocalNotificationsConstants } from './LocalNotificationsConstants';
import { DateTimeComponents } from './models/DateTimeComponents';
import NotificationDetails from './models/NotificationDetails';
import NotificationSlotDetails from './models/NotificationSlotDetails';
import { RepeatInterval } from './models/RepeatInterval';
import { NotificationContentFactory } from './NotificationContentFactory';
import { NotificationSlotManager } from './NotificationSlotManager';
import { ReminderCalendar, ReminderInfo, ReminderRequest, ReminderTimer } from './utils/OhosTypeAliases';

const TAG: string = 'ReminderScheduler';
const TIMER_REPEAT_OCCURRENCES: number = 30;
const REMINDER_LIMIT_ERROR_CODE: number = 1700002;

/** WantAgent payload passed to reminder-agent APIs. */
interface ReminderWantAgentInfo {
  pkgName?: string;
  abilityName: string;
  parameters: Record<string, Object>;
}

/** Schedules and cancels OHOS reminder-agent notifications. */
export class ReminderScheduler {
  private readonly slotManager: NotificationSlotManager;
  private readonly contentFactory: NotificationContentFactory;

  constructor(slotManager: NotificationSlotManager, contentFactory: NotificationContentFactory) {
    this.slotManager = slotManager;
    this.contentFactory = contentFactory;
  }

  /**
   * Publishes a calendar-based repeating reminder derived from repeatInterval.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async publishPeriodicReminder(notificationDetails: NotificationDetails): Promise<void> {
    console.info(`[FLN-REPEAT][ENTRY][PERIODIC] id=${notificationDetails.id} ` +
      `usesTimerRepeat=${notificationDetails.usesTimerRepeat()} ` +
      `repeatInterval=${notificationDetails.repeatInterval} ` +
      `scheduledDateTime=${notificationDetails.scheduledDateTime} ` +
      `matchDateTimeComponents=${notificationDetails.matchDateTimeComponents}`);
    if (notificationDetails.usesTimerRepeat()) {
      await this.publishTimerReminder(notificationDetails);
      return;
    }
    if (!notificationDetails.scheduledDateTime) {
      notificationDetails.scheduledDateTime = new Date().toISOString();
    }
    if (notificationDetails.repeatInterval === RepeatInterval.Daily) {
      notificationDetails.matchDateTimeComponents = DateTimeComponents.Time;
    } else if (notificationDetails.repeatInterval === RepeatInterval.Weekly) {
      notificationDetails.matchDateTimeComponents = DateTimeComponents.DayOfWeekAndTime;
    }
    let intervalMs: number = this.calculateRepeatIntervalMilliseconds(notificationDetails);
    console.info(`[FLN-REPEAT] publishPeriodicReminder id=${notificationDetails.id} ` +
      `repeatInterval=${notificationDetails.repeatInterval} intervalMs=${intervalMs} ` +
      `scheduledDateTime=${notificationDetails.scheduledDateTime} ` +
      `matchDateTimeComponents=${notificationDetails.matchDateTimeComponents}`);
    await this.publishCalendarReminder(notificationDetails);
  }

  /**
   * Publishes a timer-based reminder (one-shot or repeating interval).
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async publishTimerReminder(notificationDetails: NotificationDetails): Promise<void> {
    let slotDetails: NotificationSlotDetails =
      NotificationSlotDetails.fromNotificationDetails(notificationDetails);
    await this.slotManager.ensureSlotForDetails(slotDetails);
    let triggerTimeInSeconds: number = await this.resolveTriggerTimeInSeconds(notificationDetails);
    if (triggerTimeInSeconds <= 0) {
      throw new Error('scheduled time must be in the future');
    }
    if (notificationDetails.usesTimerRepeat()) {
      await this.cancelRemindersMatchingNotificationId(notificationDetails.id);
      let published: number = 0;
      // When scheduledDateTime is present, align the first occurrence to
      // scheduledDateTime (not to now + interval) so a 7-day interval starting
      // at 2026-09-28 10:00 fires at 2026-09-28 10:00, then weekly thereafter.
      let firstDelaySeconds: number = triggerTimeInSeconds;
      let intervalSeconds: number = triggerTimeInSeconds;
      if (notificationDetails.scheduledDateTime) {
        let date: Date = new Date(notificationDetails.scheduledDateTime);
        let intervalMs: number = this.calculateRepeatIntervalMilliseconds(notificationDetails);
        if (!isNaN(date.getTime()) && intervalMs > 0) {
          let currentTime: number = await systemDateTime.getCurrentTime();
          firstDelaySeconds = Math.max(1, Math.floor((date.getTime() - currentTime) / 1000));
          intervalSeconds = Math.floor(intervalMs / 1000);
        }
      }
      for (let occurrence = 1; occurrence <= TIMER_REPEAT_OCCURRENCES; occurrence++) {
        let delaySeconds: number = firstDelaySeconds + (occurrence - 1) * intervalSeconds;
        if (delaySeconds <= 0) {
          // Skip already-elapsed occurrences and continue.
          console.info(`[FLN-REPEAT] publishTimerReminder chain skip id=${notificationDetails.id} ` +
            `occurrence=${occurrence}/${TIMER_REPEAT_OCCURRENCES} elapsedDelay=${delaySeconds}`);
          continue;
        }
        let timer: ReminderTimer =
          await this.buildTimerReminder(notificationDetails, delaySeconds, occurrence);
        console.info(`[FLN-REPEAT] publishTimerReminder chain id=${notificationDetails.id} ` +
          `occurrence=${occurrence}/${TIMER_REPEAT_OCCURRENCES} triggerTimeInSeconds=${delaySeconds} ` +
          `notificationId=${timer.notificationId}`);
        try {
          await this.publishReminderRequest(timer);
          published++;
        } catch (err) {
          let code: number = (err as BusinessError)?.code ?? -1;
          console.error(`[FLN-REPEAT] publishTimerReminder chain stop occurrence=${occurrence} code=${code}`);
          if (code === REMINDER_LIMIT_ERROR_CODE && published > 0) {
            break;
          }
          throw err instanceof Error ? err : new Error(String(err));
        }
      }
      console.info(`[FLN-REPEAT] publishTimerReminder chain done published=${published}`);
      await this.dumpValidReminders(notificationDetails.id);
      return;
    }
    let timer: ReminderTimer = await this.buildTimerReminder(notificationDetails, triggerTimeInSeconds);
    console.info(`[FLN-REPEAT] publishTimerReminder id=${notificationDetails.id} ` +
      `triggerTimeInSeconds=${triggerTimeInSeconds} request=${JSON.stringify(timer)}`);
    console.info('publishTimerReminder-->request: ' + JSON.stringify(timer));
    await this.publishReminderRequest(timer);
    await this.dumpValidReminders(notificationDetails.id);
  }

  /**
   * Publishes a calendar reminder at a specific date/time.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async publishCalendarReminder(notificationDetails: NotificationDetails): Promise<void> {
    console.info(`[FLN-REPEAT][ENTRY][CALENDAR] id=${notificationDetails.id} ` +
      `scheduledDateTime=${notificationDetails.scheduledDateTime} ` +
      `matchDateTimeComponents=${notificationDetails.matchDateTimeComponents} ` +
      `repeatInterval=${notificationDetails.repeatInterval} ` +
      `usesTimerRepeat=${notificationDetails.usesTimerRepeat()}`);
    // Workaround: OpenHarmony ReminderRequestCalendar's daysOfWeek/repeatDays
    // repeat semantics are unreliable for weekly/monthly/yearly recurring
    // notifications (logs show `tarDuration is less than 0` and reminders
    // silently fail to fire). For matchDateTimeComponents that imply a weekly,
    // monthly, or yearly recurrence, route to publishTimerReminder with a
    // 7-day/30-day/365-day interval chain so the system actually triggers
    // the reminders. The time/zone semantics are preserved by chaining
    // one-shot timer reminders.
    const matchDateTimeComponents: DateTimeComponents | undefined =
      notificationDetails.matchDateTimeComponents;
    if (matchDateTimeComponents === DateTimeComponents.DayOfWeekAndTime as DateTimeComponents ||
      matchDateTimeComponents === DateTimeComponents.DayOfMonthAndTime as DateTimeComponents ||
      matchDateTimeComponents === DateTimeComponents.DateAndTime as DateTimeComponents) {
      let intervalMs: number = this.calculateRepeatIntervalMilliseconds(notificationDetails);
      if (intervalMs <= 0) {
        if (matchDateTimeComponents === DateTimeComponents.DayOfWeekAndTime as DateTimeComponents) {
          intervalMs = 7 * 24 * 60 * 60 * 1000;
        } else if (matchDateTimeComponents === DateTimeComponents.DayOfMonthAndTime as DateTimeComponents) {
          intervalMs = 30 * 24 * 60 * 60 * 1000;
        } else {
          intervalMs = 365 * 24 * 60 * 60 * 1000;
        }
      }
      console.info(`[FLN-REPEAT] publishCalendarReminder fallback to timer chain ` +
        `match=${matchDateTimeComponents} intervalMs=${intervalMs}`);
      notificationDetails.repeatIntervalMilliseconds = intervalMs;
      await this.publishTimerReminder(notificationDetails);
      return;
    }
    let slotDetails: NotificationSlotDetails =
      NotificationSlotDetails.fromNotificationDetails(notificationDetails);
    await this.slotManager.ensureSlotForDetails(slotDetails);
    let date: Date = new Date(notificationDetails.scheduledDateTime ?? '');
    console.info(`[FLN-REPEAT][ENTRY][CALENDAR] date=${date.toISOString()} ` +
      `localDate=${date.toString()} getTime=${date.getTime()} ` +
      `now=${Date.now()} diffMs=${date.getTime() - Date.now()}`);
    if (isNaN(date.getTime())) {
      throw new Error('invalid scheduledDateTime format');
    }
    let calendar: ReminderCalendar = await this.buildCalendarReminder(notificationDetails, date);
    this.applyRepeatComponents(calendar, notificationDetails, date);
    console.info(`[FLN-REPEAT] publishCalendarReminder id=${notificationDetails.id} ` +
      `date=${date.toISOString()} local=${date.toString()} ` +
      `dateTime=${JSON.stringify(calendar.dateTime)} ` +
      `repeatMonths=${JSON.stringify(calendar.repeatMonths)} ` +
      `repeatDays=${JSON.stringify(calendar.repeatDays)} ` +
      `daysOfWeek=${JSON.stringify(calendar.daysOfWeek)}`);
    console.info('publishCalendarReminder-->request: ' + JSON.stringify(calendar));
    await this.publishReminderRequest(calendar);
    await this.dumpValidReminders(notificationDetails.id);
  }

  /**
   * Cancels a scheduled reminder by reminder id.
   *
   * @param notificationId Reminder id returned by the reminder agent.
   */
  async cancelReminderById(notificationId: number): Promise<void> {
    try {
      Log.d(TAG, 'cancelReminderById-->notificationId: ' + notificationId);
      await reminderAgentManager.cancelReminder(notificationId);
      Log.i(TAG, 'cancelReminderById-->success');
    } catch (err) {
      Log.e(TAG, 'cancelReminderById-->err msg: ' + JSON.stringify(err));
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  /** Cancels all scheduled reminders. */
  async cancelAllReminders(): Promise<void> {
    try {
      await reminderAgentManager.cancelAllReminders();
      Log.i(TAG, 'cancelAllReminders-->success');
    } catch (err) {
      Log.e(TAG, 'cancelAllReminders-->err msg: ' + JSON.stringify(err));
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  /**
   * Returns all valid scheduled reminder requests.
   *
   * @returns Array of reminder requests currently registered with the system.
   */
  async getReminderList(): Promise<ReminderRequest[]> {
    try {
      let reminders: ReminderRequest[] = await reminderAgentManager.getValidReminders();
      Log.i(TAG, 'getReminderList-->success, data: ' + JSON.stringify(reminders));
      return reminders;
    } catch (err) {
      Log.e(TAG, 'getReminderList-->err msg:' + JSON.stringify(err));
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  private async resolveTriggerTimeInSeconds(notificationDetails: NotificationDetails): Promise<number> {
    if (notificationDetails.repeatInterval != undefined ||
      notificationDetails.repeatIntervalMilliseconds != undefined) {
      let intervalMs: number = this.calculateRepeatIntervalMilliseconds(notificationDetails);
      return intervalMs / 1000;
    }
    if (notificationDetails.scheduledDateTime) {
      let date: Date = new Date(notificationDetails.scheduledDateTime);
      let currentTime: number = await systemDateTime.getCurrentTime();
      return (date.getTime() - currentTime) / 1000;
    }
    throw new Error('publishTimerReminder: scheduled time or repeat interval is required');
  }

  private buildReminderParameters(notificationDetails: NotificationDetails): Record<string, Object> {
    let parameters: Record<string, Object> = {};
    if (notificationDetails.id != undefined) {
      parameters[LocalNotificationsConstants.NOTIFICATION_ID] = notificationDetails.id;
    }
    parameters[LocalNotificationsConstants.PAYLOAD] = notificationDetails.payload ?? '';
    parameters[LocalNotificationsConstants.ACTION] = LocalNotificationsConstants.ACTION_SELECTION_NOTIFICATION;
    return parameters;
  }

  private buildWantAgent(parameters: Record<string, Object>): reminderAgentManager.WantAgent {
    let wantAgentInfo: ReminderWantAgentInfo = {
      pkgName: bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)?.name,
      abilityName: LocalNotificationsConstants.ABILITY_NAME,
      parameters: parameters
    };
    return wantAgentInfo as reminderAgentManager.WantAgent;
  }

  private async buildTimerReminder(notificationDetails: NotificationDetails,
    triggerTimeInSeconds: number, occurrence?: number): Promise<ReminderTimer> {
    let parameters: Record<string, Object> = this.buildReminderParameters(notificationDetails);
    let timer: ReminderTimer = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
      wantAgent: this.buildWantAgent(parameters),
      title: this.contentFactory.formatReminderField(notificationDetails, 'title'),
      content: this.contentFactory.formatReminderField(notificationDetails, 'body'),
      triggerTimeInSeconds: triggerTimeInSeconds,
    };
    await this.applyCommonReminderFields(timer, notificationDetails);
    if (occurrence != undefined) {
      timer.notificationId = this.occurrenceNotificationId(notificationDetails.id, occurrence);
    }
    return timer;
  }

  private async buildCalendarReminder(notificationDetails: NotificationDetails,
    date: Date): Promise<ReminderCalendar> {
    let parameters: Record<string, Object> = this.buildReminderParameters(notificationDetails);
    let month: number = date.getMonth() + 1;
    let calendar: ReminderCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      wantAgent: this.buildWantAgent(parameters),
      title: this.contentFactory.formatReminderField(notificationDetails, 'title'),
      content: this.contentFactory.formatReminderField(notificationDetails, 'body'),
      dateTime: {
        year: date.getFullYear(),
        month: month,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
        second: date.getSeconds(),
      },
    };
    await this.applyCommonReminderFields(calendar, notificationDetails);
    return calendar;
  }

  private async applyCommonReminderFields(
    reminder: ReminderTimer | ReminderCalendar,
    notificationDetails: NotificationDetails): Promise<void> {
    if (notificationDetails.id != undefined) {
      reminder.notificationId = notificationDetails.id;
    }
    if (notificationDetails.groupKey) {
      reminder.groupId = notificationDetails.groupKey;
    }
    if (notificationDetails.slotType != undefined) {
      reminder.slotType = notificationDetails.slotType;
    }
    reminder.tapDismissed = false;
    if (notificationDetails.autoCancel === true) {
      reminder.tapDismissed = true;
    }
    if (notificationDetails.timeoutAfter) {
      reminder.autoDeletedTime =
        await systemDateTime.getCurrentTime(false) + notificationDetails.timeoutAfter;
    }
    // Explicitly reset snooze behaviour to default (no auto-snooze).
    // OHOS `ReminderRequest` defaults `snoozeTimes` to a non-zero value which
    // causes the system to auto-snooze after the first trigger; this prevents
    // the user from seeing the notification and emits "tarDuration is less
    // than 0" in the reminder log. Setting it explicitly to 0 disables it.
    reminder.snoozeTimes = 0;
  }

  private applyRepeatComponents(calendar: ReminderCalendar, notificationDetails: NotificationDetails,
    date: Date): void {
    let matchDateTimeComponents: DateTimeComponents | undefined =
      notificationDetails.matchDateTimeComponents;
    if (matchDateTimeComponents == undefined) {
      return;
    }
    // Day-of-week index from JS Date.getDay() (0=Sunday..6=Saturday) maps to the
    // OpenHarmony ReminderRequestCalendar.daysOfWeek range (1..7, 1=Sunday..7=Saturday).
    const dayOfWeekHarmony: number = date.getDay() === 0 ? 7 : date.getDay();
    const monthHarmony: number = date.getMonth() + 1;
    const dateHarmony: number = date.getDate();
    const yearHarmony: number = date.getFullYear();

    // Defaults: every month, every day-of-month, every day-of-week. Each branch
    // narrows one of these dimensions to match the requested DateTimeComponents.
    // Note: OpenHarmony ReminderRequestCalendar.repeatMonths/repeatDays/daysOfWeek
    // are OR-combined, so leaving the other dimensions as full ranges (e.g. all
    // months / all days of month) would cause unwanted firings. Each branch
    // therefore clears the dimensions that are NOT part of the requested match.
    calendar.repeatMonths = this.range(1, 12);
    calendar.repeatDays = this.range(1, 31);
    calendar.daysOfWeek = this.range(1, 7);

    switch (matchDateTimeComponents) {
      case DateTimeComponents.Time as DateTimeComponents:
        // Daily at the same HH:mm: every day-of-month, every day-of-week, every
        // month satisfies the time match alone. Clear the other dimensions to
        // prevent them from independently triggering.
        calendar.repeatMonths = [];
        calendar.repeatDays = [];
        calendar.daysOfWeek = [];
        break;
      case DateTimeComponents.DayOfWeekAndTime as DateTimeComponents:
        // Weekly on the same day-of-week at the same HH:mm: only that single
        // weekday. Clear the other dimensions so OR-combine does not match
        // every day.
        calendar.repeatMonths = [];
        calendar.repeatDays = [];
        calendar.daysOfWeek = [dayOfWeekHarmony];
        break;
      case DateTimeComponents.DayOfMonthAndTime as DateTimeComponents:
        // Monthly on the same day-of-month at the same HH:mm: all months, all
        // weekdays, but only the matching day-of-month. Note: when the date
        // does not exist in a month (e.g. 31st of Feb) the reminder simply
        // does not fire that month, matching the platform behaviour.
        calendar.repeatMonths = [];
        calendar.repeatDays = [dateHarmony];
        calendar.daysOfWeek = [];
        break;
      case DateTimeComponents.DateAndTime as DateTimeComponents:
        // Yearly on the same calendar date (month + day) at the same HH:mm.
        calendar.repeatMonths = [monthHarmony];
        calendar.repeatDays = [dateHarmony];
        calendar.daysOfWeek = [];
        break;
      default:
        break;
    }

    // Stamp the first-occurrence calendar info so OHOS fires the very first
    // notification at the scheduledDate even when the trigger list is narrowed.
    // `dateTime.year = 0` means "every year" for OHOS; for the year-bound
    // `DateAndTime` schedule we deliberately set the concrete year so the first
    // reminder lands on the requested date and only repeats on subsequent years.
    const firstDate: reminderAgentManager.LocalDateTime =
      this.toCalendarDateTime(notificationDetails.scheduledDateTime);
    if (matchDateTimeComponents === DateTimeComponents.DateAndTime as DateTimeComponents) {
      firstDate.year = yearHarmony;
    } else {
      firstDate.year = 0;
    }
    calendar.dateTime = firstDate;
    console.info(`[FLN-REPEAT] applyRepeatComponents match=${matchDateTimeComponents} ` +
      `months=${JSON.stringify(calendar.repeatMonths)} ` +
      `days=${JSON.stringify(calendar.repeatDays)} ` +
      `daysOfWeek=${JSON.stringify(calendar.daysOfWeek)} ` +
      `firstDate=${JSON.stringify(calendar.dateTime)}`);
  }

  private range(start: number, end: number): number[] {
    const out: number[] = [];
    for (let i = start; i <= end; i++) {
      out.push(i);
    }
    return out;
  }

  private toCalendarDateTime(scheduledDateTime: string | undefined): reminderAgentManager.LocalDateTime {
    const fallback: reminderAgentManager.LocalDateTime = {
      year: 0,
      month: 1,
      day: 1,
      hour: 10,
      minute: 0,
    };
    if (!scheduledDateTime) {
      return fallback;
    }
    const d: Date = new Date(scheduledDateTime);
    if (isNaN(d.getTime())) {
      return fallback;
    }
    return {
      year: d.getFullYear(),
      month: d.getMonth() + 1,
      day: d.getDate(),
      hour: d.getHours(),
      minute: d.getMinutes(),
    };
  }

  isTimerChainNotificationId(baseId: number, notificationId: number): boolean {
    let prefix: number = this.occurrenceNotificationId(baseId, 0);
    return notificationId > prefix && notificationId <= prefix + TIMER_REPEAT_OCCURRENCES;
  }

  timerChainNotificationIds(baseId: number): number[] {
    let ids: number[] = [];
    for (let occurrence = 1; occurrence <= TIMER_REPEAT_OCCURRENCES; occurrence++) {
      ids.push(this.occurrenceNotificationId(baseId, occurrence));
    }
    return ids;
  }

  private occurrenceNotificationId(baseId: number | undefined, occurrence: number): number {
    let base: number = baseId ?? 0;
    return 0x61000000 + ((base & 0xFFFF) << 8) + occurrence;
  }

  private async cancelRemindersMatchingNotificationId(notificationId?: number): Promise<void> {
    if (notificationId == undefined) {
      return;
    }
    try {
      let reminderList: ReminderInfo[] = await reminderAgentManager.getAllValidReminders();
      for (let index = 0; index < reminderList.length; index++) {
        let reminderInfo: ReminderInfo = reminderList[index];
        let paramId: string | number | undefined =
          reminderInfo?.reminderReq?.wantAgent?.parameters?.[LocalNotificationsConstants.NOTIFICATION_ID] as
            (string | number | undefined);
        if (Number(paramId) === notificationId) {
          await this.cancelReminderById(reminderInfo.reminderId);
        }
      }
    } catch (err) {
      Log.e(TAG, `[FLN-REPEAT] cancelRemindersMatchingNotificationId err=${JSON.stringify(err)}`);
    }
  }

  private calculateRepeatIntervalMilliseconds(notificationDetails: NotificationDetails): number {
    if (notificationDetails.repeatIntervalMilliseconds != undefined &&
      notificationDetails.repeatIntervalMilliseconds > 0) {
      return notificationDetails.repeatIntervalMilliseconds;
    }
    let intervalMs: number = 0;
    switch (notificationDetails.repeatInterval) {
      case RepeatInterval.EveryMinute:
        intervalMs = 60000;
        break;
      case RepeatInterval.Hourly:
        intervalMs = 60000 * 60;
        break;
      case RepeatInterval.Daily:
        intervalMs = 60000 * 60 * 24;
        break;
      case RepeatInterval.Weekly:
        intervalMs = 60000 * 60 * 24 * 7;
        break;
      default:
        break;
    }
    return intervalMs;
  }

  private publishReminderRequest(reminderRequest: ReminderRequest): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      console.info(`[FLN-REPEAT][REQUEST] type=${reminderRequest.reminderType} ` +
        `notificationId=${reminderRequest.notificationId} ` +
        `req=${JSON.stringify(reminderRequest)}`);
      reminderAgentManager.publishReminder(reminderRequest, (err: BusinessError, reminderId: number) => {
        if (err?.code) {
          console.error(`[FLN-REPEAT] publishReminder failed code=${err.code} msg=${err.message} ` +
            `type=${reminderRequest.reminderType} req=${JSON.stringify(reminderRequest)}`);
          reject(err);
        } else {
          console.info(`[FLN-REPEAT] publishReminder success reminderId=${reminderId} ` +
            `type=${reminderRequest.reminderType} notificationId=${reminderRequest.notificationId}`);
          console.info('publishReminder-->success, reminderId: ' + reminderId);
          resolve();
        }
      });
    });
  }

  private async dumpValidReminders(notificationId?: number): Promise<void> {
    try {
      let reminders: ReminderRequest[] = await reminderAgentManager.getValidReminders();
      console.info(`[FLN-REPEAT] getValidReminders count=${reminders.length} lookingForId=${notificationId}`);
      for (let index = 0; index < reminders.length; index++) {
        let reminder: ReminderRequest = reminders[index];
        let timer: ReminderTimer = reminder as ReminderTimer;
        let calendar: ReminderCalendar = reminder as ReminderCalendar;
        console.info(`[FLN-REPEAT] valid[${index}] type=${reminder.reminderType} ` +
          `notificationId=${reminder.notificationId} title=${reminder.title} ` +
          `triggerTimeInSeconds=${timer.triggerTimeInSeconds} ` +
          `timeInterval=${reminder.timeInterval} snoozeTimes=${reminder.snoozeTimes} ` +
          `dateTime=${JSON.stringify(calendar.dateTime)} ` +
          `repeatMonths=${JSON.stringify(calendar.repeatMonths)} ` +
          `repeatDays=${JSON.stringify(calendar.repeatDays)} ` +
          `daysOfWeek=${JSON.stringify(calendar.daysOfWeek)}`);
      }
    } catch (err) {
      console.error(`[FLN-REPEAT] dumpValidReminders err=${JSON.stringify(err)}`);
    }
  }
}
