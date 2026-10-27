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

export class LocalNotificationsConstants {
  static readonly INITIALIZE_METHOD: string = "initialize";
  static readonly GET_CALLBACK_HANDLE_METHOD: string = "getCallbackHandle";
  static readonly ARE_NOTIFICATIONS_ENABLED_METHOD: string = "areNotificationsEnabled";
  static readonly CAN_SCHEDULE_EXACT_NOTIFICATIONS_METHOD: string = "canScheduleExactNotifications";
  static readonly CREATE_NOTIFICATION_CHANNEL_GROUP_METHOD: string = "createNotificationChannelGroup";
  static readonly DELETE_NOTIFICATION_CHANNEL_GROUP_METHOD: string = "deleteNotificationChannelGroup";
  static readonly CREATE_NOTIFICATION_CHANNEL_METHOD: string = "createNotificationChannel";
  static readonly DELETE_NOTIFICATION_CHANNEL_METHOD: string = "deleteNotificationChannel";
  // Android-only MethodChannel names below; not registered on OHOS (see README.OpenHarmony.md).
  static readonly GET_ACTIVE_NOTIFICATION_MESSAGING_STYLE_METHOD: string = "getActiveNotificationMessagingStyle";
  static readonly GET_NOTIFICATION_CHANNELS_METHOD: string = "getNotificationChannels";
  static readonly START_FOREGROUND_SERVICE: string = "startForegroundService";
  static readonly STOP_FOREGROUND_SERVICE: string = "stopForegroundService";
  static readonly PENDING_NOTIFICATION_REQUESTS_METHOD: string = "pendingNotificationRequests";
  static readonly GET_ACTIVE_NOTIFICATIONS_METHOD: string = "getActiveNotifications";
  static readonly SHOW_METHOD: string = "show";
  static readonly CANCEL_METHOD: string = "cancel";
  static readonly CANCEL_ALL_METHOD: string = "cancelAll";
  static readonly CANCEL_ALL_PENDING_NOTIFICATIONS_METHOD: string = "cancelAllPendingNotifications";
  static readonly ZONED_SCHEDULE_METHOD: string = "zonedSchedule";
  static readonly PERIODICALLY_SHOW_METHOD: string = "periodicallyShow";
  static readonly PERIODICALLY_SHOW_WITH_DURATION_METHOD: string = "periodicallyShowWithDuration";
  static readonly GET_NOTIFICATION_APP_LAUNCH_DETAILS_METHOD: string = "getNotificationAppLaunchDetails";
  static readonly REQUEST_NOTIFICATIONS_PERMISSION_METHOD: string = "requestNotificationsPermission";
  static readonly REQUEST_EXACT_ALARMS_PERMISSION_METHOD: string = "requestExactAlarmsPermission";
  static readonly REQUEST_FULL_SCREEN_INTENT_PERMISSION_METHOD: string = "requestFullScreenIntentPermission";
  static readonly RECEIVE_NOTIFICATION_RESPONSE: string = "didReceiveNotificationResponse";
  static readonly GET_LOCAL_TIMEZONE: string = "getLocalTimezone";
  static readonly ADD_NOTIFICATION_SLOT_METHOD: string = "addNotificationSlot";
  static readonly DELETE_NOTIFICATION_SLOT_METHOD: string = "deleteNotificationSlot";
  static readonly GET_NOTIFICATION_SLOT_METHOD: string = "getNotificationSlots";

  static readonly ERROR_UNEXPECTED: string = "unexpected_error";
  static readonly ERROR_INVALID_ICON: string = "invalid_icon";
  static readonly ERROR_INVALID_BIG_PICTURE: string = "invalid_big_picture";
  static readonly ERROR_INVALID_SOUND: string = "invalid_sound";
  static readonly ERROR_INVALID_PARAMETERS: string = "invalid_parameters";
  static readonly ERROR_NOTIFICATION_PUBLISH_FAILED: string = "notification_publish_failed";
  static readonly ERROR_REMINDER_PUBLISH_FAILED: string = "reminder_publish_failed";
  static readonly ERROR_INITIALIZE_FAILED: string = "initialize_failed";
  static readonly ERROR_SLOT_OPERATION_FAILED: string = "slot_operation_failed";
  static readonly ERROR_FULL_SCREEN_INTENT_NOT_SUPPORTED: string = "full_screen_intent_not_supported";

  static readonly ID: string = "id";
  static readonly TITLE: string = "title";
  static readonly BODY: string = "body";
  static readonly INPUTS: string = "inputs";
  static readonly PAYLOAD: string = "payload";
  static readonly ACTION: string = "action";
  /** Dart periodicallyShow() argument key. */
  static readonly REPEAT_INTERVAL: string = "repeatInterval";
  /** @deprecated Legacy alias; use [REPEAT_INTERVAL]. */
  static readonly REPORT_INTERVAL: string = "repeatInterval";
  static readonly REPEAT_INTERVAL_MILLISECONDS: string = "repeatIntervalMilliseconds";
  static readonly TIMEZONE_NAME: string = "timeZoneName";
  static readonly SCHEDULED_DATETIME: string = "scheduledDateTime";
  static readonly MATCH_DATETIME_COMPONENTS: string = "matchDateTimeComponents";
  static readonly PLATFORM_SPECIFICS: string = "platformSpecifics";
  static readonly SUBTEXT: string = "subText";
  static readonly AUTO_CANCEL: string = "autoCancel";
  static readonly ONGOING: string = "ongoing";
  static readonly ONLY_ALERT_ONCE: string = "onlyAlertOnce";
  static readonly SHOW_WHEN: string = "showWhen";
  static readonly WHEN: string = "when";
  static readonly STYLE: string = "style";
  static readonly ACTIONS: string = "actions";
  static readonly TAG: string = "tag";
  static readonly GROUP_KEY: string = "groupKey";
  static readonly SLOT_TYPE: string = "slotType";
  static readonly BADGE_NUMBER: string = "badgeNumber";
  static readonly PLAY_SOUND: string = "playSound";
  static readonly ENABLE_VIBRATION: string = "enableVibration";
  static readonly SILENT: string = "silent";
  static readonly STYLE_INFORMATION: string = "styleInformation";
  static readonly HTML_FORMAT_TITLE: string = "htmlFormatTitle";
  static readonly HTML_FORMAT_CONTENT: string = "htmlFormatContent";
  static readonly CONTENT_TITLE: string = "contentTitle";
  static readonly SUMMARY_TEXT: string = "summaryText";
  static readonly LARGE_ICON: string = "largeIcon";
  static readonly LARGE_ICON_SOURCE: string = "largeIconBitmapSource";
  static readonly BIG_PICTURE: string = "bigPicture";
  static readonly BIG_PICTURE_SOURCE: string = "bigPictureBitmapSource";
  static readonly BIG_TEXT: string = "bigText";
  static readonly TEXT_LINES: string = "lines";
  static readonly SHOW_PROGRESS: string = "showProgress";
  static readonly MAX_PROGRESS: string = "maxProgress";
  static readonly PROGRESS: string = "progress";
  static readonly ACTION_SELECTION_NOTIFICATION: string = "SELECT_NOTIFICATION";
  static readonly TIMEOUT_AFTER: string = "timeoutAfter";
  static readonly USES_CHRONOMETER: string = "usesChronometer";
  static readonly CHRONOMETER_COUNTDOWN: string = "chronometerCountDown";
  static readonly FULL_SCREEN: string = "fullScreenIntent";
  static readonly ICON: string = "icon";
  static readonly SLOT_DESC: string = "slotDesc";
  static readonly SLOT_SHOW_BADGE: string = "slotShowBadge";

  static readonly HTML_FORMAT_CONTENT_TITLE: string = "htmlFormatContentTitle";
  static readonly HTML_FORMAT_SUMMARY_TEXT: string = "htmlFormatSummaryText";
  static readonly HTML_FORMAT_BIG_TEXT: string = "htmlFormatBigText";
  static readonly HTML_FORMAT_LINES: string = "htmlFormatLines";

  static readonly DESCRIPTION: string = "description";
  static readonly SHOW_BADGE: string = "showBadge";
  static readonly IMPORTANCE: string = "importance";
  static readonly SLOT_ACTION: string = "slotAction";
  static readonly LOCKSCREEN_VISIBILITY: string = "lockscreenVisibility";
  static readonly BYPASS_DND: string = "bypassDnd";
  static readonly SOUND: string = "sound";
  static readonly SOUND_SOURCE: string = "soundSource";
  static readonly VIBRATION_PATTERN: string = "vibrationPattern";
  static readonly IS_FLOAT_ICON: string = "isFloatingIcon";

  static readonly COLORIZED: string = "colorized";
  static readonly ENABLE_LIGHTS: string = "enableLights";
  static readonly LED_COLOR_ALPHA: string = "ledColorAlpha";
  static readonly LED_COLOR_RED: string = "ledColorRed";
  static readonly LED_COLOR_GREEN: string = "ledColorGreen";
  static readonly LED_COLOR_BLUE: string = "ledColorBlue";
  static readonly LED_COLOR: string = "ledColor";
  static readonly COLOR_ALPHA: string = "colorAlpha";
  static readonly COLOR_RED: string = "colorRed";
  static readonly COLOR_GREEN: string = "colorGreen";
  static readonly COLOR_BLUE: string = "colorBlue";


  static readonly NOTIFICATION_ID: string = "notificationId";
  static readonly NOTIFICATION_TAG: string = "notificationTag";
  static readonly ACTION_ID: string = "actionId";
  static readonly KEY: string = "key";
  static readonly INPUT: string = "input";
  static readonly LABEL: string = "label";
  static readonly CHOICES: string = "choices";
  static readonly ALLOW_FREE_FORM_INPUT: string = "allowFreeFormInput";
  static readonly ALLOWED_MIME_TYPE: string = "allowedMimeType";
  static readonly ALLOWED_MIME_TYPES: string = "allowedMimeTypes";
  static readonly CHANNEL_ID: string = "channelId";
  static readonly TEXT: string = "text";
  static readonly TIMESTAMP: string = "timestamp";
  static readonly BOT: string = "bot";
  static readonly IMPORTANT: string = "important";
  static readonly NAME: string = "name";
  static readonly URI: string = "uri";
  static readonly PERSON: string = "person";
  static readonly CONVERSATION_TITLE: string = "conversationTitle";
  static readonly GROUP_CONVERSATION: string = "groupConversation";
  static readonly MESSAGES: string = "messages";
  static readonly DATA_MIME_TYPE: string = "dataMimeType";
  static readonly DATA_URI: string = "dataUri";
  static readonly DATA: string = "data";
  static readonly NOTIFICATION_RESPONSE_TYPE: string = "notificationResponseType";

  static readonly DEFAULT_ICON: string = "defaultIcon";
  static readonly NOTIFICATION_RESPONSE: string = "notificationResponse";
  static readonly NOTIFICATION_LAUNCHED_APP: string = "notificationLaunchedApp";

  static readonly ABILITY_NAME: string = "EntryAbility";
  static readonly DAY: string = "day";
  static readonly DATE: string = "date";
  static readonly MONTH: string = "month";
  static readonly NOTIFICATION_TEMPLATE_DOWNLOAD: string = "downloadTemplate";

  static readonly LARGE_ICON_WIDTH: number = 64;
  static readonly SMALL_ICON_WIDTH: number = 48;
  static readonly BIG_PICTURE_WIDTH: number = 800;
  static readonly BIG_PICTURE_HEIGHT: number = 400;
}
