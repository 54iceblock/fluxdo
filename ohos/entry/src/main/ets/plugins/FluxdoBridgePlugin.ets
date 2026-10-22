/**
 * FluxDO 自研 OHOS ArkTS 桥（task-8）。
 *
 * 职责：给 Flutter 侧补上没有 OHOS 原生实现的系统能力。当前只包含「时区」
 * （P0），后续新增桥（如文件另存为）都在本文件里加。
 *
 * 通道设计：
 *  - `com.fluxdo/ohos`：自研业务通道。Dart 侧（lib/utils/time_utils.dart）显式调用，
 *    不依赖第三方包的内部实现细节，意图最清晰。
 *  - `flutter_timezone`：flutter_timezone 5.1.x 的 **实际** 通道名
 *    （见 .pub-cache/hosted/.../flutter_timezone-5.1.1/lib/flutter_timezone.dart 第 12 行
 *    `static const _channel = MethodChannel('flutter_timezone')`）。该包没有 OHOS 平台实现，
 *    我们在这里顶替它的原生端，于是 `FlutterTimezone.getLocalTimezone()` 在 OHOS 直接可用。
 *  - `plugins.jonasroesner.dev/flutter_timezone`：flutter_timezone 部分 5.x 文档/旧版本
 *    使用的通道名。一并应答，防止将来升级/降级包版本时通道名漂移导致再次回退 UTC。
 *
 * 时区 API 选型（实际以本机 API 26 SDK 为准）：
 *  任务书里写的 `i18n.System.getSystemTimeZone()` 在 API 26 SDK
 *  （D:\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.i18n.d.ts）中并不存在；
 *  官方等效写法是 `i18n.getTimeZone()`（不传参 = 系统时区）再取 `getID()`，
 *  返回 IANA 名（如 "Asia/Shanghai"），与 flutter_timezone 的契约一致。
 *
 * 注册方式：在 EntryAbility.configureFlutterEngine() 里手动 `getPlugins()?.add(...)`。
 * 不能写进 GeneratedPluginRegistrant.ets —— 那是 flutter 工具每次构建重新生成的
 * gitignore 文件。
 */
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodResult,
  MethodChannel,
} from '@ohos/flutter_ohos';
import i18n from '@ohos.i18n';
import hilog from '@ohos.hilog';

const DOMAIN: number = 0x0F1D;
const TAG: string = 'FluxdoBridge';

/** 自研业务通道（Dart 侧显式调用） */
const CHANNEL_FLUXDO_OHOS: string = 'com.fluxdo/ohos';
/** flutter_timezone 5.1.x 实际使用的通道名 */
const CHANNEL_FLUTTER_TIMEZONE: string = 'flutter_timezone';
/** flutter_timezone 部分 5.x 文档/旧版本使用的通道名（兼容兜底） */
const CHANNEL_FLUTTER_TIMEZONE_LEGACY: string =
  'plugins.jonasroesner.dev/flutter_timezone';

/** 兜底时区：与 Dart 侧 TimeUtils 的最终回退保持一致 */
const FALLBACK_TIMEZONE: string = 'UTC';

export default class FluxdoBridgePlugin implements FlutterPlugin, MethodCallHandler {
  private channels: Array<MethodChannel> = [];

  getUniqueClassName(): string {
    return 'FluxdoBridgePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    try {
      const messenger = binding.getBinaryMessenger();
      const names: Array<string> = [
        CHANNEL_FLUXDO_OHOS,
        CHANNEL_FLUTTER_TIMEZONE,
        CHANNEL_FLUTTER_TIMEZONE_LEGACY,
      ];
      for (const name of names) {
        const channel = new MethodChannel(messenger, name);
        channel.setMethodCallHandler(this);
        this.channels.push(channel);
      }
      hilog.info(
        DOMAIN,
        TAG,
        'bridge attached, %{public}d channels, localTimezone=%{public}s',
        this.channels.length,
        this.getLocalTimezone()
      );
      // 自定义 hilog domain 在部分版本上不可见（hilog -x 抓不到），
      // 这里再用 console 打一份（映射到 JSAPP 域，稳定可见），便于验证时区桥。
      console.info(`FluxdoBridge attached, channels=${this.channels.length}, localTimezone=${this.getLocalTimezone()}`);
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, TAG, 'onAttachedToEngine failed: %{public}s', err.message);
    }
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    try {
      for (const channel of this.channels) {
        channel.setMethodCallHandler(null);
      }
      this.channels = [];
      hilog.info(DOMAIN, TAG, 'bridge detached');
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, TAG, 'onDetachedFromEngine failed: %{public}s', err.message);
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (call.method === 'getLocalTimezone') {
        // flutter_timezone：返回 String（Dart 侧会包成 TimezoneInfo(identifier)）
        const tz: string = this.getLocalTimezone();
        hilog.info(DOMAIN, TAG, 'getLocalTimezone -> %{public}s', tz);
        console.info(`FluxdoBridge getLocalTimezone -> ${tz}`);
        result.success(tz);
        return;
      }
      if (call.method === 'getAvailableTimezones') {
        result.success(this.getAvailableTimezones());
        return;
      }
      if (call.method === 'getSystemLocale') {
        result.success(i18n.System.getSystemLocale());
        return;
      }
      result.notImplemented();
    } catch (e) {
      const err = e as Error;
      hilog.error(
        DOMAIN,
        TAG,
        'method %{public}s failed: %{public}s',
        call.method,
        err.message
      );
      result.error('FLUXDO_OHOS_BRIDGE_ERROR', err.message, null);
    }
  }

  /**
   * 系统时区 ID（IANA 名），例如 "Asia/Shanghai"。
   *
   * 回退链：系统时区 → App 默认时区 → 固定 "UTC"。
   * 注意不要抛异常：Dart 侧拿不到会回退 UTC，但显式返回 'UTC' 能让 Dart 侧
   * 走正常路径，便于日志区分「桥失败」和「桥返回 UTC」。
   */
  private getLocalTimezone(): string {
    try {
      // 局部变量用类型推断，避免 ArkTS 对 namespace 类型标注的兼容性差异。
      const systemZone = i18n.getTimeZone();
      const id: string = systemZone.getID();
      if (id.length > 0) {
        return id;
      }
    } catch (e) {
      const err = e as Error;
      hilog.warn(DOMAIN, TAG, 'i18n.getTimeZone failed: %{public}s', err.message);
    }
    // API 26 的 i18n.System 没有 getAppDefaultTimeZone()，不再做二级回退，
    // 直接落到固定 UTC（Dart 侧同样有 UTC 兜底）。
    return FALLBACK_TIMEZONE;
  }

  /** 系统支持的时区 ID 列表（flutter_timezone 的 getAvailableTimezones 契约） */
  private getAvailableTimezones(): Array<string> {
    try {
      const ids: Array<string> = i18n.TimeZone.getAvailableIDs();
      if (ids.length > 0) {
        return ids;
      }
    } catch (e) {
      const err = e as Error;
      hilog.warn(
        DOMAIN,
        TAG,
        'i18n.TimeZone.getAvailableIDs failed: %{public}s',
        err.message
      );
    }
    return [this.getLocalTimezone()];
  }
}
