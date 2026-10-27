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

import 'person.dart';

/// Represents a message used in OHOS messaging-style notifications.
class OhosMessage {
  /// Constructs an instance of [OhosMessage].
  const OhosMessage(
    this.text,
    this.timestamp,
    this.person, {
    this.dataMimeType,
    this.dataUri,
  });

  /// The message text.
  final String text;

  /// Time at which the message arrived.
  final DateTime timestamp;

  /// Person that sent this message.
  final OhosPerson? person;

  /// MIME type for this message context when [dataUri] is provided.
  final String? dataMimeType;

  /// Uri containing the content.
  final String? dataUri;
}
