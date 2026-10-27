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
import { MethodCall, MethodResult, BinaryMessenger, MethodCallHandler } from '@ohos/flutter_ohos';
import { RecorderWrapper } from './RecorderWrapper';
import { RecordConfig } from './RecordConfig';
import { Utils } from './Utils';

export class MethodCallHandlerImpl implements MethodCallHandler {
  private readonly TAG = 'MethodCallHandlerImpl';
  private messenger: BinaryMessenger;
  private recorders: Map<string, RecorderWrapper> = new Map<string, RecorderWrapper>();
  /**
   * 麦克风权限提供者（FluxDO 本地改动）：
   * 上游把 `hasPermission` 写死返回 true，权限在插件 attach 时无条件申请。
   * 现在改为按需：Dart 侧调用 hasPermission() 时才检查/申请。
   */
  private permissionProvider: (() => Promise<boolean>) | null;

  constructor(messenger: BinaryMessenger, permissionProvider?: () => Promise<boolean>) {
    this.messenger = messenger;
    this.permissionProvider = permissionProvider ?? null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const recorderId: string = call.argument('recorderId');
    if (recorderId === null || recorderId.trim() === '') {
      result.error(this.TAG + ' ARGUMENT_ERROR', 'Call missing mandatory parameter recorderId.', null);
      return;
    }
    if (call.method == "create") {
      try {
        this.createRecorder(recorderId);
        result.success(null);
      } catch (e) {
        result.error(this.TAG + " record", "Cannot create recording configuration.", e.message);
      }
      return;
    }

    let recorder = this.recorders.get(recorderId);
    if (recorder == null) {
      result.error(this.TAG + " record",
        "Recorder has not yet been created or has already been disposed.", null
      )
      return
    }
    switch (call.method) {
      case "start":
        let config = this.getRecordConfig(call);
        recorder.startRecordingToFile(config, result);
        break;
      case "startStream":
        try {
          let config = this.getRecordConfig(call);
          recorder.startRecordingToStream(config, result);
        } catch (e) {
          result.error(this.TAG + " record", "Cannot create recording configuration.", e)
        }
        break;
      case "stop":
        recorder.stop(result);
        break;
      case "pause":
        recorder.pause(result);
        break;
      case "resume":
        recorder.resume(result);
        break;
      case "isPaused":
        recorder.isPaused(result);
        break;
      case "isRecording":
        recorder.isRecording(result);
        break;
      case "cancel":
        recorder.cancel(result);
        break;
      case "hasPermission":
        // 上游是 `result.success(true)`（假定权限已在 attach 时申请过）。
        // 改为真实检查 + 按需申请：用户点「录音」时才会弹权限框。
        if (this.permissionProvider == null) {
          result.success(false);
          break;
        }
        this.permissionProvider().then((granted: boolean) => {
          result.success(granted);
        }).catch((err: Error) => {
          result.error(this.TAG + " record", "Cannot check record permission.", err.message);
        });
        break;
      case "getAmplitude":
        recorder.getAmplitude(result);
        break;
      case "listInputDevices":
        result.success(this.getDeviceMapList());
        break;
      case "dispose":
        this.disposeRecorder(recorder, recorderId);
        result.success(null)
        break;
      case "isEncoderSupported":
        result.success(true);
        break;
      default:
        result.notImplemented()
        break;
    }
  };

  getRecordConfig(call: MethodCall): RecordConfig {
    let config = call.argument("androidConfig") as Map<string, Object>;
    const recordConfig = new RecordConfig();
    recordConfig.path = call.argument("path");
    recordConfig.encoder = Utils.firstNonNull(call.argument("encoder"), "aacLc");
    recordConfig.bitRate = Utils.firstNonNull(call.argument("bitRate"), 128000);
    recordConfig.sampleRate = Utils.firstNonNull(call.argument("sampleRate"), 44100);
    recordConfig.numChannels = Utils.firstNonNull(call.argument("numChannels"), 2);
    recordConfig.autoGain = Utils.firstNonNull(call.argument("autoGain"), false);
    recordConfig.echoCancel = Utils.firstNonNull(call.argument("echoCancel"), false);
    recordConfig.noiseSuppress = Utils.firstNonNull(call.argument("noiseSuppress"), false);
    let isMuteAudio: boolean = false;
    isMuteAudio = config?.get("muteAudio") as boolean;
    recordConfig.muteAudio = isMuteAudio;
    return recordConfig;
  }

  createRecorder(recorderId: string): void {
    let recorder: RecorderWrapper = new RecorderWrapper(recorderId, this.messenger);
    this.recorders.set(recorderId, recorder);
  }

  getDeviceMapList(): Array<Map<string, string>> {
    const deviceInfo = new Map<string, string>();
    deviceInfo.set("id", "4");
    deviceInfo.set("label", "Microphone (Built-in Microphone)");
    const deviceList: Array<Map<string, string>> = [deviceInfo];
    return deviceList;
  }

  dispose() {
    this.recorders.forEach((value: RecorderWrapper, key: string) => {
      this.disposeRecorder(value, key)
    });
    this.recorders.clear()
  }

  disposeRecorder(recorder: RecorderWrapper, recorderId: string) {
    recorder.dispose()
    this.recorders.delete(recorderId)
  }
}