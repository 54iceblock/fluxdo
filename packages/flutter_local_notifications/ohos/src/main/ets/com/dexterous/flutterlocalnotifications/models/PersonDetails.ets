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

export class PersonDetails {
  public bot?: boolean;
  public important?: boolean;
  public key?: string;
  public name?: string;
  public uri?: string;

  /** Creates a person record used by messaging-style notifications. */
  constructor(bot?: boolean, important?: boolean, key?: string, name?: string, uri?: string) {
    this.bot = bot;
    this.important = important;
    this.key = key;
    this.name = name;
    this.uri = uri;
  }
}
