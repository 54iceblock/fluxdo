# VENDOR：file_picker（OHOS 适配副本）

| 项 | 内容 |
|---|---|
| 上游 | <https://github.com/miguelpruivo/flutter_file_picker>（file_picker 10.3.8） |
| OHOS 来源 | `gitcode.com/CPF-Flutter/fluttertpc_file_picker`，TAG `10.3.8-ohos-1.0.0`（分支 `br_v10.3.8_ohos`） |
| 许可证 | MIT（见同目录 `LICENSE`） |
| 同步日期 | 2026-10-21 |

## 相对上游 fork 的本地改动（仅此 4 处，便于升级时重放）

1. `pubspec.yaml`：`name: file_picker_ohos` → `name: file_picker`（用 path 依赖无缝覆盖官方包，业务代码
   `import 'package:file_picker/file_picker.dart'` 不用改）；版本保持 `10.3.8`。
2. `lib/file_picker.dart`（新增）：`export 'file_picker_ohos.dart';` —— 补齐与上游同名的入口文件。
3. `lib/**/*.dart`：`package:file_picker_ohos/` → `package:file_picker/`（14 个文件，纯重命名）。
4. `ohos/oh-package.json5` 与 `ohos/src/main/module.json5`：`name` 由 `file_picker_ohos` → `file_picker`
   （hvigor 按插件名注入 `file_picker: file:<pkg>/ohos` 依赖，模块名必须一致）。

未改动 `android/`、`ios/`、`macos/`、`ohos/` 的原生实现与 Dart 业务逻辑；`Platform.operatingSystem == 'ohos'`
→ `FilePickerIO`（MethodChannel `miguelruivo.flutter.plugins.filepicker`）的分支由上游 fork 自带。

## 升级/回滚

- 升级：取新 TAG 后重放上面 4 步（`sed`/脚本均可），再跑 `flutter pub get` + 五端回归。
- 回滚：`pubspec.yaml` 里把 `file_picker` 改回 `^10.3.10` hosted，删除本目录即可。
