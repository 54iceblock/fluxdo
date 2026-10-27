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

import { DefaultStyleInformation } from './DefaultStyleInformation';

/** Configuration for [BigTextStyleInformation]. */
export interface BigTextStyleConfig {
  htmlFormatTitle: boolean;
  htmlFormatBody: boolean;
  contentTitle: string;
  bigText: string;
  summaryText: string;
  htmlFormatContentTitle: boolean;
  htmlFormatBigText: boolean;
  htmlFormatSummaryText: boolean;
}

export class BigTextStyleInformation extends DefaultStyleInformation {
  public contentTitle: string;
  public bigText: string;
  public summaryText: string;

  public htmlFormatContentTitle: boolean;
  public htmlFormatBigText: boolean;
  public htmlFormatSummaryText: boolean;

  /** Creates big-text style metadata parsed from Dart platform specifics. */
  constructor(config: BigTextStyleConfig) {
    super(config.htmlFormatTitle, config.htmlFormatBody);
    this.bigText = config.bigText;
    this.contentTitle = config.contentTitle;
    this.summaryText = config.summaryText;
    this.htmlFormatContentTitle = config.htmlFormatContentTitle;
    this.htmlFormatBigText = config.htmlFormatBigText;
    this.htmlFormatSummaryText = config.htmlFormatSummaryText;
  }
}
