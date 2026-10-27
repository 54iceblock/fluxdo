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

import { PictureSource } from './PictureSource';
import { DefaultStyleInformation } from './DefaultStyleInformation';

/** Configuration for [BigPictureStyleInformation]. */
export interface BigPictureStyleConfig {
  htmlFormatTitle: boolean;
  htmlFormatBody: boolean;
  contentTitle: string;
  summaryText: string;
  htmlFormatContentTitle: boolean;
  htmlFormatSummaryText: boolean;
  bigPicture: string | Uint8Array;
  bigPictureSource: PictureSource;
}

export class BigPictureStyleInformation extends DefaultStyleInformation {
  public contentTitle: string;
  public summaryText: string;

  public htmlFormatContentTitle: boolean;
  public htmlFormatSummaryText: boolean;

  public bigPicture: string | Uint8Array;
  public bigPictureSource: PictureSource;

  /** Creates big-picture style metadata with optional HTML formatting flags. */
  constructor(config: BigPictureStyleConfig) {
    super(config.htmlFormatTitle, config.htmlFormatBody);
    this.contentTitle = config.contentTitle;
    this.summaryText = config.summaryText;
    this.htmlFormatContentTitle = config.htmlFormatContentTitle;
    this.htmlFormatSummaryText = config.htmlFormatSummaryText;
    this.bigPicture = config.bigPicture;
    this.bigPictureSource = config.bigPictureSource;
  }
}
