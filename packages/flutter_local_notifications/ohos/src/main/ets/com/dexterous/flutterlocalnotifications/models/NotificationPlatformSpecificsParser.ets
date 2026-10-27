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

import { MethodCall } from '@ohos/flutter_ohos';
import { LocalNotificationsConstants } from '../LocalNotificationsConstants';
import { NotificationAction } from './NotificationAction';
import NotificationDetails from './NotificationDetails';
import { MessageDetails } from './MessageDetails';
import { PersonDetails } from './PersonDetails';
import { NotificationSlotAction } from './NotificationSlotAction';
import { SoundSource } from './SoundSource';
import { BigPictureStyleInformation, BigPictureStyleConfig } from './styles/BigPictureStyleInformation';
import { BigTextStyleInformation, BigTextStyleConfig } from './styles/BigTextStyleInformation';
import { DefaultStyleInformation } from './styles/DefaultStyleInformation';
import { InBoxStyleInformation, InBoxStyleConfig } from './styles/InBoxStyleInformation';
import { LiveViewStyleInformation, LiveViewStyleConfig } from './styles/LiveViewStyleInformation';
import { MessagingStyleInformation, MessagingStyleConfig } from './styles/MessagingStyleInformation';
import { NotificationStyle } from './styles/NotificationStyle';
import { PictureSource } from './styles/PictureSource';
import { PlatformSpecificsMap } from '../utils/OhosTypeAliases';
import { PlatformSpecificsReader } from '../utils/PlatformSpecificsReader';

/** ARGB component key names within platform specifics. */
export interface ArgbColorKeys {
  alphaKey: string;
  redKey: string;
  greenKey: string;
  blueKey: string;
}

/** Parses Dart platform-specific notification fields into [NotificationDetails]. */
export class NotificationPlatformSpecificsParser {
  /**
   * Reads all OHOS platform-specific fields from a MethodChannel call.
   *
   * @param call Incoming MethodChannel call from Dart.
   * @param notificationDetails Target model to populate.
   */
  static readPlatformSpecifics(call: MethodCall, notificationDetails: NotificationDetails): void {
    let platformChannelSpecifics: PlatformSpecificsMap =
      call.argument(LocalNotificationsConstants.PLATFORM_SPECIFICS) as PlatformSpecificsMap;
    if (!platformChannelSpecifics) {
      return;
    }
    let reader: PlatformSpecificsReader = new PlatformSpecificsReader(platformChannelSpecifics);
    NotificationPlatformSpecificsParser.readBasicFields(reader, notificationDetails);
    NotificationPlatformSpecificsParser.readStyleInformation(reader, notificationDetails);
    NotificationPlatformSpecificsParser.readActionFields(reader, notificationDetails);
    NotificationPlatformSpecificsParser.readSoundFields(reader, notificationDetails);
    NotificationPlatformSpecificsParser.readSlotFields(reader, notificationDetails);
  }

  private static readBasicFields(reader: PlatformSpecificsReader, details: NotificationDetails): void {
    details.subText = reader.optString(LocalNotificationsConstants.SUBTEXT);
    details.autoCancel = reader.optBool(LocalNotificationsConstants.AUTO_CANCEL);
    details.ongoing = reader.optBool(LocalNotificationsConstants.ONGOING);
    details.onlyAlertOnce = reader.optBool(LocalNotificationsConstants.ONLY_ALERT_ONCE);
    details.showWhen = reader.optBool(LocalNotificationsConstants.SHOW_WHEN);
    let whenObj: number | undefined = reader.optNumber(LocalNotificationsConstants.WHEN);
    if (whenObj != undefined) {
      details.when = Number(whenObj);
    }
    details.tag = reader.optString(LocalNotificationsConstants.TAG);
    details.groupKey = reader.optString(LocalNotificationsConstants.GROUP_KEY);
    details.badgeNumber = reader.optNumber(LocalNotificationsConstants.BADGE_NUMBER);
    details.timeoutAfter = reader.optNumber(LocalNotificationsConstants.TIMEOUT_AFTER);
    details.usesChronometer = reader.optBool(LocalNotificationsConstants.USES_CHRONOMETER);
    details.chronometerCountDown = reader.optBool(LocalNotificationsConstants.CHRONOMETER_COUNTDOWN);
    details.icon = reader.optString(LocalNotificationsConstants.ICON);
    details.isFloatingIcon = reader.optBool(LocalNotificationsConstants.IS_FLOAT_ICON);
    details.largeIcon = reader.optLargeIcon(LocalNotificationsConstants.LARGE_ICON);
    details.largeIconSource = NotificationPlatformSpecificsParser.parsePictureSource(
      reader.optNumber(LocalNotificationsConstants.LARGE_ICON_SOURCE));
    details.showProgress = reader.optBool(LocalNotificationsConstants.SHOW_PROGRESS);
    if (reader.has(LocalNotificationsConstants.MAX_PROGRESS)) {
      details.maxProgress = reader.optNumber(LocalNotificationsConstants.MAX_PROGRESS);
    }
    if (reader.has(LocalNotificationsConstants.PROGRESS)) {
      details.progress = reader.optNumber(LocalNotificationsConstants.PROGRESS);
    }
    details.colorized = reader.optBool(LocalNotificationsConstants.COLORIZED);
    NotificationPlatformSpecificsParser.applyArgbColor(reader, {
      alphaKey: LocalNotificationsConstants.COLOR_ALPHA,
      redKey: LocalNotificationsConstants.COLOR_RED,
      greenKey: LocalNotificationsConstants.COLOR_GREEN,
      blueKey: LocalNotificationsConstants.COLOR_BLUE,
    }, (color: number) => { details.color = color; });
  }

  private static readActionFields(reader: PlatformSpecificsReader, details: NotificationDetails): void {
    if (!reader.has(LocalNotificationsConstants.ACTIONS)) {
      return;
    }
    let mapList: Map<string, Object>[] | undefined =
      reader.optMapList(LocalNotificationsConstants.ACTIONS);
    if (!mapList) {
      return;
    }
    let actionList: NotificationAction[] = [];
    for (let map of mapList) {
      actionList.push(new NotificationAction(map));
    }
    details.actions = actionList;
  }

  private static readSoundFields(reader: PlatformSpecificsReader, details: NotificationDetails): void {
    details.playSound = reader.optBool(LocalNotificationsConstants.PLAY_SOUND);
    details.sound = reader.optString(LocalNotificationsConstants.SOUND);
    details.soundSource = NotificationPlatformSpecificsParser.parseSoundSource(
      reader.optNumber(LocalNotificationsConstants.SOUND_SOURCE));
    details.enableVibration = reader.optBool(LocalNotificationsConstants.ENABLE_VIBRATION);
    details.vibrationPattern = reader.optNumberArray(LocalNotificationsConstants.VIBRATION_PATTERN);
    details.enableLights = reader.optBool(LocalNotificationsConstants.ENABLE_LIGHTS);
    NotificationPlatformSpecificsParser.applyArgbColor(reader, {
      alphaKey: LocalNotificationsConstants.LED_COLOR_ALPHA,
      redKey: LocalNotificationsConstants.LED_COLOR_RED,
      greenKey: LocalNotificationsConstants.LED_COLOR_GREEN,
      blueKey: LocalNotificationsConstants.LED_COLOR_BLUE,
    }, (color: number) => { details.ledColor = color; });
    let silent: boolean | undefined = reader.optBool(LocalNotificationsConstants.SILENT);
    if (silent) {
      details.playSound = false;
      details.enableVibration = false;
      details.enableLights = false;
    }
  }

  private static readSlotFields(reader: PlatformSpecificsReader, details: NotificationDetails): void {
    details.slotType = reader.optNumber(LocalNotificationsConstants.SLOT_TYPE);
    details.slotDesc = reader.optString(LocalNotificationsConstants.SLOT_DESC);
    details.slotAction = NotificationDetails.parseSlotAction(
      reader.optNumber(LocalNotificationsConstants.SLOT_ACTION));
    details.slotShowBadge = reader.optBool(LocalNotificationsConstants.SLOT_SHOW_BADGE);
    details.importance = reader.optNumber(LocalNotificationsConstants.IMPORTANCE);
    details.lockscreenVisibility = NotificationDetails.parseLockscreenVisibility(
      reader.optObject(LocalNotificationsConstants.LOCKSCREEN_VISIBILITY));
    details.bypassDnd = reader.optBool(LocalNotificationsConstants.BYPASS_DND);
  }

  private static readStyleInformation(reader: PlatformSpecificsReader, details: NotificationDetails): void {
    details.style = reader.optNumber(LocalNotificationsConstants.STYLE);
    let styleInformation: Map<string, Object> | undefined =
      reader.optMap(LocalNotificationsConstants.STYLE_INFORMATION);
    if (!styleInformation) {
      return;
    }
    let styleReader: PlatformSpecificsReader = new PlatformSpecificsReader(styleInformation);
    let defaultStyle: DefaultStyleInformation =
      NotificationPlatformSpecificsParser.getDefaultStyleInformation(styleReader);
    if (details.style == NotificationStyle.DefaultStyle) {
      details.styleInformation = defaultStyle;
    } else if (details.style == NotificationStyle.BigPicture) {
      NotificationPlatformSpecificsParser.readBigPictureStyle(details, styleReader, defaultStyle);
    } else if (details.style == NotificationStyle.BigText) {
      NotificationPlatformSpecificsParser.readBigTextStyle(details, styleReader, defaultStyle);
    } else if (details.style == NotificationStyle.Inbox) {
      NotificationPlatformSpecificsParser.readInboxStyle(details, styleReader, defaultStyle);
    } else if (details.style == NotificationStyle.Messaging) {
      NotificationPlatformSpecificsParser.readMessagingStyle(details, styleReader, defaultStyle);
    } else if (details.style == NotificationStyle.LiveView) {
      NotificationPlatformSpecificsParser.readLiveViewStyle(details, styleReader, defaultStyle);
    }
  }

  private static getDefaultStyleInformation(reader: PlatformSpecificsReader): DefaultStyleInformation {
    let htmlFormatTitle: boolean =
      reader.optBool(LocalNotificationsConstants.HTML_FORMAT_TITLE) ?? false;
    let htmlFormatBody: boolean =
      reader.optBool(LocalNotificationsConstants.HTML_FORMAT_CONTENT) ?? false;
    return new DefaultStyleInformation(htmlFormatTitle, htmlFormatBody);
  }

  private static readLiveViewStyle(details: NotificationDetails, reader: PlatformSpecificsReader,
    defaultStyle: DefaultStyleInformation): void {
    let config: LiveViewStyleConfig = {
      htmlFormatTitle: defaultStyle.htmlFormatTitle,
      htmlFormatBody: defaultStyle.htmlFormatBody,
      title: reader.optString('title') ?? 'title',
      text: reader.optString('text') ?? 'text',
      typeCode: reader.optNumber('typeCode') ?? 0,
      initialTime: reader.optNumber('initialTime') ?? 3000,
      isCountDown: reader.optBool('isCountDown') ?? false,
      isPaused: reader.optBool('isPaused') ?? false,
      isInTitle: reader.optBool('isInTitle') ?? false,
    };
    details.styleInformation = new LiveViewStyleInformation(config);
  }

  private static readMessagingStyle(details: NotificationDetails, reader: PlatformSpecificsReader,
    defaultStyle: DefaultStyleInformation): void {
    let config: MessagingStyleConfig = {
      htmlFormatTitle: defaultStyle.htmlFormatTitle,
      htmlFormatBody: defaultStyle.htmlFormatBody,
      person: NotificationPlatformSpecificsParser.readPersonDetails(
        reader.optMap(LocalNotificationsConstants.PERSON)),
      conversationTitle: reader.optString(LocalNotificationsConstants.CONVERSATION_TITLE),
      groupConversation: reader.optBool(LocalNotificationsConstants.GROUP_CONVERSATION),
      messages: NotificationPlatformSpecificsParser.readMessages(
        reader.optMapList(LocalNotificationsConstants.MESSAGES)),
    };
    details.styleInformation = new MessagingStyleInformation(config);
  }

  private static readPersonDetails(person: Map<string, Object> | undefined): PersonDetails | undefined {
    if (!person) {
      return undefined;
    }
    let reader: PlatformSpecificsReader = new PlatformSpecificsReader(person);
    return new PersonDetails(
      reader.optBool(LocalNotificationsConstants.BOT),
      reader.optBool(LocalNotificationsConstants.IMPORTANT),
      reader.optString(LocalNotificationsConstants.KEY),
      reader.optString(LocalNotificationsConstants.NAME),
      reader.optString(LocalNotificationsConstants.URI));
  }

  private static readMessages(messages: Map<string, Object>[] | undefined): MessageDetails[] {
    let result: MessageDetails[] = [];
    if (!messages) {
      return result;
    }
    for (let messageData of messages) {
      if (!messageData) {
        continue;
      }
      let reader: PlatformSpecificsReader =
        new PlatformSpecificsReader(messageData as Map<string, Object>);
      result.push(new MessageDetails(
        reader.optString(LocalNotificationsConstants.TEXT) ?? '',
        reader.optNumber(LocalNotificationsConstants.TIMESTAMP),
        NotificationPlatformSpecificsParser.readPersonDetails(
          reader.optMap(LocalNotificationsConstants.PERSON)),
        reader.optString(LocalNotificationsConstants.DATA_MIME_TYPE),
        reader.optString(LocalNotificationsConstants.DATA_URI)));
    }
    return result;
  }

  private static readBigPictureStyle(details: NotificationDetails, reader: PlatformSpecificsReader,
    defaultStyle: DefaultStyleInformation): void {
    let contentTitle: string | undefined = reader.optString(LocalNotificationsConstants.CONTENT_TITLE);
    let summaryText: string | undefined = reader.optString(LocalNotificationsConstants.SUMMARY_TEXT);
    let bigPicture: string | Uint8Array | undefined =
      reader.optObject(LocalNotificationsConstants.BIG_PICTURE) as (string | Uint8Array | undefined);
    let bigPictureSourceRaw: number | undefined =
      reader.optNumber(LocalNotificationsConstants.BIG_PICTURE_SOURCE);
    if (!contentTitle || !summaryText || !bigPicture || bigPictureSourceRaw == undefined) {
      return;
    }
    let bigPictureSource: PictureSource | undefined =
      NotificationPlatformSpecificsParser.parsePictureSource(bigPictureSourceRaw);
    if (bigPictureSource == undefined) {
      return;
    }
    let config: BigPictureStyleConfig = {
      htmlFormatTitle: defaultStyle.htmlFormatTitle,
      htmlFormatBody: defaultStyle.htmlFormatBody,
      contentTitle: contentTitle,
      summaryText: summaryText,
      htmlFormatContentTitle: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_CONTENT_TITLE) ?? false,
      htmlFormatSummaryText: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_SUMMARY_TEXT) ?? false,
      bigPicture: bigPicture,
      bigPictureSource: bigPictureSource,
    };
    details.styleInformation = new BigPictureStyleInformation(config);
  }

  private static readBigTextStyle(details: NotificationDetails, reader: PlatformSpecificsReader,
    defaultStyle: DefaultStyleInformation): void {
    let contentTitle: string | undefined = reader.optString(LocalNotificationsConstants.CONTENT_TITLE);
    let bigText: string | undefined = reader.optString(LocalNotificationsConstants.BIG_TEXT);
    let summaryText: string | undefined = reader.optString(LocalNotificationsConstants.SUMMARY_TEXT);
    if (!contentTitle || !bigText || !summaryText) {
      return;
    }
    let config: BigTextStyleConfig = {
      htmlFormatTitle: defaultStyle.htmlFormatTitle,
      htmlFormatBody: defaultStyle.htmlFormatBody,
      contentTitle: contentTitle,
      bigText: bigText,
      summaryText: summaryText,
      htmlFormatContentTitle: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_CONTENT_TITLE) ?? false,
      htmlFormatSummaryText: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_SUMMARY_TEXT) ?? false,
      htmlFormatBigText: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_BIG_TEXT) ?? false,
    };
    details.styleInformation = new BigTextStyleInformation(config);
  }

  private static readInboxStyle(details: NotificationDetails, reader: PlatformSpecificsReader,
    defaultStyle: DefaultStyleInformation): void {
    let contentTitle: string | undefined = reader.optString(LocalNotificationsConstants.CONTENT_TITLE);
    let lines: string[] | undefined = reader.optStringArray(LocalNotificationsConstants.TEXT_LINES);
    let summaryText: string | undefined = reader.optString(LocalNotificationsConstants.SUMMARY_TEXT);
    if (!contentTitle || !lines || !summaryText) {
      return;
    }
    let config: InBoxStyleConfig = {
      htmlFormatTitle: defaultStyle.htmlFormatTitle,
      htmlFormatBody: defaultStyle.htmlFormatBody,
      contentTitle: contentTitle,
      lines: lines,
      summaryText: summaryText,
      htmlFormatContentTitle: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_CONTENT_TITLE) ?? false,
      htmlFormatSummaryText: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_SUMMARY_TEXT) ?? false,
      htmlFormatLines: reader.optBool(LocalNotificationsConstants.HTML_FORMAT_LINES) ?? false,
    };
    details.styleInformation = new InBoxStyleInformation(config);
  }

  /**
   * Parses a Dart picture source index into [PictureSource].
   *
   * @param raw Raw picture source index from Dart.
   * @returns Parsed picture source or undefined when invalid.
   */
  static parsePictureSource(raw: number | undefined): PictureSource | undefined {
    if (raw == undefined) {
      return undefined;
    }
    if (raw === PictureSource.DrawableResource || raw === PictureSource.FilePath || raw === PictureSource.ByteArray) {
      return raw as PictureSource;
    }
    return undefined;
  }

  /**
   * Parses a Dart sound source index into [SoundSource].
   *
   * @param raw Raw sound source index from Dart.
   * @returns Parsed sound source or undefined when invalid.
   */
  static parseSoundSource(raw: number | undefined): SoundSource | undefined {
    if (raw == undefined) {
      return undefined;
    }
    if (raw === SoundSource.RawResource || raw === SoundSource.Uri) {
      return raw as SoundSource;
    }
    return undefined;
  }

  private static applyArgbColor(reader: PlatformSpecificsReader, keys: ArgbColorKeys,
    setter: (color: number) => void): void {
    let alpha: number | undefined = reader.optNumber(keys.alphaKey);
    let red: number | undefined = reader.optNumber(keys.redKey);
    let green: number | undefined = reader.optNumber(keys.greenKey);
    let blue: number | undefined = reader.optNumber(keys.blueKey);
    if (alpha == undefined || red == undefined || green == undefined || blue == undefined) {
      return;
    }
    alpha = Math.max(0, Math.min(255, alpha));
    red = Math.max(0, Math.min(255, red));
    green = Math.max(0, Math.min(255, green));
    blue = Math.max(0, Math.min(255, blue));
    let color: number = (alpha << 24) | (red << 16) | (green << 8) | blue;
    if (color < 0) {
      color = 0xFFFFFFFF + color + 1;
    }
    setter(color);
  }
}
