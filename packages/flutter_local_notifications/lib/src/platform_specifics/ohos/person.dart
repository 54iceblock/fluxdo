/*
 * Copyright (c) 2024 Shenzhen Kaihong Digital Industry Development Co., Ltd.
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

/// Details of a person used in OHOS messaging-style notifications.
class OhosPerson {
  /// Constructs an instance of [OhosPerson].
  const OhosPerson({
    this.bot = false,
    this.important = false,
    this.key,
    this.name,
    this.uri,
  });

  /// Whether this person represents a machine rather than a human.
  final bool bot;

  /// Whether this is an important person.
  final bool important;

  /// Unique identifier for this person.
  final String? key;

  /// Name of this person.
  final String? name;

  /// Uri for this person.
  final String? uri;
}
