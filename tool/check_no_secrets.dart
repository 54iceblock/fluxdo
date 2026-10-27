// 签名材料守卫：防止「本机签名配置被误提交」再次发生。
//
// 背景：`ohos/build-profile.json5` 曾被提交进 DevEco 自动写入的 signingConfigs，
// 含本机证书绝对路径与加密后的 keyPassword/storePassword（见 git 历史 f23ecc2）。
// 该文件因此成为「提交前必查」的高危文件。
//
// 用法：
//   dart run tool/check_no_secrets.dart          # 检查，命中即 exit 1
//   dart run tool/check_no_secrets.dart --fix    # 顺手把 signingConfigs 复位成 []
//   dart run tool/check_no_secrets.dart --verbose
//
// CI 与本地提交前都应跑；just 里也有 `just check-secrets`。
import 'dart:convert';
import 'dart:io';

/// 检查根目录（本文件位于 `tool/` 下）。
final Directory _root = File.fromUri(Platform.script).parent.parent;

/// 命中即失败的字符串特征（大小写敏感，避免误报）。
const List<String> _textNeedles = <String>[
  '"storePassword":',
  '"keyPassword":',
  '-----BEGIN RSA PRIVATE KEY-----',
  '-----BEGIN EC PRIVATE KEY-----',
  '-----BEGIN PRIVATE KEY-----',
];

/// 允许出现上述特征的文件（本守卫自身 + 明确的一次性测试密钥）。
const Set<String> _textAllowList = <String>{
  'tool/check_no_secrets.dart',
  // 单元测试用的临时 RSA 私钥（测试内生成/写死的测试向量，非真实证书）。
  'test/services/crypto/crypto_toolbox_test.dart',
};

/// 允许存在的密钥类文件后缀（示例/模板除外）。
const List<String> _secretFileExtensions = <String>[
  '.p12',
  '.p7b',
  '.jks',
  '.keystore',
  '.cer',
];

/// 与漏洞无关的重目录（体积大、第三方源码多、构建产物）。
const List<String> _skipDirs = <String>[
  '.git',
  '.dart_tool',
  '.hvigor', // hvigor 同步产物里会回显 DevEco 签名配置，属生成物
  'build',
  'oh_modules',
  'node_modules',
  '.cache',
  'third_party',
  '.pub-cache',
];

/// OHOS 签名配置的宿主文件。
const String _ohosBuildProfile = 'ohos/build-profile.json5';

bool _verbose = false;

Future<void> main(List<String> args) async {
  _verbose = args.contains('--verbose');
  final bool fix = args.contains('--fix');

  final List<String> problems = <String>[];

  _checkBuildProfile(problems, fix: fix);
  _checkSecretFiles(problems);
  _checkTextNeedles(problems);

  if (problems.isEmpty) {
    stdout.writeln('[check-no-secrets] OK：未发现签名材料泄漏。');
    return;
  }
  stderr.writeln('[check-no-secrets] 发现 ${problems.length} 项问题：');
  for (final String problem in problems) {
    stderr.writeln('  - $problem');
  }
  exitCode = 1;
}

/// 1) ohos/build-profile.json5 的 signingConfigs 必须为空数组。
void _checkBuildProfile(List<String> problems, {required bool fix}) {
  final File file = File('${_root.path}/$_ohosBuildProfile');
  if (!file.existsSync()) {
    problems.add('$_ohosBuildProfile 不存在（OHOS 工程丢失？）');
    return;
  }
  final String text = file.readAsStringSync();
  if (!text.contains('"signingConfigs": []')) {
    if (!fix) {
      problems.add(
        '$_ohosBuildProfile 的 signingConfigs 非空——DevEco 自动签名写回了本机证书。'
        '请改回 "signingConfigs": []（或 dart run tool/check_no_secrets.dart --fix）',
      );
      return;
    }
    final String repaired = _resetSigningConfigs(text);
    if (repaired == text) {
      problems.add('$_ohosBuildProfile 无法自动修复，请手工把 signingConfigs 改回 []');
      return;
    }
    file.writeAsStringSync(repaired);
    stdout.writeln('[check-no-secrets] 已自动复位 $_ohosBuildProfile 的 signingConfigs');
  }
}

/// 把 `"signingConfigs": [ ... ],` 整段替换为 `"signingConfigs": [],`
/// （保留数组前置注释，只吃掉数组本体）。
String _resetSigningConfigs(String text) {
  final RegExpMatch? match = RegExp(
    r'"signingConfigs"\s*:\s*\[',
  ).firstMatch(text);
  if (match == null) return text;
  int depth = 0;
  int end = -1;
  for (int i = match.end - 1; i < text.length; i++) {
    final String ch = text[i];
    if (ch == '[') {
      depth++;
    } else if (ch == ']') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  if (end < 0) return text;
  return '${text.substring(0, match.start)}"signingConfigs": []'
      '${text.substring(end + 1)}';
}

/// 2) 仓库里不应出现私钥/证书文件（`.p12`/`.p7b`/`.cer` ...）。
void _checkSecretFiles(List<String> problems) {
  for (final FileSystemEntity entity in _walk(_root)) {
    if (entity is! File) continue;
    final String path = entity.path;
    if (_allowed(path)) continue;
    final String lower = path.toLowerCase();
    for (final String ext in _secretFileExtensions) {
      if (lower.endsWith(ext)) {
        problems.add('发现疑似签名材料文件：${_rel(path)}（应放 .gitignore 或移出仓库）');
        break;
      }
    }
  }
}

/// 3) 文本文件里不应出现密码字段/私钥头。
void _checkTextNeedles(List<String> problems) {
  for (final FileSystemEntity entity in _walk(_root)) {
    if (entity is! File) continue;
    final String path = entity.path;
    if (_allowed(path)) continue;
    final String rel = _rel(path);
    if (_textAllowList.contains(rel)) continue;

    // 只读小文件、且看起来像文本的，避免把 .so/图片读进内存。
    final int size = entity.lengthSync();
    if (size > 512 * 1024) continue;
    final List<int> head = _readHead(entity, 4096);
    if (head.contains(0)) continue; // 二进制
    String text;
    try {
      text = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
    } on FileSystemException {
      continue;
    }
    for (final String needle in _textNeedles) {
      if (text.contains(needle)) {
        problems.add('$rel 含敏感特征 `$needle`');
        break;
      }
    }
  }
}

List<int> _readHead(File file, int maxBytes) {
  final RandomAccessFile raf = file.openSync();
  try {
    return raf.readSync(maxBytes);
  } finally {
    raf.closeSync();
  }
}

/// 白名单文件（仅守卫自身，避免自检误报）。
bool _allowed(String path) => _textAllowList.contains(_rel(path));

String _rel(String path) =>
    path.substring(_root.path.length + 1).replaceAll('\\', '/');

Iterable<FileSystemEntity> _walk(Directory dir) sync* {
  late final List<FileSystemEntity> children;
  try {
    children = dir.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final FileSystemEntity child in children) {
    final String name = child.uri.pathSegments.where((String s) => s.isNotEmpty).last;
    if (child is Directory) {
      if (_skipDirs.contains(name)) continue;
      yield* _walk(child);
    } else {
      if (_verbose) stdout.writeln('scan ${_rel(child.path)}');
      yield child;
    }
  }
}
