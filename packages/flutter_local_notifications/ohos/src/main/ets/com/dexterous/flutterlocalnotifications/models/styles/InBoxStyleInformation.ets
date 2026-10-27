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

/** Configuration for [InBoxStyleInformation]. */
export interface InBoxStyleConfig {
  htmlFormatTitle: boolean;
  htmlFormatBody: boolean;
  contentTitle: string;
  lines: string[];
  summaryText: string;
  htmlFormatContentTitle: boolean;
  htmlFormatLines: boolean;
  htmlFormatSummaryText: boolean;
}

export class InBoxStyleInformation extends DefaultStyleInformation {
  public lines: string[];
  public contentTitle: string;
  public summaryText: string;

  public htmlFormatContentTitle: boolean;
  public htmlFormatLines: boolean;
  public htmlFormatSummaryText: boolean;

  /** Creates inbox style metadata with optional HTML formatting flags. */
  constructor(config: InBoxStyleConfig) {
    super(config.htmlFormatTitle, config.htmlFormatBody);
    this.lines = config.lines;
    this.contentTitle = config.contentTitle;
    this.summaryText = config.summaryText;
    this.htmlFormatContentTitle = config.htmlFormatContentTitle;
    this.htmlFormatLines = config.htmlFormatLines;
    this.htmlFormatSummaryText = config.htmlFormatSummaryText;
  }
}
