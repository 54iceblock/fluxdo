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

import '../message.dart';
import '../person.dart';
import 'default_style_information.dart';

/// Used to pass the content for an OHOS notification displayed using the
/// messaging style.
class OhosMessagingStyleInformation extends OhosDefaultStyleInformation {
  /// Constructs an instance of [OhosMessagingStyleInformation].
  OhosMessagingStyleInformation(
    this.person, {
    this.conversationTitle,
    this.groupConversation,
    this.messages,
    bool htmlFormatContent = false,
    bool htmlFormatTitle = false,
  }) : super(htmlFormatContent, htmlFormatTitle);

  /// The person displayed for messages sent by the user.
  final OhosPerson person;

  /// The title to be displayed on this conversation.
  final String? conversationTitle;

  /// Whether this conversation notification represents a group.
  final bool? groupConversation;

  /// Messages to be displayed by this notification.
  final List<OhosMessage>? messages;
}
