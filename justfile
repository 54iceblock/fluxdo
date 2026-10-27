set windows-shell := ["pwsh.exe", "-NoLogo", "-NoProfile", "-Command"]

# 显示可用命令
default:
  @just --list

# 初始化工作区依赖和链接
bootstrap:
  @dart run melos bootstrap

# 显式同步项目状态（pub get、l10n、证书资源）
sync:
  @dart run tool/project_prep.dart app

# 单独生成国际化代码
l10n:
  @dart run tool/gen_l10n.dart

# 校验国际化生成结果是否最新
l10n-check:
  @dart run tool/gen_l10n.dart --check

# 检查开发环境和生成产物状态
doctor:
  @dart run tool/project_prep.dart doctor

# 生成并同步代理证书资源
certs:
  @dart run tool/project_prep.dart certs

# 执行 flutter clean 并重置依赖指纹
clean:
  @dart run tool/project_tasks.dart app:clean

# 先 clean，再 build；额外参数透传给 flutter build
rebuild *args:
  @dart run tool/project_tasks.dart app:rebuild {{args}}

# 执行 flutter run；额外参数透传给 flutter run
run *args:
  @dart run tool/flutterw.dart run {{args}}

# 执行 flutter build；额外参数透传给 flutter build
build *args:
  @dart run tool/flutterw.dart build {{args}}

# 执行工作区测试；额外参数透传给 flutter test
test *args:
  @dart run tool/project_tasks.dart test:all {{args}}

# 执行 flutter drive；额外参数透传给 flutter drive
drive *args:
  @dart run tool/flutterw.dart drive {{args}}

# 显式准备平台原生产物；额外参数透传给 native:prepare
native *args:
  @dart run tool/project_tasks.dart native:prepare {{args}}

# 执行 flutter analyze；额外参数透传给 flutter analyze
analyze *args:
  @flutter analyze {{args}}

# 发版前检查、analyze、test
release-check *args:
  @dart run tool/project_tasks.dart release:prepare {{args}}

# 稳定版发版；无参时进入交互式流程
release *args:
  @dart run tool/release.dart --track release {{args}}

# 预发布发版；无参时进入交互式流程
prerelease *args:
  @dart run tool/release.dart --track prerelease {{args}}

# 构建 iOS 无签名 IPA；无参时进入版本输入和确认流程
ipa *args:
  @dart run tool/build_ipa_nosign.dart {{args}}

# 签名材料守卫：防 DevEco 把本机证书/密码写回 ohos/build-profile.json5 后误提交
check-secrets *args:
  @dart tool/check_no_secrets.dart {{args}}

# 检查 OHOS 专用 git 依赖是否全部锁定到 commit SHA；--portable 输出可跨平台发布的 pubspec
check-pubspec *args:
  @dart tool/check_ohos_pubspec.dart {{args}}
