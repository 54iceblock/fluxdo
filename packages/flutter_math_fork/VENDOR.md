# VENDOR：flutter_math_fork（OHOS 补丁副本）

| 项 | 内容 |
|---|---|
| 上游 | pub.dev `flutter_math_fork` 0.7.4（<https://github.com/simpleclub/flutter_math>） |
| 许可证 | Apache-2.0（见同目录 `LICENSE`） |
| 改动日期 | 2026-10-21（OHOS 移植构建期修复，Lead 执行） |

## 为什么需要副本

Flutter OHOS 分支新增了 `TargetPlatform.ohos` 枚举。`flutter_math_fork` 0.7.4 里对 `TargetPlatform` 的
`switch` 是穷尽匹配（没有 default 分支），在 OHOS 上编译直接报
`type 'TargetPlatform' is not exhaustively matched by cases`。

## 本地改动（4 处，均为补 `case TargetPlatform.ohos:`）

- `lib/src/widgets/selection/gesture_detector_builder_selectable.dart`
- `lib/src/widgets/selectable.dart`（2 处）
- `lib/src/render/layout/line_editable.dart`

语义上与 Android 分支一致（触屏双击选词/选择手柄行为）。Dart 业务逻辑无其它改动。

## 接入方式

`repo/pubspec.yaml`：

```yaml
dependency_overrides:
  flutter_math_fork:
    path: packages/flutter_math_fork
```

## 升级/回滚

- 升级：上游若已支持 `TargetPlatform.ohos`（0.7.5+/新版本），删除 override 与目录即可。
- 回滚：删除 override + 本目录（注意：OHOS 将无法编译）。
