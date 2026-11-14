
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import hilog from '@ohos.hilog';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FluxdoBridgePlugin from '../plugins/FluxdoBridgePlugin';
import bundleManager from '@ohos.bundle.bundleManager';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import { Configuration } from '@ohos.app.ability.Configuration';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0F1D;
const TAG: string = 'EntryAbility';

/** 备用图标 `dark` 在 AppScope/app.json5 的 alternateIcons 里声明（API 26+）。 */
const ALT_ICON_DARK: string = 'dark';
/** 空串 = 取消备用图标，恢复 app.json5 的默认 icon（= 浅色模式的现状）。 */
const ALT_ICON_DEFAULT: string = '';
/** 备用图标能力自 API 26（HarmonyOS 7）起提供，低版本调用会直接报错。 */
const MIN_API_FOR_ALTERNATE_ICON: number = 26;
/** 没有已启用的备用图标时再传空串会得到该错误码，等价于「已经是默认图标」。 */
const ERR_NO_ALTERNATE_ICON_ENABLED: number = 17700309;

export default class EntryAbility extends FlutterAbility {
  /** 桌面图标同步的请求序号：切深浅色可能在配置回调里连发，以最后一次为准。 */
  private iconSyncSeq: number = 0;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // FluxDO 自研 ArkTS 桥（时区 / AVIF 探测 / 剪贴板写图片 / 外部浏览器）。
    // 必须在这里手动注册：GeneratedPluginRegistrant 由 flutter 工具每次构建重新生成
    // （已 gitignore），把桥写进去会在下次构建时丢失。
    // 插件只依赖 BinaryMessenger，不依赖 UIAbility，所以 configureFlutterEngine
    // 阶段注册是安全的。
    try {
      const plugins = flutterEngine.getPlugins();
      if (plugins != null) {
        // 桥里有需要 UIAbilityContext 的能力（startAbility 打开外部浏览器），
        // 注册前先把 context 交给桥插件。
        FluxdoBridgePlugin.abilityContext = this.context;
        plugins.add(new FluxdoBridgePlugin());
        hilog.info(DOMAIN, TAG, 'FluxdoBridgePlugin registered');
      } else {
        hilog.error(DOMAIN, TAG, 'FluxdoBridgePlugin not registered: plugins registry is null');
      }
    } catch (e) {
      const err = e as Error;
      hilog.error(
        DOMAIN,
        TAG,
        'FluxdoBridgePlugin register failed: %{public}s',
        err.message
      );
    }
  }

  // 深链诊断（审查报告 §7.2）：热启动时系统回调 onNewWant，基类会经
  // AbilityControlSurface 转给 app_links 插件，由其 eventSink 推到 Dart 的
  // uriLinkStream。这里只打一条带 uri 的 hilog，便于真机区分「系统没把 want
  // 交给本应用」与「交给了但 Dart 侧没收到（DeepLinkService 无『收到链接』）」。
  // 行为不变：必须先调 super，不能吞掉事件。
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
    // 冷启动深链：app_links 读 launchWant.uri 作为 initialLink
    hilog.info(DOMAIN, TAG, 'onCreate uri=%{public}s', want.uri ?? '');
    super.onCreate(want, launchParam);
    // 冷启动时按「当时」的系统深浅色同步桌面图标（见 syncDesktopIcon）。
    this.syncDesktopIcon(this.context.config.colorMode);
  }

  /**
   * 系统深浅色变化（应用在前台/后台都算）时同步桌面图标。
   * 必须先调 super：FlutterAbility 在这里把 brightness、字号、语言转给 Flutter，
   * 吞掉会破坏应用内深浅色跟随。
   */
  onConfigurationUpdate(config: Configuration): void {
    super.onConfigurationUpdate(config);
    this.syncDesktopIcon(config.colorMode);
  }

  /**
   * 按系统深浅色切换桌面图标：深色 → 备用图标 `dark`（深色经典图标），浅色 → 默认图标。
   *
   * 为什么要在应用里自己切：HarmonyOS 不会因为系统切了深色模式就去重绘第三方应用的
   * 桌面图标（launcher 按默认配置解析 icon，`dark/media` 限定词对桌面图标无效），
   * 只能由应用在冷启动或前台收到 onConfigurationUpdate 时用 API 26 的
   * `bundleManager.setAlternateIcon()` 主动切换。详见
   * HarmonyOS7-桌面图标深浅色-预研报告.md §3。
   *
   * 约束：不能阻塞生命周期、不能向外抛异常；API < 26 直接跳过；
   * 先查当前生效的备用图标，相同就不调用（可避开 17700309 且避免重复设置）。
   */
  private syncDesktopIcon(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    // 所有错误都在这里收口成 hilog，绝不向生命周期回调抛出。
    this.applyDesktopIcon(colorMode).catch((err: BusinessError) => {
      const code: number = err != null && err.code != null ? err.code : -1;
      const message: string = err != null && err.message != null ? err.message : 'unknown';
      hilog.error(DOMAIN, TAG, 'desktop icon sync failed: code=%{public}d message=%{public}s',
        code, message);
    });
  }

  private async applyDesktopIcon(colorMode: ConfigurationConstant.ColorMode | undefined): Promise<void> {
    if (deviceInfo.sdkApiVersion < MIN_API_FOR_ALTERNATE_ICON) {
      return; // 低版本没有 setAlternateIcon，静默降级为单一图标
    }
    // COLOR_MODE_NOT_SET / undefined 一律当浅色（恢复默认图标）。
    const desired: string =
      colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? ALT_ICON_DARK : ALT_ICON_DEFAULT;
    const token: number = ++this.iconSyncSeq;
    const icons: Array<bundleManager.AlternateIconInfo> = await bundleManager.getAlternateIcons();
    let current: string = ALT_ICON_DEFAULT;
    for (let i = 0; i < icons.length; i++) {
      if (icons[i].enabled) {
        current = icons[i].iconName;
        break;
      }
    }
    // 期间又来了新的深浅色回调 → 让最新那次去设置；已经一致 → 不重复调用。
    if (token !== this.iconSyncSeq || current === desired) {
      hilog.info(DOMAIN, TAG, 'desktop icon sync skipped: current=%{public}s desired=%{public}s',
        current, desired);
      return;
    }
    try {
      await bundleManager.setAlternateIcon(desired);
      hilog.info(DOMAIN, TAG, 'desktop icon %{public}s -> %{public}s', current, desired);
    } catch (e) {
      // 这里自己消化：ArkTS 的 arkts-limited-throw 不允许 throw 非 Error 类型的值，
      // 而且生命周期回调本来就不该被异常打断，所以一律记日志后 return。
      const err = e as BusinessError;
      const code: number = err != null && err.code != null ? err.code : -1;
      const message: string = err != null && err.message != null ? err.message : 'unknown';
      if (code === ERR_NO_ALTERNATE_ICON_ENABLED) {
        // 本来就没有启用的备用图标，说明已经是默认图标，按「无需切换」处理。
        hilog.info(DOMAIN, TAG, 'desktop icon already default (17700309), skip');
        return;
      }
      hilog.error(DOMAIN, TAG,
        'desktop icon %{public}s -> %{public}s failed: code=%{public}d message=%{public}s',
        current, desired, code, message);
    }
  }

  onNewWant(want: Want, launchParams: AbilityConstant.LaunchParam): void {
    hilog.info(
      DOMAIN,
      TAG,
      'onNewWant uri=%{public}s action=%{public}s',
      want.uri ?? '',
      want.action ?? ''
    );
    super.onNewWant(want, launchParams);
  }

  /**
   * 基类只在 CRITICAL 时通知 Dart；MODERATE / LOW 也转发 memoryPressure，
   * 让 Dart 侧释放 ImageCache 与自建缓存（lib/services/memory_reclaimer.dart）。
   * CRITICAL 仍交给基类，避免重复。
   *
   * 进后台不需要额外处理：引擎自带 GpuReclaim 会在 paused 后发 memoryPressure
   * 并拆交换链，Dart 侧 _enterBackground 也会清缓存。后台 GL 的额外释放方案
   * 已真机验证无收益（见 docs/engine-gl-reclaim-research.md §0.0）。
   */
  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    super.onMemoryLevel(level);
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_MODERATE ||
      level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_LOW) {
      this.sendMemoryPressure(`memoryLevel=${level}`);
    }
  }

  /** Dart 侧 didHaveMemoryPressure（notifyLowMemoryWarning 在嵌入层是空函数，不再调用）。 */
  private sendMemoryPressure(reason: string): void {
    try {
      this.getFlutterEngine()?.getSystemChannel()?.sendMemoryPressureWarning();
      hilog.info(DOMAIN, TAG, 'memoryPressure reason=%{public}s', reason);
    } catch (e) {
      const err = e as Error;
      hilog.error(DOMAIN, TAG, 'memoryPressure failed: %{public}s', err.message);
    }
  }
}
