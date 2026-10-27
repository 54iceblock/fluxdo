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

import { Log, MethodCall, MethodCallHandler, MethodChannel, MethodResult } from '@ohos/flutter_ohos';
import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';
import systemDateTime from '@ohos.systemDateTime';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from './utils/AppContext';
import { readErrorMessage } from './utils/ErrorUtil';
import { NotificationResponseUtil } from './utils/NotificationResponseUtil';
import { LocalNotificationsConstants } from './LocalNotificationsConstants';
import { MethodCallQueryHandler } from './MethodCallQueryHandler';
import { MethodCallSlotHandler } from './MethodCallSlotHandler';
import { NotificationManager } from './NotificationManager';
import NotificationDetails from './models/NotificationDetails';
import { ReminderInfo } from './utils/OhosTypeAliases';

const TAG: string = 'FlutterMethodCallHandlerImpl';
const PERMISSION_REQUEST_IN_PROGRESS_ERROR_CODE: string = 'permissionRequestInProgress';
const PERMISSION_REQUEST_IN_PROGRESS_ERROR_MESSAGE: string =
  'Another permission request is already in progress';
const NOTIFICATION_PERMISSION_ERROR_CODE: string = 'notificationPermissionError';

enum PermissionRequestProgress {
  None,
  RequestingNotificationPermission
}

export default class MethodCallHandlerImpl implements MethodCallHandler {
  private readonly appContext: AppContext;
  private readonly notificationManager: NotificationManager;
  private permissionRequestProgress: PermissionRequestProgress = PermissionRequestProgress.None;
  private slotHandler: MethodCallSlotHandler | null = null;
  private queryHandler: MethodCallQueryHandler | null = null;

  constructor(appContext: AppContext, notificationManager: NotificationManager) {
    this.appContext = appContext;
    this.notificationManager = notificationManager;
    this.slotHandler = new MethodCallSlotHandler(notificationManager);
    this.queryHandler = new MethodCallQueryHandler(notificationManager, appContext);
  }

  /**
   * Routes MethodChannel calls from Dart to OHOS native handlers.
   *
   * @param call Incoming MethodChannel call from Dart.
   * @param result Flutter result callback for the invocation.
   *
   * Legend (see README.OpenHarmony.md):
 * - [OHOS-IMPL]    Implemented on OpenHarmony; reasonable parity with Android/iOS where applicable.
 * - [OHOS-ONLY]    OpenHarmony-specific API (no Android/iOS equivalent).
   * - [NOT-SUPPORTED] Platform has no equivalent API; explicitly returns notImplemented().
   * - [DEFAULT-NI]   Android/iOS-only methods (channels, foreground service,
   *   exact alarms, etc.) -> default notImplemented().
   */
  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (this.dispatchCoreLifecycle(call, result)) {
        return;
      }
      if (this.dispatchPermissions(call, result)) {
        return;
      }
      if (this.dispatchSlotsAndTimezone(call, result)) {
        return;
      }
      if (this.dispatchUnsupported(call, result)) {
        return;
      }
      result.notImplemented();
    } catch (e) {
      Log.e(TAG, 'onMethodCall-->unexpected error: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, String(e), null);
    }
  }

  private dispatchCoreLifecycle(call: MethodCall, result: MethodResult): boolean {
    switch (call.method) {
      case LocalNotificationsConstants.INITIALIZE_METHOD:
        void this.initialize(call, result);
        return true;
      case LocalNotificationsConstants.GET_NOTIFICATION_APP_LAUNCH_DETAILS_METHOD:
        this.queryHandler?.getNotificationAppLaunchDetails(result);
        return true;
      case LocalNotificationsConstants.SHOW_METHOD:
        void this.show(call, result);
        return true;
      case LocalNotificationsConstants.ZONED_SCHEDULE_METHOD:
        void this.zonedSchedule(call, result);
        return true;
      case LocalNotificationsConstants.PERIODICALLY_SHOW_METHOD:
        void this.repeat(call, result);
        return true;
      case LocalNotificationsConstants.PERIODICALLY_SHOW_WITH_DURATION_METHOD:
        void this.repeat(call, result);
        return true;
      case LocalNotificationsConstants.CANCEL_METHOD:
        void this.cancel(call, result);
        return true;
      case LocalNotificationsConstants.CANCEL_ALL_METHOD:
        void this.cancelAllNotifications(result);
        return true;
      case LocalNotificationsConstants.CANCEL_ALL_PENDING_NOTIFICATIONS_METHOD:
        void this.cancelAllPendingNotifications(result);
        return true;
      case LocalNotificationsConstants.PENDING_NOTIFICATION_REQUESTS_METHOD:
        void this.queryHandler?.getScheduledNotifications(result);
        return true;
      case LocalNotificationsConstants.GET_ACTIVE_NOTIFICATIONS_METHOD:
        void this.queryHandler?.getActiveNotifications(result);
        return true;
      default:
        return false;
    }
  }

  private dispatchPermissions(call: MethodCall, result: MethodResult): boolean {
    switch (call.method) {
      case LocalNotificationsConstants.ARE_NOTIFICATIONS_ENABLED_METHOD:
        void this.isNotificationEnable(result);
        return true;
      case LocalNotificationsConstants.REQUEST_NOTIFICATIONS_PERMISSION_METHOD:
        void this.requestNotificationsPermission(result);
        return true;
      default:
        return false;
    }
  }

  private dispatchSlotsAndTimezone(call: MethodCall, result: MethodResult): boolean {
    switch (call.method) {
      case LocalNotificationsConstants.ADD_NOTIFICATION_SLOT_METHOD:
        void this.slotHandler?.addNotificationSlot(call, result);
        return true;
      case LocalNotificationsConstants.DELETE_NOTIFICATION_SLOT_METHOD:
        void this.slotHandler?.deleteNotificationSlot(call, result);
        return true;
      case LocalNotificationsConstants.GET_NOTIFICATION_SLOT_METHOD:
        void this.slotHandler?.getNotificationSlots(result);
        return true;
      case LocalNotificationsConstants.GET_LOCAL_TIMEZONE:
        try {
          result.success(systemDateTime.getTimezoneSync());
        } catch (e) {
          Log.e(TAG, 'getLocalTimezone-->err msg: ' + JSON.stringify(e));
          result.success('UTC');
        }
        return true;
      default:
        return false;
    }
  }

  private dispatchUnsupported(call: MethodCall, result: MethodResult): boolean {
    switch (call.method) {
      case LocalNotificationsConstants.GET_CALLBACK_HANDLE_METHOD:
        result.notImplemented();
        return true;
      case LocalNotificationsConstants.REQUEST_FULL_SCREEN_INTENT_PERMISSION_METHOD:
        this.requestFullScreenIntentPermission(call, result);
        return true;
      default:
        return false;
    }
  }

  private parseCallNotificationId(call: MethodCall): number | undefined {
    let rawId: string | number | undefined = call.argument(LocalNotificationsConstants.ID) as
      (string | number | undefined);
    if (rawId === null || rawId === undefined || rawId === '') {
      return undefined;
    }
    let notificationId: number = Number(rawId);
    if (Number.isNaN(notificationId)) {
      return undefined;
    }
    return notificationId;
  }

  private formatErrorMessage(error: Error | BusinessError | ESObject): string {
    return readErrorMessage(error);
  }

  private resolveNotificationErrorCode(message: string): string {
    let normalized: string = message.toLowerCase();
    if (normalized.includes('invalid_big_picture')) {
      return LocalNotificationsConstants.ERROR_INVALID_BIG_PICTURE;
    }
    if (normalized.includes('invalid_sound')) {
      return LocalNotificationsConstants.ERROR_INVALID_SOUND;
    }
    if (normalized.includes('invalid_icon')) {
      return LocalNotificationsConstants.ERROR_INVALID_ICON;
    }
    if (normalized.includes('params check failed') || normalized.includes('notification type not support')) {
      return LocalNotificationsConstants.ERROR_INVALID_PARAMETERS;
    }
    return LocalNotificationsConstants.ERROR_NOTIFICATION_PUBLISH_FAILED;
  }

  /**
   * Resets in-flight permission request state when the ability or engine detaches.
   */
  resetPermissionState(): void {
    this.permissionRequestProgress = PermissionRequestProgress.None;
  }

  /**
   * Releases handler state when the engine detaches.
   */
  dispose(): void {
    this.permissionRequestProgress = PermissionRequestProgress.None;
    this.queryHandler = null;
    this.slotHandler = null;
    this.notificationManager.reset();
    this.appContext.clearDefaultIcon();
    this.appContext.clearLaunchWant();
  }

  /**
   * Stores the launch Want for cold-start notification response lookup.
   *
   * @param launchWant Ability launch Want from EntryAbility.
   */
  initLaunchWant(launchWant: Want | undefined): void {
    Log.d(TAG, 'initLaunchWant--> want: ' + JSON.stringify(launchWant));
    this.appContext.setLaunchWant(launchWant);
  }

  /**
   * Forwards notification action taps to Dart via MethodChannel.
   *
   * @param want Incoming Want from notification action.
   * @param channel Active MethodChannel instance.
   */
  onNewWant(want: Want, channel: MethodChannel): void {
    try {
      Log.d(TAG, 'onNewWant--> want: ' + JSON.stringify(want));
      let action: string | undefined = want?.action;
      let isSelectionAction: boolean = action === LocalNotificationsConstants.ACTION_SELECTION_NOTIFICATION;
      let hasSelectionParameter: boolean = want?.parameters != undefined &&
        want.parameters[LocalNotificationsConstants.ACTION] ==
          LocalNotificationsConstants.ACTION_SELECTION_NOTIFICATION;
      if (isSelectionAction || hasSelectionParameter) {
        let responseMap: Map<string, Object> =
          NotificationResponseUtil.extractNotificationResponseMap(want);
        if (responseMap.size > 0) {
          channel.invokeMethod(LocalNotificationsConstants.RECEIVE_NOTIFICATION_RESPONSE, responseMap);
        } else {
          Log.w(TAG, 'onNewWant-->empty response map, skip forwarding');
        }
      }
    } catch (e) {
      Log.e(TAG, 'onNewWant-->error: ' + JSON.stringify(e));
      try {
        let errorMap: Map<string, Object> = new Map<string, Object>();
        errorMap.set(LocalNotificationsConstants.ERROR_UNEXPECTED, readErrorMessage(e));
        channel.invokeMethod(LocalNotificationsConstants.RECEIVE_NOTIFICATION_RESPONSE, errorMap);
      } catch (invokeErr) {
        Log.e(TAG, 'onNewWant-->failed to report error to Flutter: ' + JSON.stringify(invokeErr));
      }
    }
  }

  private requestFullScreenIntentPermission(call: MethodCall, result: MethodResult): void {
    result.notImplemented();
  }

  /**
   * Loads default icon resource name into plugin AppContext for subsequent notifications.
   *
   * @param call Method call containing DEFAULT_ICON argument.
   * @param result Flutter result callback.
   */
  private async initialize(call: MethodCall, result: MethodResult): Promise<void> {
    let defaultIcon: string = call.argument(LocalNotificationsConstants.DEFAULT_ICON);
    Log.d(TAG, 'initialize-->defaultIcon set defaultIcon: ' + defaultIcon);
    if (!defaultIcon) {
      Log.w(TAG, 'initialize-->defaultIcon not set');
      result.success(true);
      return;
    }
    try {
      let uiAbility: UIAbility | undefined = this.appContext.getAbility();
      if (!uiAbility) {
        Log.w(TAG, 'initialize-->UIAbility not bound yet, defer defaultIcon: ' + defaultIcon);
        this.appContext.setDefaultIcon(defaultIcon);
        result.success(true);
        return;
      }
      let icon: Uint8Array | undefined = await uiAbility.context.resourceManager.getMediaByName(defaultIcon);
      if (icon) {
        this.appContext.setDefaultIcon(defaultIcon);
        Log.i(TAG, 'initialize-->defaultIcon seted');
        result.success(true);
      } else {
        Log.i(TAG, 'initialize-->defaultIcon get failed');
        result.error(LocalNotificationsConstants.ERROR_INVALID_ICON,
          'The resource ' + defaultIcon + ' could not be found.', null);
      }
    } catch (e) {
      Log.e(TAG, 'initialize-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_INITIALIZE_FAILED, this.formatErrorMessage(e), null);
    }
  }

  /**
   * Publishes an immediate notification from Dart show() arguments.
   *
   * @param call Method call with id, title, body and platform specifics.
   * @param result Flutter result callback.
   */
  private async show(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let notificationId: number | undefined = this.parseCallNotificationId(call);
      if (notificationId === undefined) {
        result.error(LocalNotificationsConstants.ERROR_INVALID_PARAMETERS,
          call.argument(LocalNotificationsConstants.ID) == null ? 'id is required' : 'id must be a number', null);
        return;
      }
      let notificationDetails: NotificationDetails = NotificationDetails.from(call);
      Log.d(TAG, 'show-->request: ' + JSON.stringify(notificationDetails));
      await this.notificationManager.showNotification(notificationDetails);
      result.success(null);
    } catch (e) {
      let message: string = this.formatErrorMessage(e);
      result.error(this.resolveNotificationErrorCode(message), message, null);
      Log.e(TAG, 'show-->err msg: ' + JSON.stringify(e));
    }
  }

  /**
   * Schedules a zoned notification using ReminderAgent calendar or timer API.
   *
   * @param call Method call with scheduledDateTime and matchDateTimeComponents index.
   * @param result Flutter result callback.
   */
  private async zonedSchedule(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let notificationDetails: NotificationDetails = NotificationDetails.from(call);
      Log.d(TAG, 'zonedSchedule-->request: ' + JSON.stringify(notificationDetails));
      if (notificationDetails.scheduledDateTime == undefined ||
        String(notificationDetails.scheduledDateTime).trim().length === 0) {
        result.error(LocalNotificationsConstants.ERROR_INVALID_PARAMETERS,
          'scheduledDateTime is required', null);
        return;
      }
      if (notificationDetails.matchDateTimeComponents == undefined) {
        await this.notificationManager.publishTimerReminder(notificationDetails);
      } else {
        await this.notificationManager.publishCalendarReminder(notificationDetails);
      }
      result.success(null);
    } catch (e) {
      result.error(LocalNotificationsConstants.ERROR_REMINDER_PUBLISH_FAILED, this.formatErrorMessage(e), null);
      Log.e(TAG, 'zonedSchedule-->err msg: ' + JSON.stringify(e));
    }
  }

  private async requestNotificationsPermission(result: MethodResult): Promise<void> {
    if (this.permissionRequestProgress !== PermissionRequestProgress.None) {
      result.error(PERMISSION_REQUEST_IN_PROGRESS_ERROR_CODE, PERMISSION_REQUEST_IN_PROGRESS_ERROR_MESSAGE, null);
      return;
    }
    this.permissionRequestProgress = PermissionRequestProgress.RequestingNotificationPermission;
    try {
      let enable: boolean = await this.notificationManager.enableNotification();
      result.success(enable);
    } catch (e) {
      Log.e(TAG, 'requestNotificationsPermission-->err msg: ' + JSON.stringify(e));
      let errMessage: string = (e as Error)?.message ?? String(e);
      result.error(NOTIFICATION_PERMISSION_ERROR_CODE, errMessage, null);
      return;
    } finally {
      this.permissionRequestProgress = PermissionRequestProgress.None;
    }
  }

  /**
   * Handles periodicallyShow / periodicallyShowWithDuration from Dart.
   *
   * @param call Method call with repeatInterval or repeatDurationMillis.
   * @param result Flutter result callback.
   */
  private async repeat(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let notificationDetails: NotificationDetails = NotificationDetails.from(call);
      let pathName: string = notificationDetails.usesTimerRepeat() ?
        'publishTimerReminder/TIMER' : 'publishPeriodicReminder/CALENDAR';
      Log.i(TAG, `[FLN-REPEAT] native repeat() method=${call.method} id=${notificationDetails.id} ` +
        `title=${notificationDetails.title} repeatInterval=${notificationDetails.repeatInterval} ` +
        `repeatIntervalMilliseconds=${notificationDetails.repeatIntervalMilliseconds} ` +
        `scheduledDateTime=${notificationDetails.scheduledDateTime} path=${pathName}`);
      Log.d(TAG, 'repeat-->request: ' + JSON.stringify(notificationDetails));
      if (notificationDetails.repeatInterval == undefined &&
        notificationDetails.repeatIntervalMilliseconds == undefined) {
        result.error(LocalNotificationsConstants.ERROR_INVALID_PARAMETERS,
          'repeatInterval or repeatIntervalMilliseconds is required', null);
        return;
      }
      if (notificationDetails.usesTimerRepeat()) {
        await this.notificationManager.publishTimerReminder(notificationDetails);
      } else {
        await this.notificationManager.publishPeriodicReminder(notificationDetails);
      }
      result.success(null);
    } catch (e) {
      result.error(LocalNotificationsConstants.ERROR_REMINDER_PUBLISH_FAILED, this.formatErrorMessage(e), null);
      Log.e(TAG, 'repeat-->err msg: ' + JSON.stringify(e));
    }
  }

  private async cancel(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      let notificationId: number | undefined = this.parseCallNotificationId(call);
      if (notificationId === undefined) {
        result.error(LocalNotificationsConstants.ERROR_INVALID_PARAMETERS,
          call.argument(LocalNotificationsConstants.ID) == null ? 'id is required' : 'id must be a number', null);
        return;
      }
      await this.notificationManager.cancelNotificationById(notificationId,
        call.argument(LocalNotificationsConstants.TAG));
      await this.notificationManager.cancelTimerChainNotifications(notificationId);
      let reminderList: ReminderInfo[] = await reminderAgentManager.getAllValidReminders();
      if (reminderList && reminderList.length > 0) {
        for (let index = 0; index < reminderList.length; index++) {
          let reminderInfo: ReminderInfo = reminderList[index];
          if (reminderInfo && this.queryHandler?.reminderMatchesNotificationId(reminderInfo, notificationId)) {
            await this.notificationManager.cancelReminderById(reminderInfo.reminderId);
          }
        }
      }
      result.success(null);
    } catch (e) {
      Log.e(TAG, 'cancel-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, this.formatErrorMessage(e), null);
    }
  }

  private async cancelAllNotifications(result: MethodResult): Promise<void> {
    try {
      await this.notificationManager.cancelAllNotifications();
      await this.notificationManager.cancelAllReminders();
      result.success(null);
    } catch (e) {
      Log.e(TAG, 'cancelAllNotifications-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, this.formatErrorMessage(e), null);
    }
  }

  private async cancelAllPendingNotifications(result: MethodResult): Promise<void> {
    try {
      await this.notificationManager.cancelAllPendingNotifications();
      result.success(null);
    } catch (e) {
      result.error(LocalNotificationsConstants.ERROR_REMINDER_PUBLISH_FAILED, this.formatErrorMessage(e), null);
      Log.e(TAG, 'cancelAllPendingNotifications-->err msg: ' + JSON.stringify(e));
    }
  }

  private async isNotificationEnable(result: MethodResult): Promise<void> {
    try {
      let enable: boolean = await this.notificationManager.isNotificationEnable();
      result.success(enable);
    } catch (e) {
      Log.e(TAG, 'isNotificationEnable-->err msg: ' + JSON.stringify(e));
      result.error(LocalNotificationsConstants.ERROR_UNEXPECTED, this.formatErrorMessage(e), null);
    }
  }
}
