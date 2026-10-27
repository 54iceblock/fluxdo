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

import { LocalNotificationsConstants } from '../LocalNotificationsConstants';

export class NotificationAction {
  id?: string;
  title: string;
  actionInputs?: NotificationActionInput[];

  /**
   * Parses a notification action from a MethodChannel map payload.
   *
   * @param map Action fields from Dart platform specifics.
   */
  constructor(map: Map<string, Object>) {
    let idValue: Object | undefined = map.get(LocalNotificationsConstants.ID);
    this.id = idValue ? String(idValue) : undefined;
    let titleValue: Object | undefined = map.get(LocalNotificationsConstants.TITLE);
    this.title = titleValue ? String(titleValue) : '';
    let inputs: Map<string, Object>[] | undefined =
      map.get(LocalNotificationsConstants.INPUTS) as (Map<string, Object>[] | undefined);
    if (inputs && inputs.length > 0) {
      this.actionInputs = [];
      for (let item of inputs) {
        item && this.actionInputs.push(new NotificationActionInput(item));
      }
    }
  }
}

export class NotificationActionInput {
  choices?: string[];
  allowFreeFormInput?: boolean;
  label?: string;
  allowedMimeTypes?: string[];

  /**
   * Parses a notification action input from a MethodChannel map payload.
   *
   * @param map Action input fields from Dart platform specifics.
   */
  constructor(map: Map<string, Object>) {
    this.choices = NotificationActionInput.readStringList(map.get(LocalNotificationsConstants.CHOICES));
    let allowFreeForm: Object | undefined = map.get(LocalNotificationsConstants.ALLOW_FREE_FORM_INPUT);
    this.allowFreeFormInput = typeof allowFreeForm === 'boolean' ? allowFreeForm : undefined;
    let labelValue: Object | undefined = map.get(LocalNotificationsConstants.LABEL);
    this.label = typeof labelValue === 'string' ? labelValue : undefined;
    let mimeTypes: string[] = NotificationActionInput.readStringList(
      map.get(LocalNotificationsConstants.ALLOWED_MIME_TYPE));
    if (mimeTypes.length == 0) {
      mimeTypes = NotificationActionInput.readStringList(map.get(LocalNotificationsConstants.ALLOWED_MIME_TYPES));
    }
    this.allowedMimeTypes = mimeTypes.length > 0 ? mimeTypes : undefined;
  }

  private static readStringList(value: Object | undefined): string[] {
    if (!value || !Array.isArray(value)) {
      return [];
    }
    let result: string[] = [];
    for (let item of value as Object[]) {
      if (item != undefined) {
        result.push(String(item));
      }
    }
    return result;
  }
}
