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

import { BusinessError } from '@kit.BasicServicesKit';

/**
 * Returns a [BusinessError] when the value matches OHOS error shape; otherwise undefined.
 *
 * @param error Thrown or callback error value.
 * @returns Parsed business error or undefined.
 */
export function readBusinessError(error: Error | BusinessError): BusinessError | undefined {
  if (typeof error !== 'object' || error === null) {
    return undefined;
  }
  let code: number = (error as BusinessError).code;
  let message: string = (error as BusinessError).message;
  if (typeof code === 'number' && typeof message === 'string') {
    return error as BusinessError;
  }
  return undefined;
}

/**
 * Extracts a human-readable message from an unknown thrown value.
 *
 * @param error Thrown or callback error value.
 * @returns Error message string.
 */
export function readErrorMessage(error: Error | BusinessError | ESObject): string {
  if (error instanceof Error) {
    return error.message;
  }
  let businessError: BusinessError | undefined = readBusinessError(error as Error | BusinessError);
  if (businessError !== undefined) {
    return businessError.message;
  }
  return String(error);
}
