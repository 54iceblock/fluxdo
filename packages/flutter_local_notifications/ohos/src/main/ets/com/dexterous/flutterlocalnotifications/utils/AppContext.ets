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

import UIAbility from '@ohos.app.ability.UIAbility';
import Want from '@ohos.app.ability.Want';

/** Per-plugin holder for the bound UIAbility; avoids static/globalThis sharing across engines. */
export class AppContext {
  private ability: UIAbility | undefined;
  private defaultIcon: string | undefined;
  private launchWant: Want | undefined;

  /**
   * Stores the UIAbility used for resource and context lookups.
   *
   * @param ability Current host UIAbility or undefined when detaching.
   */
  setAbility(ability: UIAbility | undefined): void {
    this.ability = ability;
  }

  /**
   * Returns the stored UIAbility for this plugin instance.
   *
   * @returns UIAbility instance or undefined when unavailable.
   */
  getAbility(): UIAbility | undefined {
    return this.ability;
  }

  /**
   * Stores the default notification icon resource name for this plugin instance.
   *
   * @param icon Drawable resource name or undefined when clearing.
   */
  setDefaultIcon(icon: string | undefined): void {
    this.defaultIcon = icon;
  }

  /**
   * Returns the default icon resource name for this plugin instance.
   *
   * @returns Drawable resource name or undefined when not configured.
   */
  getDefaultIcon(): string | undefined {
    return this.defaultIcon;
  }

  /** Clears the stored default icon resource name. */
  clearDefaultIcon(): void {
    this.defaultIcon = undefined;
  }

  /**
   * Stores the launch Want for cold-start notification response lookup.
   *
   * @param launchWant Ability launch Want or undefined when clearing.
   */
  setLaunchWant(launchWant: Want | undefined): void {
    this.launchWant = launchWant;
  }

  /**
   * Returns the stored launch Want for notification response queries.
   *
   * @returns Launch Want or undefined when not set.
   */
  getLaunchWant(): Want | undefined {
    return this.launchWant;
  }

  /** Clears the stored launch Want. */
  clearLaunchWant(): void {
    this.launchWant = undefined;
  }
}
