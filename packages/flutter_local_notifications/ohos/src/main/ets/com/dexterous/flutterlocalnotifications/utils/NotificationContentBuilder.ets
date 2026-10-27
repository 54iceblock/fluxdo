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

import { image } from '@kit.ImageKit';
import { notificationManager } from '@kit.NotificationKit';

/** Parsed notification content fields before mapping to [notificationManager.NotificationContent]. */
export interface NotificationContentResult {
  notificationContentType: notificationManager.ContentType;
  normal?: notificationManager.NotificationBasicContent;
  longText?: notificationManager.NotificationLongTextContent;
  multiLine?: notificationManager.NotificationMultiLineContent;
  picture?: notificationManager.NotificationPictureContent;
  customLiveView?: notificationManager.NotificationSystemLiveViewContent;
}

/** Configuration for long-text notification content. */
export interface LongTextContentConfig {
  title: string;
  body: string;
  briefText: string;
  expandedTitle: string;
  longText: string;
  subText?: string;
}

/** Configuration for multi-line (inbox) notification content. */
export interface MultiLineContentConfig {
  title: string;
  body: string;
  longTitle: string;
  briefText: string;
  lines: string[];
  subText?: string;
}

/** Configuration for picture notification content. */
export interface PictureContentConfig {
  title: string;
  body: string;
  expandedTitle: string;
  briefText: string;
  picture: image.PixelMap;
  subText?: string;
}

/** Configuration for system live-view notification content. */
export interface LiveViewContentConfig {
  title: string;
  text: string;
  typeCode: number;
  initialTime?: number;
  isCountDown?: boolean;
  isPaused?: boolean;
  isInTitle?: boolean;
}

/** Invisible placeholder: OpenHarmony publish rejects empty title/text. */
const OHOS_EMPTY_TEXT_PLACEHOLDER: string = '\u200B';

function ensureOhosPublishableText(value: string): string {
  return value.length > 0 ? value : OHOS_EMPTY_TEXT_PLACEHOLDER;
}

/** Builds OHOS [notificationManager.NotificationContent] payloads from Dart notification details. */
export class NotificationContentBuilder {
  /**
   * Builds basic text notification content.
   *
   * @param title Notification title.
   * @param body Notification body text.
   * @param subText Optional additional text line.
   * @returns Content wrapper or undefined when required fields are empty.
   */
  initBasicNotificationContent(title: string, body: string,
    subText?: string): NotificationContentResult | undefined {
    const normalizedTitle: string = title ?? '';
    const normalizedBody: string = body ?? '';
    if (!normalizedTitle && !normalizedBody) {
      return undefined;
    }
    let basicContent: notificationManager.NotificationBasicContent = {
      title: ensureOhosPublishableText(normalizedTitle),
      text: ensureOhosPublishableText(normalizedBody),
      additionalText: subText ?? ''
    };
    let result: NotificationContentResult = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: basicContent
    };
    return result;
  }

  /**
   * Builds long-text (expanded) notification content.
   *
   * @param config Long-text content configuration.
   * @returns Content wrapper or undefined when required fields are empty.
   */
  initNotificationLongTextContent(config: LongTextContentConfig): NotificationContentResult | undefined {
    if (!config.title || !config.body || !config.longText || !config.briefText || !config.expandedTitle) {
      return undefined;
    }
    let result: NotificationContentResult = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_LONG_TEXT,
      longText: {
        title: config.title,
        text: config.body,
        additionalText: config.subText ?? '',
        expandedTitle: config.expandedTitle,
        longText: config.longText,
        briefText: config.briefText
      }
    };
    return result;
  }

  /**
   * Builds multi-line (inbox) notification content.
   *
   * @param config Multi-line content configuration.
   * @returns Content wrapper or undefined when required fields are empty.
   */
  initNotificationMultiLineContent(config: MultiLineContentConfig): NotificationContentResult | undefined {
    if (!config.title || !config.body || !config.longTitle || !config.briefText || !config.lines) {
      return undefined;
    }
    let result: NotificationContentResult = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_MULTILINE,
      multiLine: {
        title: config.title,
        text: config.body,
        additionalText: config.subText ?? '',
        longTitle: config.longTitle,
        briefText: config.briefText,
        lines: config.lines
      }
    };
    return result;
  }

  /**
   * Builds picture notification content.
   *
   * @param config Picture content configuration.
   * @returns Content wrapper or undefined when required fields are empty.
   */
  initNotificationPictureContent(config: PictureContentConfig): NotificationContentResult | undefined {
    if (!config.title || !config.body || !config.expandedTitle || !config.briefText || !config.picture) {
      return undefined;
    }
    let notificationPictureContent: notificationManager.NotificationPictureContent = {
      title: config.title,
      text: config.body,
      additionalText: config.subText ?? '',
      briefText: config.briefText,
      expandedTitle: config.expandedTitle,
      picture: config.picture
    };
    let result: NotificationContentResult = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_PICTURE,
      picture: notificationPictureContent
    };
    return result;
  }

  /**
   * Builds system live-view notification content.
   *
   * @param config Live-view content configuration.
   * @returns Content wrapper or undefined when required fields are empty.
   */
  initNotificationSystemLiveViewContent(config: LiveViewContentConfig): NotificationContentResult | undefined {
    if (!config.title || !config.text || config.typeCode === undefined || config.typeCode === null) {
      return undefined;
    }
    let notificationSystemLiveViewContent: notificationManager.NotificationSystemLiveViewContent = {
      typeCode: config.typeCode,
      title: config.title,
      text: config.text,
      time: {
        initialTime: config.initialTime,
        isCountDown: config.isCountDown,
        isPaused: config.isPaused,
        isInTitle: config.isInTitle,
      }
    };
    let result: NotificationContentResult = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
      customLiveView: notificationSystemLiveViewContent
    };
    return result;
  }
}

/** Stateless notification content builder singleton (no cached resources). */
export const notificationContentBuilder: NotificationContentBuilder = new NotificationContentBuilder();
