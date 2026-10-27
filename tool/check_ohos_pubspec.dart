// OHOS 依赖审计：git 依赖必须锁定 commit，且非 OHOS 平台要能用上游版本构建。
//
// 背景（审核发现的两个问题）：
//  1) 之前多个 git 依赖写的是**分支名**（`ref: main`、`ref: br_3.41_dev` 等）。
//     分支会被上游持续提交，也可能被 force-push —— 同一份 pubspec 在不同时间
//     解析出不同代码，构建不可复现，`pubspec.lock` 一删就漂移。
//  2) 单 pubspec 策略下，`dependency_overrides` 里的 OHOS fork 对 Android/iOS/
//     桌面端**同样生效**（inappwebview 6.2.0-beta.3→6.1.5、mobile_scanner
//     7.4.2→7.1.4、device_info_plus 12.3.0 fork 等），非 OHOS 平台存在回归风险。
//
// 用法：
//   dart run tool/check_ohos_pubspec.dart              # 校验：所有 git 依赖都锁到 SHA，且与 lock 一致
//   dart run tool/check_ohos_pubspec.dart --portable <输出路径>
//       生成一份「去掉 OHOS 专属 override」的 pubspec（默认 .tmp/pubspec.portable.yaml），
//       用它跑 `flutter pub get` + 目标平台构建，即可验证上游版本仍可编译。
//
// just 配方：`just check-pubspec`、`just check-pubspec --portable`
import 'dart:convert';
import 'dart:io';

/// 仓库根目录：默认是本文件所在仓库（`tool/` 的上一级），测试可用 `--root <dir>` 覆盖。
Directory _root = File.fromUri(Platform.script).parent.parent;

/// 仅为了 OHOS 才存在的 override：非 OHOS 平台应使用上游版本。
/// 新增 OHOS fork 时必须登记到这里，否则 --portable 会漏掉。
const Set<String> _ohosOnlyOverrides = <String>{
  'device_info_plus',
  'connectivity_plus',
  'open_filex',
  'mobile_scanner',
  'volume_controller',
  'app_links',
  'flutter_local_notifications',
  'sqflite',
  'flutter_inappwebview',
  'flutter_inappwebview_platform_interface',
  'ota_update',
};

/// 便携版要**恢复成上游形态**的 override（不是简单删掉）。
///
/// `device_info_plus` 上游本来就有一条 hosted pin：`super_clipboard ^0.9.1` 要求
/// `device_info_plus <12.0.0`，而上游业务代码用 12.3.0，只能靠 override 压过去。
/// OHOS 版把这条换成了 git fork；便携版若直接删掉，非 OHOS 平台会
/// `version solving failed`（实测）。
const Map<String, String> _portableRestore = <String, String>{
  'device_info_plus': '  device_info_plus: 12.3.0',
};

/// 上游有、但 OHOS 移植为了构建通过而删掉的 override —— 便携版必须补回，
/// 否则桌面端会丢掉 vendored 的 inappwebview 修复（Windows 析构 UAF 闪退）。
const String _portableExtraOverrides = '''  flutter_inappwebview_linux:
    path: packages/flutter_inappwebview_linux
  # Windows 插件析构存在悬垂 this 回调 UAF(CF 验证 WebView 销毁时闪退)
  flutter_inappwebview_windows:
    path: packages/flutter_inappwebview_windows''';

final RegExp _sha40 = RegExp(r'^[0-9a-f]{40}$');

Future<void> main(List<String> args) async {
  // 统一 UTF-8 输出：Windows 控制台默认代码页会把中文/路径变成乱码
  stdout.encoding = utf8;
  stderr.encoding = utf8;
  final int rootIndex = args.indexOf('--root');
  if (rootIndex >= 0 && rootIndex + 1 < args.length) {
    _root = Directory(args[rootIndex + 1]).absolute;
  }
  final int portableIndex = args.indexOf('--portable');
  if (portableIndex >= 0) {
    final String out = portableIndex + 1 < args.length &&
            !args[portableIndex + 1].startsWith('-')
        ? args[portableIndex + 1]
        : '.dart_tool/pubspec.portable.yaml';
    await _writePortable(out);
    return;
  }

  final List<String> problems = <String>[];
  final _PubspecScan scan = _scanPubspec(File('${_root.path}/pubspec.yaml'));
  problems.addAll(scan.problems);
  problems.addAll(_checkLock(scan));

  stdout.writeln(
    '[check-pubspec] 扫描到 ${scan.gitDependencies.length} 个 git 依赖、'
    '${scan.overrides.length} 个 override（其中 OHOS 专属 ${_ohosOnlyOverrides.length} 个）。',
  );

  if (problems.isEmpty) {
    stdout.writeln('[check-pubspec] OK：所有 git 依赖都锁定到 commit SHA，且与 pubspec.lock 一致。');
    return;
  }
  stderr.writeln('[check-pubspec] 发现 ${problems.length} 项问题：');
  for (final String p in problems) {
    stderr.writeln('  - $p');
  }
  exitCode = 1;
}

/// `dependencies:` / `dependency_overrides:` 里所有 git 依赖的 ref。
class _GitDep {
  _GitDep(this.name, this.ref, this.section);

  final String name;
  final String ref;
  final String section;
}

class _PubspecScan {
  final List<_GitDep> gitDependencies = <_GitDep>[];
  final Set<String> overrides = <String>{};
  final List<String> problems = <String>[];
}

/// 逐行扫描 pubspec.yaml：不依赖 yaml 包，保持脚本零依赖可独立执行。
_PubspecScan _scanPubspec(File file) {
  final _PubspecScan scan = _PubspecScan();
  final List<String> lines = const LineSplitter().convert(file.readAsStringSync());

  String section = '';
  String? currentName;

  void flush() {
    final String? name = currentName;
    if (name == null) return;
    final String? ref = _findRefInBlock(lines, name);
    if (ref != null) {
      scan.gitDependencies.add(_GitDep(name, ref, section));
      if (!_sha40.hasMatch(ref)) {
        scan.problems.add(
          '$section > $name 的 git ref 不是 40 位 commit SHA：`$ref`'
          '（分支名会让依赖不可复现）',
        );
      }
    }
    currentName = null;
  }

  for (final String line in lines) {
    if (line.trimLeft().startsWith('#')) continue;
    if (line.trim().isEmpty) continue;
    final int indent = line.length - line.trimLeft().length;
    final String trimmed = line.trim();

    if (indent == 0) {
      flush();
      section = trimmed.endsWith(':') ? trimmed.substring(0, trimmed.length - 1) : '';
      continue;
    }
    if (section != 'dependencies' && section != 'dependency_overrides') continue;

    if (indent == 2 && trimmed.endsWith(':')) {
      flush();
      final String name = trimmed.substring(0, trimmed.length - 1);
      currentName = name;
      if (section == 'dependency_overrides') scan.overrides.add(name);
      continue;
    }
    if (indent == 2 && trimmed.contains(':')) {
      // 形如 `package: 1.2.3` 的单行依赖：不是 git，忽略。
      flush();
      continue;
    }
  }
  flush();
  return scan;
}

/// 在文本里定位某个依赖块（2 空格缩进开始，遇到下一个 2 空格缩进键结束）。
String? _findRefInBlock(List<String> lines, String name) {
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    if (line.trim() != '$name:') continue;
    final int indent = line.length - line.trimLeft().length;
    for (int j = i + 1; j < lines.length; j++) {
      final String body = lines[j];
      if (body.trim().isEmpty) continue;
      final int bodyIndent = body.length - body.trimLeft().length;
      if (bodyIndent <= indent) break;
      final RegExpMatch? m = RegExp(r'^\s+ref:\s*(\S+)\s*$').firstMatch(body);
      if (m != null) return m.group(1)!.replaceAll('"', '').replaceAll("'", '');
    }
    return null;
  }
  return null;
}

/// pubspec.lock 里的 `ref` 必须与 pubspec 一致（防止改了 pubspec 忘跑 pub get）。
List<String> _checkLock(_PubspecScan scan) {
  final File lock = File('${_root.path}/pubspec.lock');
  if (!lock.existsSync()) return const <String>[];
  final List<String> lines = const LineSplitter().convert(lock.readAsStringSync());
  final Map<String, String> lockRefs = <String, String>{};
  String? current;
  int currentIndent = 0;
  for (final String line in lines) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final int indent = line.length - line.trimLeft().length;
    final String trimmed = line.trim();
    if (indent == 2 && trimmed.endsWith(':')) {
      current = trimmed.substring(0, trimmed.length - 1);
      currentIndent = indent;
      continue;
    }
    if (current == null || indent <= currentIndent) continue;
    final RegExpMatch? m = RegExp(r'^ref:\s*(\S+)$').firstMatch(trimmed);
    if (m != null) {
      lockRefs[current] = m.group(1)!.replaceAll('"', '');
    }
  }
  final List<String> problems = <String>[];
  for (final _GitDep dep in scan.gitDependencies) {
    final String? lockRef = lockRefs[dep.name];
    if (lockRef == null) continue; // 不是直接依赖或被 pub 合并，跳过
    if (lockRef != dep.ref) {
      problems.add(
        '${dep.name}: pubspec 的 ref(${dep.ref}) 与 pubspec.lock($lockRef) 不一致'
        '——改完 ref 记得跑 `flutter pub get`',
      );
    }
  }
  return problems;
}

/// 生成「还原成上游形态」的 pubspec，供非 OHOS 平台验证上游版本可用。
///
/// 注意不是简单「删掉 OHOS override」：
///  - `_portableRestore` 里的键要恢复成上游的 hosted pin（否则 version solving 失败）；
///  - `_portableExtraOverrides` 是上游有、OHOS 版删掉的 override，必须补回。
Future<void> _writePortable(String outPath) async {
  final File file = File('${_root.path}/pubspec.yaml');
  final List<String> lines = const LineSplitter().convert(file.readAsStringSync());
  final List<String> out = <String>[];
  bool inOverrides = false;
  bool dropping = false;
  // 段内注释先缓存：紧跟在被删/被替换块上方的说明，随该块一起丢掉
  final List<String> pendingComments = <String>[];
  bool injected = false;

  for (final String line in lines) {
    final String trimmed = line.trim();
    final int indent = line.length - line.trimLeft().length;

    if (indent == 0 && !trimmed.startsWith('#')) {
      inOverrides = trimmed == 'dependency_overrides:';
      dropping = false;
      pendingComments.clear();
      out.add(line);
      // 直接在本段开头注入：YAML 里 override 顺序无关，避免"记住插入位置"那类
      // 索引漂移 bug（上一版就把 git 子块残留到了错误位置）。
      if (inOverrides && !injected) {
        out.addAll(_portableRestore.values);
        out.add(_portableExtraOverrides);
        injected = true;
      }
      continue;
    }
    if (!inOverrides) {
      out.add(line);
      continue;
    }

    if (indent == 2 && trimmed.startsWith('#')) {
      pendingComments.add(line);
      continue;
    }

    final RegExpMatch? key =
        indent == 2 ? RegExp(r'^([A-Za-z0-9_]+):').firstMatch(trimmed) : null;
    if (key != null) {
      final String name = key.group(1)!;
      // 被删掉的 OHOS fork，以及已被还原成上游形态的键，整块（含 git 子块）都丢弃
      dropping =
          _ohosOnlyOverrides.contains(name) || _portableRestore.containsKey(name);
      if (dropping) {
        pendingComments.clear();
        continue;
      }
      out.addAll(pendingComments);
      pendingComments.clear();
      out.add(line);
      continue;
    }

    // 块内更深缩进的行
    if (dropping) continue;
    out.addAll(pendingComments);
    pendingComments.clear();
    out.add(line);
  }

  if (!injected) {
    stderr.writeln(
      '[check-pubspec] 警告：pubspec.yaml 里没有 dependency_overrides 段，'
      '便携版缺少 device_info_plus 的 hosted pin（super_clipboard 会解析失败）',
    );
  }

  // 相对路径按仓库根解析（不受当前工作目录影响）
  final File target = File(outPath).isAbsolute
      ? File(outPath)
      : File('${_root.path}/$outPath');
  target.parent.createSync(recursive: true);
  target.writeAsStringSync(
    '# 由 `dart tool/check_ohos_pubspec.dart --portable` 生成：\n'
    '# 已移除 OHOS 专属 override，并把上游有、OHOS 版替换/删除的 override 还原，\n'
    '# 用于 Android/iOS/桌面端回归验证。不要手工编辑、也不要提交本文件。\n'
    '${out.join('\n')}\n',
  );
  stdout.writeln('[check-pubspec] 已生成便携版 pubspec：$outPath');
  stdout.writeln('  下一步：cp $outPath pubspec.yaml && flutter pub get && <目标平台构建>');
}
