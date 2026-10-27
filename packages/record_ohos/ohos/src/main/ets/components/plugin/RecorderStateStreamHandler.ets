/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
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
import { Any } from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';

export class RecorderStateStreamHandler implements StreamHandler {
  private readonly TAG = 'RecorderStateStreamHandler';
  private eventSink: EventSink | null = null;

  onListen(args: Any, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel() {
    this.eventSink = null;
  }

  sendStateEvent(state: number) {
    if (this.eventSink == null) {
      console.error(this.TAG + ' eventSink null ');
      return;
    }
    this.eventSink!.success(state)
  }

  sendStateErrorEvent(ex: Error) {
    this.eventSink!.error('-1', ex.message, '')
  }
}