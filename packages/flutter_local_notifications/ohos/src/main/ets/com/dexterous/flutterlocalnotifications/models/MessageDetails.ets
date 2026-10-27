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

import { PersonDetails } from './PersonDetails';

export class MessageDetails {
  public text: string;
  public timestamp?: number;
  public person?: PersonDetails;
  public dataMimeType?: string;
  public dataUri?: string;

  /** Creates a message entry for messaging-style notifications. */
  constructor(text: string, timestamp?: number, person?: PersonDetails, dataMimeType?: string, dataUri?: string) {
    this.text = text;
    this.timestamp = timestamp;
    this.person = person;
    this.dataMimeType = dataMimeType;
    this.dataUri = dataUri;
  }
}
