
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import hilog from '@ohos.hilog';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import FluxdoBridgePlugin from '../plugins/FluxdoBridgePlugin';

const DOMAIN: number = 0x0F1D;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends FlutterAbility {
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
}
