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

import { bundleManager, UIAbility, wantAgent } from '@kit.AbilityKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { notificationManager } from '@kit.NotificationKit';
import fs from '@ohos.file.fs';
import { Log } from '@ohos/flutter_ohos';
import { LocalNotificationsConstants } from './LocalNotificationsConstants';
import NotificationDetails from './models/NotificationDetails';
import { NotificationActionInput } from './models/NotificationAction';
import NotificationSlotDetails from './models/NotificationSlotDetails';
import { NotificationStyle } from './models/styles/NotificationStyle';
import { NotificationSlotAction } from './models/NotificationSlotAction';
import { SoundSource } from './models/SoundSource';
import { NotificationContentFactory } from './NotificationContentFactory';
import { NotificationSlotManager } from './NotificationSlotManager';
import { ReminderScheduler } from './ReminderScheduler';
import { AppContext } from './utils/AppContext';
import { readBusinessError } from './utils/ErrorUtil';
import { NActionButton, NContent, NRequest, NSlot, ReminderRequest } from './utils/OhosTypeAliases';
import { Utils } from './utils/Utils';

const TAG: string = 'FlutterNotificationManager';
const RAW_SOUND_EXTENSIONS: string[] =
  ['.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac', '.amr', '.aiff'];
const INVALID_RAW_SOUND_ERROR_MESSAGE: string =
  'The resource %s could not be found. Please make sure it has been added as a rawfile ' +
  'resource to your OpenHarmony head project.';

/** Facade for OHOS notification publishing, scheduling, and slot management. */
export class NotificationManager {
  private readonly appContext: AppContext;
  private readonly slotManager: NotificationSlotManager;
  private readonly contentFactory: NotificationContentFactory;
  private readonly reminderScheduler: ReminderScheduler;

  constructor(appContext: AppContext) {
    this.appContext = appContext;
    this.slotManager = new NotificationSlotManager();
    this.contentFactory = new NotificationContentFactory(appContext);
    this.reminderScheduler = new ReminderScheduler(this.slotManager, this.contentFactory);
  }

  /** Clears cached notification slot actions when the engine detaches. */
  reset(): void {
    this.slotManager.reset();
  }

  /**
   * Returns the slot action previously stored for a slot type.
   *
   * @param slotType OHOS notification slot type value.
   * @returns Stored slot action or undefined when not set.
   */
  getStoredSlotAction(slotType: number): NotificationSlotAction | undefined {
    return this.slotManager.getStoredSlotAction(slotType);
  }

  private propagateError(err: Error | BusinessError | ESObject): never {
    let businessError: BusinessError | undefined = readBusinessError(err as Error | BusinessError);
    if (businessError != undefined) {
      throw new Error(businessError.message);
    }
    throw new Error(err instanceof Error ? err.message : String(err));
  }

  /**
   * Builds notification content from style information and publishes immediately.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async showNotification(notificationDetails: NotificationDetails): Promise<void> {
    let notificationRequest: NRequest | undefined = undefined;
    let notificationContent: NContent | undefined = undefined;
    try {
      let slotDetails: NotificationSlotDetails =
        NotificationSlotDetails.fromNotificationDetails(notificationDetails);
      await this.slotManager.ensureSlotForDetails(slotDetails);
      notificationContent = await this.contentFactory.buildNotificationContent(notificationDetails);
      if (!notificationContent) {
        if (notificationDetails.style === NotificationStyle.BigPicture) {
          throw new Error('invalid_big_picture: picture content validation failed');
        }
        throw new Error('params check failed');
      }
      notificationRequest = await this.initBasicNotificationRequest(notificationContent, notificationDetails);
      if (!notificationRequest) {
        throw new Error('notification type not support');
      }
      Log.d(TAG, 'showNotification-->request: ' + JSON.stringify(notificationRequest));
      await this.publishNotificationRequest(notificationRequest, notificationDetails.badgeNumber);
      this.releaseNotificationResources(notificationRequest, notificationContent);
    } catch (err) {
      this.releaseNotificationResources(notificationRequest, notificationContent);
      Log.e(TAG, 'showNotification-->err msg: ' + JSON.stringify(err));
      this.propagateError(err);
    }
  }

  private releaseNotificationResources(request: NRequest | undefined, content?: NContent): void {
    this.releaseNotificationRequestIcons(request);
    this.contentFactory.releaseContentPixelMaps(content);
  }

  private releaseNotificationRequestIcons(request: NRequest | undefined): void {
    if (request == undefined) {
      return;
    }
    try {
      request.smallIcon?.release();
    } catch (e) {
      Log.e(TAG, 'releaseNotificationRequestIcons-->smallIcon: ' + JSON.stringify(e));
    }
    try {
      request.largeIcon?.release();
    } catch (e) {
      Log.e(TAG, 'releaseNotificationRequestIcons-->largeIcon: ' + JSON.stringify(e));
    }
  }

  private publishNotificationRequest(notificationRequest: NRequest, badgeNumber?: number): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      notificationManager.publish(notificationRequest, async (err: BusinessError) => {
        if (err?.code) {
          Log.e(TAG, 'showNotification-->err code:' + err.code + ' message:' + err.message);
          reject(err);
        } else {
          if (badgeNumber != undefined) {
            try {
              await notificationManager.setBadgeNumber(badgeNumber);
            } catch (badgeErr) {
              Log.w(TAG, 'showNotification-->badge set failed but notification published: ' +
                JSON.stringify(badgeErr));
            }
          }
          Log.i(TAG, 'showNotification-->success');
          resolve();
        }
      });
    });
  }

  /**
   * Request notification permission via NotificationKit.
   *
   * @returns true if granted; false if notification is disabled (user denied / switch off, code 1600004).
   * @throws BusinessError for other failures (parameter/internal/service/dialog-already-shown),
   *         so the Flutter layer can map them to PlatformException(code: notificationPermissionError).
   */
  async enableNotification(): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification();
      Log.i(TAG, 'enableNotification-->success');
      return true;
    } catch (err) {
      Log.e(TAG, `enableNotification-->err msg: ${JSON.stringify(err)}`);
      let error: BusinessError | undefined = readBusinessError(err);
      if (error?.code === 1600004) {
        return false;
      }
      this.propagateError(err);
    }
  }

  /**
   * Returns whether notifications are enabled for the current application.
   *
   * @returns true when notifications are enabled.
   */
  async isNotificationEnable(): Promise<boolean> {
    try {
      let enable: boolean = await notificationManager.isNotificationEnabled();
      Log.i(TAG, 'isNotificationEnable-->success');
      return enable;
    } catch (err) {
      Log.e(TAG, `isNotificationEnable-->err msg: ${JSON.stringify(err)}`);
      this.propagateError(err);
    }
  }

  /**
   * Cancels a scheduled reminder by reminder id.
   *
   * @param notificationId Reminder id returned by ReminderAgent.
   */
  async cancelReminderById(notificationId: number): Promise<void> {
    await this.reminderScheduler.cancelReminderById(notificationId);
  }

  /**
   * Cancels a published notification by id and optional label.
   *
   * @param notificationId Notification id.
   * @param label Optional notification label/tag.
   */
  async cancelNotificationById(notificationId: number, label: string | undefined): Promise<void> {
    try {
      Log.d(TAG, 'cancelNotificationById-->notificationId: ' + notificationId + ', tag: ' + label);
      await notificationManager.cancel(notificationId, label);
      Log.i(TAG, 'cancelNotificationById-->success');
    } catch (err) {
      Log.e(TAG, `cancelNotificationById-->err msg: ${JSON.stringify(err)}`);
      this.propagateError(err);
    }
  }

  /**
   * Cancels displayed TIMER-chain notifications that used derived occurrence IDs.
   *
   * @param baseId Flutter notification id passed to cancel(id).
   */
  async cancelTimerChainNotifications(baseId: number): Promise<void> {
    try {
      let activeNotifications: NRequest[] = await notificationManager.getActiveNotifications();
      if (activeNotifications) {
        for (let index = 0; index < activeNotifications.length; index++) {
          let notification: NRequest = activeNotifications[index];
          if (notification.id != undefined &&
            this.reminderScheduler.isTimerChainNotificationId(baseId, notification.id)) {
            await this.cancelDisplayedNotification(notification.id, notification.label);
          }
        }
      }
    } catch (err) {
      Log.e(TAG, `cancelTimerChainNotifications-->getActiveNotifications err: ${JSON.stringify(err)}`);
    }
    let chainIds: number[] = this.reminderScheduler.timerChainNotificationIds(baseId);
    for (let index = 0; index < chainIds.length; index++) {
      await this.cancelDisplayedNotification(chainIds[index], undefined);
    }
  }

  private async cancelDisplayedNotification(notificationId: number, label: string | undefined): Promise<void> {
    try {
      await notificationManager.cancel(notificationId, label);
    } catch (err) {
      Log.d(TAG, `cancelDisplayedNotification-->id=${notificationId} err=${JSON.stringify(err)}`);
    }
  }

  /** Cancels all published notifications. */
  async cancelAllNotifications(): Promise<void> {
    try {
      await notificationManager.cancelAll();
      Log.i(TAG, 'cancelAllNotifications-->success');
    } catch (err) {
      Log.e(TAG, `cancelAllNotifications-->err msg: ${JSON.stringify(err)}`);
      this.propagateError(err);
    }
  }

  /** Cancels all scheduled reminders registered by ReminderAgent. */
  async cancelAllReminders(): Promise<void> {
    await this.reminderScheduler.cancelAllReminders();
  }

  /** Cancels all pending scheduled reminders (alias for cancelAllReminders). */
  async cancelAllPendingNotifications(): Promise<void> {
    await this.reminderScheduler.cancelAllReminders();
  }

  /**
   * Returns all valid scheduled reminders from ReminderAgent.
   *
   * @returns Array of reminder request payloads.
   */
  async getReminderList(): Promise<ReminderRequest[]> {
    return this.reminderScheduler.getReminderList();
  }

  /**
   * Returns all active notifications currently shown by the application.
   *
   * @returns Array of active notification requests.
   */
  async getActiveNotifications(): Promise<NRequest[]> {
    try {
      let notifications: NRequest[] = await notificationManager.getActiveNotifications();
      Log.i(TAG, 'getActiveNotifications-->success, data: ' + JSON.stringify(notifications));
      return notifications;
    } catch (err) {
      Log.e(TAG, 'getActiveNotifications-->err msg:' + JSON.stringify(err));
      this.propagateError(err);
    }
  }

  /**
   * Schedules a repeating reminder using ReminderAgent periodic API.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async publishPeriodicReminder(notificationDetails: NotificationDetails): Promise<void> {
    await this.reminderScheduler.publishPeriodicReminder(notificationDetails);
  }

  /**
   * Schedules a one-shot timer reminder using ReminderAgent.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async publishTimerReminder(notificationDetails: NotificationDetails): Promise<void> {
    await this.reminderScheduler.publishTimerReminder(notificationDetails);
  }

  /**
   * Schedules a calendar-based reminder using ReminderAgent.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   */
  async publishCalendarReminder(notificationDetails: NotificationDetails): Promise<void> {
    await this.reminderScheduler.publishCalendarReminder(notificationDetails);
  }

  /**
   * Adds or updates a notification slot configuration.
   *
   * @param notificationSlotDetails Parsed slot details from Dart.
   */
  async addNotificationSlot(notificationSlotDetails: NotificationSlotDetails): Promise<void> {
    await this.slotManager.addNotificationSlot(notificationSlotDetails);
  }

  /**
   * Removes a notification slot by slot type.
   *
   * @param slotType OHOS notification slot type value.
   */
  async removeNotificationSlot(slotType: number): Promise<void> {
    await this.slotManager.removeNotificationSlot(slotType);
  }

  /**
   * Returns all notification slots configured for the application.
   *
   * @returns Array of notification slot descriptors.
   */
  async getAllNotificationSlots(): Promise<NSlot[]> {
    return this.slotManager.getAllNotificationSlots();
  }

  /**
   * Returns a notification slot by slot type.
   *
   * @param slotType OHOS notification slot type value.
   * @returns Slot descriptor or undefined when not found.
   */
  async getNotificationSlotByType(slotType: number): Promise<NSlot | undefined> {
    return this.slotManager.getNotificationSlotByType(slotType);
  }

  private async buildActionButtons(notificationDetails: NotificationDetails): Promise<NActionButton[]> {
    let actionButtons: NActionButton[] = [];
    if (!notificationDetails.actions || notificationDetails.actions.length === 0) {
      return actionButtons;
    }
    for (let notificationAction of notificationDetails.actions) {
      let actionItem: NActionButton = {
        title: notificationAction.title ?? '',
        wantAgent: await this.createWantAgentForStartAbility(notificationAction.id, notificationDetails),
      };
      if (notificationAction.actionInputs && notificationAction.actionInputs.length > 0) {
        let input: NotificationActionInput = notificationAction.actionInputs[0];
        actionItem.userInput = {
          inputKey: input.label ?? notificationAction.id ?? '',
        };
      }
      actionButtons.push(actionItem);
    }
    return actionButtons;
  }

  private async applyOptionalRequestFields(result: NRequest, notificationDetails: NotificationDetails): Promise<void> {
    if (notificationDetails.id != undefined) {
      result.id = notificationDetails.id;
    }
    if (notificationDetails.slotType != undefined) {
      result.notificationSlotType = notificationDetails.slotType;
    }
    if (notificationDetails.ongoing != undefined) {
      result.isOngoing = notificationDetails.ongoing;
    }
    this.applyDeliveryTimeFields(result, notificationDetails);
    if (notificationDetails.autoCancel != undefined) {
      result.tapDismissed = notificationDetails.autoCancel;
    }
    if (notificationDetails.timeoutAfter) {
      result.autoDeletedTime = await systemDateTime.getCurrentTime(false) + notificationDetails.timeoutAfter;
    }
    // OHOS NotificationRequest.color/colorEnabled are documented as unsupported;
    // setting them causes publish() parameter validation failures (error 1600001).
    if (notificationDetails.onlyAlertOnce != undefined) {
      result.isAlertOnce = notificationDetails.onlyAlertOnce;
    }
    if (notificationDetails.usesChronometer) {
      result.isStopwatch = !notificationDetails.chronometerCountDown;
      result.isCountDown = notificationDetails.chronometerCountDown;
    }
    if (notificationDetails.isFloatingIcon != undefined) {
      result.isFloatingIcon = notificationDetails.isFloatingIcon;
    }
    Log.i(TAG, 'apply-->isFloatingIcon=' + JSON.stringify(result.isFloatingIcon));
    if (notificationDetails.tag) {
      result.label = notificationDetails.tag;
    }
    if (notificationDetails.groupKey) {
      result.groupName = notificationDetails.groupKey;
    }
  }

  /**
   * Maps Dart showWhen/when to OHOS deliveryTime/showDeliveryTime.
   *
   * OpenHarmony maps [when] to deliveryTime (custom relative time works). Setting
   * showWhen to false maps to showDeliveryTime=false, but as of OpenHarmony 6.1
   * showDeliveryTime is a reserved API and the system still renders the default
   * relative time label (e.g. "刚刚") when deliveryTime is auto-generated.
   */
  private applyDeliveryTimeFields(result: NRequest, notificationDetails: NotificationDetails): void {
    if (notificationDetails.showWhen === false) {
      result.showDeliveryTime = false;
      return;
    }
    if (notificationDetails.showWhen != undefined) {
      result.showDeliveryTime = notificationDetails.showWhen;
    }
    if (notificationDetails.when != undefined) {
      result.deliveryTime = notificationDetails.when;
    }
  }

  private async loadRequestIcons(result: NRequest, notificationDetails: NotificationDetails): Promise<void> {
    let defaultIcon: string | undefined = notificationDetails.icon ?
      notificationDetails.icon : this.appContext.getDefaultIcon();
    if (defaultIcon) {
      let uiAbility: UIAbility | undefined = this.appContext.getAbility();
      let icon: Uint8Array | undefined = await uiAbility?.context.resourceManager.getMediaByName(defaultIcon);
      if (icon) {
        let imageSource: image.ImageSource | undefined = undefined;
        try {
          imageSource = image.createImageSource(icon.buffer);
          result.smallIcon = await imageSource.createPixelMap();
        } finally {
          if (imageSource != undefined) {
            imageSource.release();
          }
        }
      }
    }
    if (notificationDetails.largeIcon && notificationDetails.largeIconSource != undefined) {
      let iconWidth: number = LocalNotificationsConstants.LARGE_ICON_WIDTH;
      let iconHeight: number = LocalNotificationsConstants.LARGE_ICON_WIDTH;
      let largeIcon: image.PixelMap | undefined = await Utils.getPixelMapFromSource(
        notificationDetails.largeIcon,
        notificationDetails.largeIconSource,
        iconHeight,
        iconWidth,
        this.appContext);
      if (largeIcon) {
        result.largeIcon = largeIcon;
      } else {
        Log.e(TAG, 'initBasicNotificationRequest-->get largeIcon failed');
      }
    }
  }

  private applyProgressTemplate(result: NRequest, notificationDetails: NotificationDetails): void {
    let progress: number = notificationDetails.progress ?? 0;
    let title: string = this.contentFactory.formatStyledText(
      notificationDetails.styleInformation?.htmlFormatTitle, notificationDetails.title ?? '');
    let fileName: string = this.contentFactory.formatStyledText(
      notificationDetails.styleInformation?.htmlFormatBody, notificationDetails.body ?? '');
    const publishableTitle: string = title.length > 0 ? title : '\u200B';
    const publishableFileName: string = fileName.length > 0 ? fileName : '\u200B';
    result.template = {
      name: LocalNotificationsConstants.NOTIFICATION_TEMPLATE_DOWNLOAD,
      data: {
        title: publishableTitle,
        fileName: publishableFileName,
        progressValue: progress
      }
    };
  }

  private async initBasicNotificationRequest(notificationContent: NContent,
    notificationDetails: NotificationDetails): Promise<NRequest> {
    let result: NRequest | undefined = undefined;
    try {
      let actionButtons: NActionButton[] = await this.buildActionButtons(notificationDetails);
      result = {
        content: notificationContent,
        wantAgent: await this.createWantAgentForStartAbility(undefined, notificationDetails),
        notificationFlags: {
          soundEnabled: notificationDetails.playSound === undefined ?
            undefined : (notificationDetails.playSound ? 1 : 0),
          vibrationEnabled: notificationDetails.enableVibration === undefined ?
            undefined : (notificationDetails.enableVibration ? 1 : 0)
        }
      };
      let resolvedSound: string | undefined = await this.resolveNotificationSound(notificationDetails);
      if (resolvedSound) {
        result.sound = resolvedSound;
      }
      await this.applyOptionalRequestFields(result, notificationDetails);
      if (actionButtons.length > 0) {
        result.actionButtons = actionButtons;
      }
      await this.loadRequestIcons(result, notificationDetails);
      if (notificationDetails.showProgress) {
        let isSupportProgress: boolean = await notificationManager.isSupportTemplate(
          LocalNotificationsConstants.NOTIFICATION_TEMPLATE_DOWNLOAD);
        if (!isSupportProgress) {
          throw new Error('progress notification template is not supported');
        }
        this.applyProgressTemplate(result, notificationDetails);
      }
      return result;
    } catch (err) {
      this.releaseNotificationRequestIcons(result);
      Log.e(TAG, 'initBasicNotificationRequest-->err msg: ' + JSON.stringify(err));
      throw err instanceof Error ? err : new Error(String(err));
    }
  }

  /**
   * Resolves Dart sound payload to a NotificationRequest.sound value.
   *
   * Raw resources are looked up under resources/rawfile (aligned with Android res/raw).
   * URI sounds are passed through unchanged.
   */
  private async resolveNotificationSound(notificationDetails: NotificationDetails): Promise<string | undefined> {
    let sound: string | undefined = notificationDetails.sound;
    if (sound == undefined || sound.length === 0) {
      return undefined;
    }
    let soundSource: SoundSource | undefined = notificationDetails.soundSource;
    if (soundSource === SoundSource.Uri || (soundSource == undefined && this.isUriSound(sound))) {
      return sound;
    }
    let rawfileName: string | undefined = await this.resolveRawfileSoundName(sound);
    if (rawfileName == undefined) {
      throw new Error('invalid_sound: ' +
        INVALID_RAW_SOUND_ERROR_MESSAGE.replace('%s', sound));
    }
    return rawfileName;
  }

  private isUriSound(sound: string): boolean {
    return sound.includes('://') || sound.startsWith('/');
  }

  private async resolveRawfileSoundName(resourceName: string): Promise<string | undefined> {
    if (resourceName.includes('.')) {
      if (await this.rawfileExists(resourceName)) {
        return resourceName;
      }
      return undefined;
    }
    for (let extension of RAW_SOUND_EXTENSIONS) {
      let candidate: string = resourceName + extension;
      if (await this.rawfileExists(candidate)) {
        return candidate;
      }
    }
    if (await this.rawfileExists(resourceName)) {
      return resourceName;
    }
    return undefined;
  }

  private async rawfileExists(path: string): Promise<boolean> {
    let uiAbility: UIAbility | undefined = this.appContext.getAbility();
    if (uiAbility == undefined) {
      return false;
    }
    try {
      let descriptor = await uiAbility.context.resourceManager.getRawFd(path);
      try {
        fs.closeSync(descriptor.fd);
      } catch (closeErr) {
        Log.w(TAG, 'rawfileExists-->close fd failed: ' + JSON.stringify(closeErr));
      }
      return true;
    } catch (err) {
      return false;
    }
  }

  private async createWantAgentForStartAbility(actionId?: string,
    notificationDetails?: NotificationDetails): Promise<Object> {
    let parameters: Record<string, Object> = {};
    if (notificationDetails?.id != undefined) {
      parameters[LocalNotificationsConstants.NOTIFICATION_ID] = notificationDetails.id;
    }
    parameters[LocalNotificationsConstants.ACTION_ID] = actionId ?? '';
    parameters[LocalNotificationsConstants.PAYLOAD] = notificationDetails?.payload ?? '';
    let wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: bundleManager.getBundleInfoForSelfSync(
            bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)?.name,
          abilityName: LocalNotificationsConstants.ABILITY_NAME,
          action: LocalNotificationsConstants.ACTION_SELECTION_NOTIFICATION,
          parameters: parameters
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0
    };
    return await wantAgent.getWantAgent(wantAgentInfo);
  }
}
