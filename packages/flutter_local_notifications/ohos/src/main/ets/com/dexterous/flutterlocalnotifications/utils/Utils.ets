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
import { UIAbility } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { PictureSource } from '../models/styles/PictureSource';
import { Log } from '@ohos/flutter_ohos';
import { AppContext } from './AppContext';

const TAG: string = 'FlutterUtils';

export class Utils {
  /**
   * Loads a PixelMap from drawable, file path, or byte array sources.
   *
   * @param data Resource name, file path, or byte payload.
   * @param pictureSource Source type discriminator.
   * @param height Desired image height (reserved for future scaling).
   * @param width Desired image width (reserved for future scaling).
   * @param appContext Plugin context for resource and ability lookups.
   * @returns Decoded PixelMap or undefined when loading fails.
   */
  static async getPixelMapFromSource(
    data: string | Uint8Array,
    pictureSource: PictureSource,
    height: number,
    width: number,
    appContext: AppContext): Promise<image.PixelMap | undefined> {
    try {
      if (pictureSource == PictureSource.DrawableResource) {
        return await Utils.loadPixelMapFromDrawable(data, appContext);
      }
      if (pictureSource == PictureSource.FilePath) {
        return await Utils.loadPixelMapFromFilePath(data);
      }
      if (pictureSource == PictureSource.ByteArray) {
        return await Utils.loadPixelMapFromByteArray(data);
      }
    } catch (e) {
      Log.e(TAG, 'getPixelMapFromSource-->get picture fail: ' + JSON.stringify(e));
    }
    return undefined;
  }

  private static async loadPixelMapFromDrawable(data: string | Uint8Array,
    appContext: AppContext): Promise<image.PixelMap | undefined> {
    let uiAbility: UIAbility | undefined = appContext.getAbility();
    let imageArray: Uint8Array = await getContext(uiAbility).resourceManager.getMediaByName(String(data));
    let pixelBuffer: ArrayBuffer = imageArray.buffer.slice(imageArray.byteOffset,
      imageArray.byteOffset + imageArray.byteLength);
    if (!pixelBuffer) {
      return undefined;
    }
    return await Utils.createPixelMapFromBuffer(pixelBuffer);
  }

  private static async loadPixelMapFromFilePath(data: string | Uint8Array): Promise<image.PixelMap | undefined> {
    let path: string = String(data);
    let stat: fs.Stat = await fs.stat(path);
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(path);
      let arrayBuffer: ArrayBuffer = new ArrayBuffer(stat.size);
      await fs.read(file.fd, arrayBuffer);
      return await Utils.createPixelMapFromBuffer(arrayBuffer);
    } finally {
      if (file != undefined) {
        try {
          await fs.close(file.fd);
        } catch (closeErr) {
          Log.e(TAG, 'loadPixelMapFromFilePath-->close file fail: ' + JSON.stringify(closeErr));
        }
      }
    }
  }

  private static async loadPixelMapFromByteArray(data: string | Uint8Array): Promise<image.PixelMap | undefined> {
    if (!(data instanceof Uint8Array)) {
      return undefined;
    }
    let dataArray: Uint8Array = data;
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(dataArray.buffer.slice(0));
      return await imageSource.createPixelMap();
    } finally {
      if (imageSource != undefined) {
        try {
          imageSource.release();
        } catch (releaseErr) {
          Log.e(TAG, 'loadPixelMapFromByteArray-->release imageSource fail: ' + JSON.stringify(releaseErr));
        }
      }
    }
  }

  private static async createPixelMapFromBuffer(buffer: ArrayBuffer): Promise<image.PixelMap | undefined> {
    let imageSource: image.ImageSource | undefined = undefined;
    try {
      imageSource = image.createImageSource(buffer);
      let opts: image.DecodingOptions = {
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      return await imageSource.createPixelMap(opts);
    } finally {
      if (imageSource != undefined) {
        try {
          imageSource.release();
        } catch (releaseErr) {
          Log.e(TAG, 'createPixelMapFromBuffer-->release imageSource fail: ' + JSON.stringify(releaseErr));
        }
      }
    }
  }

  /**
   * Strips basic HTML tags from styled notification text.
   *
   * @param text Source text that may contain HTML markup.
   * @returns Plain text with tags removed.
   */
  public static fromHtml(text: string): string {
    if (!text) {
      return text;
    }
    return text
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<[^>]*>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .trim();
  }
}
