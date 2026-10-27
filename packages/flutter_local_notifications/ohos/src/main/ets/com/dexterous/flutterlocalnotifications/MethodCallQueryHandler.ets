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

import { Log, MethodResult } from '@ohos/flutter_ohos';
import Want from '@ohos.app.ability.Want';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { LocalNotificationsConstants } from './LocalNotificationsConstants';
import { NotificationManager } from './NotificationManager';
import { NRequest, ReminderInfo, ReminderRequest } from './utils/OhosTypeAliases';
import { readErrorMessage } from './utils/ErrorUtil';
import { NotificationResponseUtil } from './utils/NotificationResponseUtil';
import { AppContext } from './utils/AppContext';

const TAG: string = 'MethodCallQueryHandler';

/** Handles notification query MethodChannel operations. */
export class MethodCallQueryHandler {
  private readonly notificationManager: NotificationManager;
  private readonly appContext: AppContext;

  constructor(notificationManager: NotificationManager, appContext: AppContext) {
    this.notificationManager = notificationManager;
    this.appContext = appContext;
  }

  /**
   * Returns notification launch details when the app was opened from a notification.
   *
   * @param result Flutter result callback for the query response.
   */
  getNotificationAppLaunchDetails(result: MethodResult): void {
    try {
      let launchWant: Want | undefined = this.appContext.getLaunchWant();
      let notificationLaunchedApp: boolean = this.isNotificationLaunchWant(launchWant);
      let notificationAppLaunchDetails: Map<string, Object> = new Map<string, Object>();
      if (notificationLaunchedApp) {
        let responseMap: Map<string, Object> =
          NotificationResponseUtil.extractNotificationResponseMap(launchWant);
        notificationAppLaunchDetails.set(LocalNotificationsConstants.NOTIFICATION_RESPONSE, responseMap);
      }
      Log.i(TAG, 'getNotificationAppLaunchDetails-->LaunchedApp from notification: ' + notificationLaunchedApp);
      notificationAppLaunchDetails.set(LocalNotificationsConstants.NOTIFICATION_LAUNCHED_APP,
        notificationLaunchedApp);
      Log.d(TAG, 'getNotificationAppLaunchDetails-->data: ' + JSON.stringify(notificationAppLaunchDetails));
      result.success(notificationAppLaunchDetails);
    } catch (e) {
      Log.e(TAG, 'getNotificationAppLaunchDetails-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, readErrorMessage(e), null);
    }
  }

  /**
   * Returns all valid scheduled reminders as pending notification requests.
   *
   * @param result Flutter result callback for the query response.
   */
  async getScheduledNotifications(result: MethodResult): Promise<void> {
    try {
      Log.d(TAG, 'getScheduledNotifications-->request: ');
      let scheduledNotifications: ReminderRequest[] =
        await this.notificationManager.getReminderList();
      if (scheduledNotifications) {
        let pendingNotifications: Map<string, Object>[] = [];
        for (let scheduledNotification of scheduledNotifications) {
          let pendingNotification: Map<string, Object> = new Map();
          let resolvedId: number | undefined =
            this.resolveReminderNotificationId(scheduledNotification);
          if (resolvedId == undefined && scheduledNotification.notificationId != undefined) {
            resolvedId = scheduledNotification.notificationId;
          }
          if (resolvedId == undefined) {
            Log.w(TAG, 'getScheduledNotifications-->skip reminder without resolvable id');
            continue;
          }
          pendingNotification.set(LocalNotificationsConstants.ID, resolvedId);
          pendingNotification.set(LocalNotificationsConstants.TITLE, scheduledNotification.title ?? '');
          pendingNotification.set(LocalNotificationsConstants.BODY, scheduledNotification.content ?? '');
          pendingNotifications.push(pendingNotification);
        }
        Log.d(TAG, 'getScheduledNotifications-->data: ' + JSON.stringify(pendingNotifications));
        result.success(pendingNotifications);
        return;
      }
      Log.d(TAG, 'getScheduledNotifications-->data: empty');
      result.success([]);
    } catch (e) {
      Log.e(TAG, 'getScheduledNotifications-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, readErrorMessage(e), null);
    }
  }

  /**
   * Returns all active notifications currently displayed by the application.
   *
   * @param result Flutter result callback for the query response.
   */
  async getActiveNotifications(result: MethodResult): Promise<void> {
    try {
      Log.d(TAG, 'getActiveNotifications-->request: ');
      let activeNotifications: NRequest[] =
        await this.notificationManager.getActiveNotifications();
      if (!activeNotifications) {
        Log.d(TAG, 'getActiveNotifications-->data: empty');
        result.success([]);
        return;
      }
      let activeNotificationsList: Map<string, Object>[] = [];
      for (let notification of activeNotifications) {
        let map: Map<string, Object> = new Map();
        map.set(LocalNotificationsConstants.ID, notification.id ?? 0);
        map.set(LocalNotificationsConstants.TAG, notification.label ?? '');
        map.set(LocalNotificationsConstants.GROUP_KEY, notification.groupName ?? '');
        map.set(LocalNotificationsConstants.TITLE, notification.content?.normal?.title ?? '');
        map.set(LocalNotificationsConstants.BODY, notification.content?.normal?.text ?? '');
        map.set(LocalNotificationsConstants.BIG_TEXT, notification.content?.longText?.longText ?? '');
        activeNotificationsList.push(map);
      }
      Log.d(TAG, 'getActiveNotifications-->data: ' + JSON.stringify(activeNotificationsList));
      result.success(activeNotificationsList);
    } catch (e) {
      Log.e(TAG, 'getActiveNotifications-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, readErrorMessage(e), null);
    }
  }

  /**
   * Parses a raw notification id from MethodChannel arguments.
   *
   * @param rawId Raw id value from Dart.
   * @returns Parsed numeric id or undefined when invalid.
   */
  private isNotificationLaunchWant(want: Want | undefined): boolean {
    if (want == undefined) {
      return false;
    }
    if (want.action === LocalNotificationsConstants.ACTION_SELECTION_NOTIFICATION) {
      return true;
    }
    let parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters == undefined) {
      return false;
    }
    if (parameters[LocalNotificationsConstants.ACTION] ==
      LocalNotificationsConstants.ACTION_SELECTION_NOTIFICATION) {
      return true;
    }
    // Cold-start WantAgent launches may omit action but still carry response fields.
    return parameters[LocalNotificationsConstants.NOTIFICATION_ID] != null ||
      (parameters[LocalNotificationsConstants.PAYLOAD] != null &&
        parameters[LocalNotificationsConstants.PAYLOAD] !== '');
  }

  parseNotificationId(rawId: string | number | undefined | null): number | undefined {
    if (rawId == null || rawId === '') {
      return undefined;
    }
    let id: number = Number(rawId);
    if (Number.isNaN(id)) {
      return undefined;
    }
    return id;
  }

  /**
   * Resolves the notification id embedded in a reminder request payload.
   *
   * @param reminderReq Reminder request from ReminderAgent.
   * @returns Parsed notification id or undefined when absent.
   */
  resolveReminderNotificationId(reminderReq?: ReminderRequest): number | undefined {
    let paramId: string | number | undefined =
      reminderReq?.wantAgent?.parameters?.[LocalNotificationsConstants.NOTIFICATION_ID] as
        (string | number | undefined);
    return this.parseNotificationId(paramId);
  }

  /**
   * Checks whether a reminder entry matches the given notification id.
   *
   * @param reminderInfo Reminder metadata from ReminderAgent.
   * @param notificationId Notification id to compare.
   * @returns true when the reminder corresponds to the notification id.
   */
  reminderMatchesNotificationId(reminderInfo: ReminderInfo, notificationId: number): boolean {
    let resolvedId: number | undefined = this.resolveReminderNotificationId(reminderInfo.reminderReq);
    return resolvedId != undefined && resolvedId === notificationId;
  }
}
