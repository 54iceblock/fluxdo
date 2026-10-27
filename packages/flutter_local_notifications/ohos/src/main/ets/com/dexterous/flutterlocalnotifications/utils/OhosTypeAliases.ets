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
import { notificationManager } from '@kit.NotificationKit';

/** Notification content including optional system live-view payload. */
export interface NContent extends notificationManager.NotificationContent {
  customLiveView?: notificationManager.NotificationSystemLiveViewContent;
}

/** Shorthand for [notificationManager.NotificationRequest]. */
export type NRequest = notificationManager.NotificationRequest;

/** Shorthand for [notificationManager.NotificationSlot]. */
export type NSlot = notificationManager.NotificationSlot;

/** Shorthand for [notificationManager.NotificationActionButton]. */
export type NActionButton = notificationManager.NotificationActionButton;

/** Shorthand for [reminderAgentManager.ReminderRequestTimer]. */
export type ReminderTimer = reminderAgentManager.ReminderRequestTimer;

/** Shorthand for [reminderAgentManager.ReminderRequestCalendar]. */
export type ReminderCalendar = reminderAgentManager.ReminderRequestCalendar;

/** Shorthand for [reminderAgentManager.ReminderRequest]. */
export type ReminderRequest = reminderAgentManager.ReminderRequest;

/** Shorthand for [reminderAgentManager.ReminderInfo]. */
export type ReminderInfo = reminderAgentManager.ReminderInfo;

/** Platform specifics map from Dart MethodChannel. */
export type PlatformSpecificsMap = Map<string, Object>;
