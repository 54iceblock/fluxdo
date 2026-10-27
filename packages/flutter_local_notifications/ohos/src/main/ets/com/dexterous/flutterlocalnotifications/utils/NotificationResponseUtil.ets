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

import { Log } from '@ohos/flutter_ohos';
import Want from '@ohos.app.ability.Want';
import { LocalNotificationsConstants } from '../LocalNotificationsConstants';

const TAG: string = 'NotificationResponseUtil';

/** Builds notification response maps from Ability Want parameters. */
export class NotificationResponseUtil {
  /**
   * Extracts notification tap response fields from a launch or action Want.
   *
   * @param want Incoming Want from notification action or cold start.
   * @returns Response map for Dart MethodChannel forwarding.
   */
  static extractNotificationResponseMap(want: Want | undefined): Map<string, Object> {
    let map: Map<string, Object> = new Map<string, Object>();
    if (!want) {
      Log.w(TAG, 'extractNotificationResponseMap-->want is undefined');
      return map;
    }
    let parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters) {
      map.set(LocalNotificationsConstants.NOTIFICATION_ID, parameters[LocalNotificationsConstants.NOTIFICATION_ID]);
      map.set(LocalNotificationsConstants.NOTIFICATION_TAG, parameters[LocalNotificationsConstants.NOTIFICATION_TAG]);
      map.set(LocalNotificationsConstants.ACTION_ID, parameters[LocalNotificationsConstants.ACTION_ID]);
      map.set(LocalNotificationsConstants.PAYLOAD, parameters[LocalNotificationsConstants.PAYLOAD]);
      if (parameters[LocalNotificationsConstants.KEY]) {
        map.set(LocalNotificationsConstants.INPUT, parameters[LocalNotificationsConstants.DATA]);
      }
      map.set(LocalNotificationsConstants.NOTIFICATION_RESPONSE_TYPE,
        parameters[LocalNotificationsConstants.ACTION_ID] != null &&
          parameters[LocalNotificationsConstants.ACTION_ID] !== '' ? 1 : 0);
    }
    return map;
  }
}
