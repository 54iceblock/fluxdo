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

import { PlatformSpecificsMap } from './OhosTypeAliases';

/** Typed getters for Dart platform-specifics [Map] values. */
export class PlatformSpecificsReader {
  private readonly map: PlatformSpecificsMap;

  constructor(map: PlatformSpecificsMap) {
    this.map = map;
  }

  /**
   * Returns whether the platform specifics map contains a key.
   *
   * @param key Map key to look up.
   * @returns true when the key is present.
   */
  has(key: string): boolean {
    return this.map.has(key);
  }

  /**
   * Reads a string value from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns String value or undefined when the key is missing.
   */
  optString(key: string): string | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined) {
      return undefined;
    }
    if (typeof value === 'string') {
      return value;
    }
    return undefined;
  }

  /**
   * Reads a boolean value from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns Boolean value or undefined when the key is missing or not a boolean.
   */
  optBool(key: string): boolean | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined) {
      return undefined;
    }
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    return undefined;
  }

  /**
   * Reads a number value from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns Number value or undefined when the key is missing or not a number.
   */
  optNumber(key: string): number | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined) {
      return undefined;
    }
    return typeof value === 'number' ? value : undefined;
  }

  /**
   * Reads an opaque object value from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns Object value or undefined when the key is missing.
   */
  optObject(key: string): Object | undefined {
    return this.map.get(key);
  }

  /**
   * Reads a large icon path or byte array from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns String path, byte array, or undefined when the key is missing.
   */
  optLargeIcon(key: string): string | Uint8Array | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined) {
      return undefined;
    }
    if (value instanceof Uint8Array) {
      return value;
    }
    return String(value);
  }

  /**
   * Reads a string array from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns String array or undefined when the key is missing or not an array.
   */
  optStringArray(key: string): Array<string> | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined || !Array.isArray(value)) {
      return undefined;
    }
    return value as Array<string>;
  }

  /**
   * Reads a number array from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns Number array or undefined when the key is missing or not an array.
   */
  optNumberArray(key: string): Array<number> | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined || !Array.isArray(value)) {
      return undefined;
    }
    return value as Array<number>;
  }

  /**
   * Reads a nested map from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns Nested map or undefined when the key is missing.
   */
  optMap(key: string): Map<string, Object> | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined) {
      return undefined;
    }
    return value as Map<string, Object>;
  }

  /**
   * Reads a list of nested maps from the platform specifics map.
   *
   * @param key Map key to look up.
   * @returns Map list or undefined when the key is missing or not an array.
   */
  optMapList(key: string): Array<Map<string, Object>> | undefined {
    let value: Object | undefined = this.map.get(key);
    if (value == undefined || !Array.isArray(value)) {
      return undefined;
    }
    return value as Array<Map<string, Object>>;
  }
}
