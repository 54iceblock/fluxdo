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
import { Log } from '@ohos/flutter_ohos';
import { LocalNotificationsConstants } from './LocalNotificationsConstants';
import NotificationDetails from './models/NotificationDetails';
import { BigPictureStyleInformation } from './models/styles/BigPictureStyleInformation';
import { BigTextStyleInformation } from './models/styles/BigTextStyleInformation';
import { DefaultStyleInformation } from './models/styles/DefaultStyleInformation';
import { InBoxStyleInformation } from './models/styles/InBoxStyleInformation';
import { LiveViewStyleInformation } from './models/styles/LiveViewStyleInformation';
import { MessagingStyleInformation } from './models/styles/MessagingStyleInformation';
import { NotificationStyle } from './models/styles/NotificationStyle';
import { AppContext } from './utils/AppContext';
import { NContent } from './utils/OhosTypeAliases';
import { notificationContentBuilder, NotificationContentResult } from './utils/NotificationContentBuilder';
import { Utils } from './utils/Utils';

const TAG: string = 'NotificationContentFactory';

/** Builds OHOS notification content from parsed [NotificationDetails]. */
export class NotificationContentFactory {
  private readonly appContext: AppContext;

  constructor(appContext: AppContext) {
    this.appContext = appContext;
  }

  /**
   * Applies HTML formatting when enabled, otherwise returns plain text.
   *
   * @param htmlFormat Whether HTML formatting is requested.
   * @param text Source text to format.
   * @returns Formatted text string.
   */
  formatStyledText(htmlFormat: boolean | undefined, text: string): string {
    return htmlFormat ? Utils.fromHtml(text) : text;
  }

  /**
   * Formats reminder title or body fields with optional HTML processing.
   *
   * @param notificationDetails Parsed notification payload.
   * @param field Field selector for title or body.
   * @returns Formatted reminder field text.
   */
  formatReminderField(notificationDetails: NotificationDetails, field: 'title' | 'body'): string {
    let htmlFormat: boolean | undefined = field === 'title'
      ? notificationDetails.styleInformation?.htmlFormatTitle
      : notificationDetails.styleInformation?.htmlFormatBody;
    let text: string | undefined = field === 'title' ? notificationDetails.title : notificationDetails.body;
    return this.formatStyledText(htmlFormat, text ?? '') ?? '';
  }

  /**
   * Maps a builder result into OHOS notification content structure.
   *
   * @param result Content builder output.
   * @returns OHOS notification content or undefined when input is empty.
   */
  toNotificationContent(result: NotificationContentResult | undefined): NContent | undefined {
    if (result == undefined) {
      return undefined;
    }
    let content: NContent = {
      notificationContentType: result.notificationContentType,
    } as NContent;
    if (result.normal != undefined) {
      content.normal = result.normal;
    }
    if (result.longText != undefined) {
      content.longText = result.longText;
    }
    if (result.multiLine != undefined) {
      content.multiLine = result.multiLine;
    }
    if (result.picture != undefined) {
      content.picture = result.picture;
    }
    if (result.customLiveView != undefined) {
      content.customLiveView = result.customLiveView;
    }
    return content;
  }

  /**
   * Builds OHOS notification content from parsed notification style details.
   *
   * @param notificationDetails Parsed notification payload from Dart.
   * @returns Notification content or undefined for unsupported styles.
   */
  async buildNotificationContent(notificationDetails: NotificationDetails): Promise<NContent | undefined> {
    if (notificationDetails.style == NotificationStyle.DefaultStyle) {
      let styleInformation: DefaultStyleInformation =
        notificationDetails.styleInformation as DefaultStyleInformation;
      let title: string = this.formatStyledText(
        styleInformation.htmlFormatTitle, notificationDetails.title ?? '');
      let body: string = this.formatStyledText(
        styleInformation.htmlFormatBody, notificationDetails.body ?? '');
      return this.toNotificationContent(notificationContentBuilder.initBasicNotificationContent(
        title, body, notificationDetails.subText));
    }
    if (notificationDetails.style == NotificationStyle.BigText) {
      return this.buildBigTextContent(notificationDetails);
    }
    if (notificationDetails.style == NotificationStyle.Inbox) {
      return this.buildInboxContent(notificationDetails);
    }
    if (notificationDetails.style == NotificationStyle.BigPicture) {
      return await this.buildBigPictureContent(notificationDetails);
    }
    if (notificationDetails.style == NotificationStyle.Messaging) {
      return this.buildMessagingContent(notificationDetails);
    }
    if (notificationDetails.style == NotificationStyle.LiveView) {
      return this.buildLiveViewContent(notificationDetails);
    }
    return undefined;
  }

  /**
   * Builds long-text (BigText style) notification content.
   *
   * @param notificationDetails Parsed notification payload.
   * @returns Notification content or undefined when required fields are missing.
   */
  buildBigTextContent(notificationDetails: NotificationDetails): NContent | undefined {
    let styleInformation: BigTextStyleInformation =
      notificationDetails.styleInformation as BigTextStyleInformation;
    return this.toNotificationContent(notificationContentBuilder.initNotificationLongTextContent({
      title: this.formatStyledText(styleInformation.htmlFormatTitle, notificationDetails.title),
      body: this.formatStyledText(styleInformation.htmlFormatBody, notificationDetails.body),
      briefText: this.formatStyledText(styleInformation.htmlFormatSummaryText, styleInformation.summaryText),
      expandedTitle: this.formatStyledText(styleInformation.htmlFormatContentTitle, styleInformation.contentTitle),
      longText: this.formatStyledText(styleInformation.htmlFormatBigText, styleInformation.bigText),
      subText: notificationDetails.subText,
    }));
  }

  /**
   * Builds multi-line (Inbox style) notification content.
   *
   * @param notificationDetails Parsed notification payload.
   * @returns Notification content or undefined when required fields are missing.
   */
  buildInboxContent(notificationDetails: NotificationDetails): NContent | undefined {
    let styleInformation: InBoxStyleInformation =
      notificationDetails.styleInformation as InBoxStyleInformation;
    let linesNew: string[] = styleInformation.htmlFormatLines ?
      styleInformation.lines.map((line: string) => Utils.fromHtml(line)) : styleInformation.lines;
    return this.toNotificationContent(notificationContentBuilder.initNotificationMultiLineContent({
      title: this.formatStyledText(styleInformation.htmlFormatTitle, notificationDetails.title),
      body: this.formatStyledText(styleInformation.htmlFormatBody, notificationDetails.body),
      longTitle: this.formatStyledText(styleInformation.htmlFormatContentTitle, styleInformation.contentTitle),
      briefText: this.formatStyledText(styleInformation.htmlFormatSummaryText, styleInformation.summaryText),
      lines: linesNew,
      subText: notificationDetails.subText,
    }));
  }

  /**
   * Builds picture (BigPicture style) notification content.
   *
   * @param notificationDetails Parsed notification payload.
   * @returns Notification content or undefined when picture loading fails.
   */
  async buildBigPictureContent(notificationDetails: NotificationDetails): Promise<NContent | undefined> {
    let styleInformation: BigPictureStyleInformation =
      notificationDetails.styleInformation as BigPictureStyleInformation;
    if (!styleInformation.bigPicture || !styleInformation.bigPictureSource) {
      return undefined;
    }
    let bigPicturePixelMap: image.PixelMap | undefined = await Utils.getPixelMapFromSource(
      styleInformation.bigPicture, styleInformation.bigPictureSource,
      LocalNotificationsConstants.BIG_PICTURE_HEIGHT, LocalNotificationsConstants.BIG_PICTURE_WIDTH,
      this.appContext);
    if (!bigPicturePixelMap) {
      Log.e(TAG, 'buildBigPictureContent-->get bigPicture failed');
      return undefined;
    }
    try {
      let content: NContent | undefined = this.toNotificationContent(
        notificationContentBuilder.initNotificationPictureContent({
          title: this.formatStyledText(styleInformation.htmlFormatTitle, notificationDetails.title),
          body: this.formatStyledText(styleInformation.htmlFormatBody, notificationDetails.body),
          expandedTitle: this.formatStyledText(styleInformation.htmlFormatContentTitle, styleInformation.contentTitle),
          briefText: this.formatStyledText(styleInformation.htmlFormatSummaryText, styleInformation.summaryText),
          picture: bigPicturePixelMap,
          subText: notificationDetails.subText,
        }));
      if (content == undefined) {
        this.releasePixelMap(bigPicturePixelMap);
      }
      return content;
    } catch (e) {
      this.releasePixelMap(bigPicturePixelMap);
      throw e instanceof Error ? e : new Error(String(e));
    }
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    if (pixelMap == undefined) {
      return;
    }
    try {
      pixelMap.release();
    } catch (e) {
      Log.e(TAG, 'releasePixelMap-->picture: ' + JSON.stringify(e));
    }
  }

  /**
   * Builds messaging-style notification content as multi-line text.
   *
   * @param notificationDetails Parsed notification payload.
   * @returns Notification content or undefined when required fields are missing.
   */
  buildMessagingContent(notificationDetails: NotificationDetails): NContent | undefined {
    let styleInformation: MessagingStyleInformation =
      notificationDetails.styleInformation as MessagingStyleInformation;
    let lines: string[] = [];
    if (styleInformation.messages) {
      for (let message of styleInformation.messages) {
        let sender: string = message.person?.name ?? styleInformation.person?.name ?? '';
        lines.push(sender ? `${sender}: ${message.text}` : message.text);
      }
    }
    if (lines.length == 0 && notificationDetails.body) {
      lines.push(notificationDetails.body);
    }
    let contentTitle: string = styleInformation.conversationTitle ?? notificationDetails.title;
    let summaryText: string = styleInformation.groupConversation ?
      'Group conversation' : notificationDetails.body;
    return this.toNotificationContent(notificationContentBuilder.initNotificationMultiLineContent({
      title: this.formatStyledText(styleInformation.htmlFormatTitle, notificationDetails.title),
      body: this.formatStyledText(styleInformation.htmlFormatBody, notificationDetails.body),
      longTitle: contentTitle,
      briefText: summaryText,
      lines: lines,
      subText: notificationDetails.subText,
    }));
  }

  /**
   * Builds system live-view notification content.
   *
   * @param notificationDetails Parsed notification payload.
   * @returns Notification content or undefined when required fields are missing.
   */
  buildLiveViewContent(notificationDetails: NotificationDetails): NContent | undefined {
    let styleInformation: LiveViewStyleInformation =
      notificationDetails.styleInformation as LiveViewStyleInformation;
    return this.toNotificationContent(notificationContentBuilder.initNotificationSystemLiveViewContent({
      title: styleInformation.title,
      text: styleInformation.text,
      typeCode: styleInformation.typeCode,
      initialTime: styleInformation.initialTime,
      isCountDown: styleInformation.isCountDown,
      isPaused: styleInformation.isPaused,
      isInTitle: styleInformation.isInTitle,
    }));
  }

  /**
   * Releases PixelMap resources held by picture notification content.
   *
   * @param content Notification content that may contain a picture PixelMap.
   */
  releaseContentPixelMaps(content: NContent | undefined): void {
    if (content == undefined) {
      return;
    }
    try {
      if (content.picture?.picture) {
        content.picture.picture.release();
      }
    } catch (e) {
      Log.e(TAG, 'releaseContentPixelMaps-->picture: ' + JSON.stringify(e));
    }
  }
}
