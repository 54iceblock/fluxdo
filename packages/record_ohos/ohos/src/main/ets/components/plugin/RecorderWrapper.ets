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
import { BinaryMessenger, MethodResult } from '@ohos/flutter_ohos';
import EventChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { RecordConfig } from './RecordConfig';
import { IRecorder } from './IRecorder';

import { MediaRecorder } from './MediaRecorder';
import { RecorderRecordStreamHandler } from './RecorderRecordStreamHandler';

import { RecorderStateStreamHandler } from './RecorderStateStreamHandler';

export class RecorderWrapper {
  private readonly TAG: string = 'RecorderWrapper';
  private readonly EVENTS_STATE_CHANNEL = "com.llfbandit.record/events/"
  private readonly EVENTS_RECORD_CHANNEL = "com.llfbandit.record/eventsRecord/"
  private recorderId: string | null;
  private messenger: BinaryMessenger;
  private recorder: IRecorder | null = null;
  private recorderStateStreamHandler: RecorderStateStreamHandler = new RecorderStateStreamHandler();
  private recorderRecordStreamHandler: RecorderRecordStreamHandler = new RecorderRecordStreamHandler();
  private eventChannel: EventChannel | null = null;
  private eventRecordChannel: EventChannel | null = null

  constructor(recorderId: string, message: BinaryMessenger) {
    this.recorderId = recorderId;
    this.messenger = message;
    this.init();
  }

  init(): void {
    this.eventChannel = new EventChannel(this.messenger, this.EVENTS_STATE_CHANNEL + this.recorderId)
    this.eventChannel!.setStreamHandler(this.recorderStateStreamHandler)
    this.eventRecordChannel = new EventChannel(this.messenger, this.EVENTS_RECORD_CHANNEL + this.recorderId)
    this.eventRecordChannel!.setStreamHandler(this.recorderRecordStreamHandler)
  }

  startRecordingToFile(config: RecordConfig, result: MethodResult) {
    this.startRecording(config, result)
  }

  startRecordingToStream(config: RecordConfig, result: MethodResult) {
    this.startRecording(config, result)
  }

  private startRecording(config: RecordConfig, result: MethodResult): void {
    try {
      if (this.recorder == null) {
        this.recorder = this.createRecorder(config)
        this.start(config, result)
      } else if (this.recorder!.isRecording) {
        this.recorder!.stop(() => {
          this.start(config, result)
        });
      } else {
        this.start(config, result)
      }
    } catch (e) {
      result.error(this.TAG +" record", e.message, e.cause);
    }
  }

  private start(config: RecordConfig, result: MethodResult): void {
    this.recorder!.start(config)
    result.success(null)
  }

  pause(result: MethodResult) {
    try {
      this.recorder!.pause()
      result.success(null)
    } catch (e) {
      result.error("record", e.message, e.cause)
    }
  }

  isPaused(result: MethodResult) {
    result.success(this.recorder!.isPaused)
  }

  isRecording(result: MethodResult) {
    result.success(this.recorder!.isRecording)
  }

  getAmplitude(result: MethodResult) {
    if (this.recorder != null) {
        let amps = this.recorder!.getAmplitude();
        let amp: Map<string, number> = new Map<string, number>();
        amp.set("current", amps[0]);
        amp.set("max", amps[1]);
        result.success(amp)
    } else {
      result.success(null)
    }
  }

  resume(result: MethodResult) {
    try {
      this.recorder!.resume()
      result.success(null)
    } catch (e) {
      result.error(this.TAG+" record", e, "")
    }
  }

  stop(result: MethodResult) {
    try {
      if (this.recorder == null) {
        result.success(null)
      } else {
        this.recorder!.stop((path) => {
          result.success(path);
        });
      }
    } catch (e) {
      result.error("record", e, "")
    }
  }

  cancel(result: MethodResult) {
    try {
      this.recorder!.cancel()
      result.success(null)
    } catch (e) {
      result.error(this.TAG+" record", e, "")
    }
  }

  private createRecorder(config: RecordConfig): IRecorder {
    return new MediaRecorder(this.recorderStateStreamHandler, this.recorderRecordStreamHandler);
  }

  public dispose() {
    try {
      this.recorder!.dispose()
    } catch (error) {
      console.error(this.TAG + ' record' + ' dispose ' + error);
    } finally {
      this.recorder = null;
    }
    this.eventChannel!.setStreamHandler(null)
    this.eventChannel = null
    this.eventRecordChannel!.setStreamHandler(null)
    this.eventRecordChannel = null
  }
}