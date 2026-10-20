import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/providers/download_provider.dart';
import 'package:fluxdo/services/download_service.dart';
import 'package:fluxdo/services/local_notification_service.dart'
    show navigatorKey;
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath, this.downloadsPath);

  final String documentsPath;
  String? downloadsPath;
  Object? downloadsError;
  int downloadsCalls = 0;

  @override
  Future<String?> getDownloadsPath() async {
    downloadsCalls++;
    final error = downloadsError;
    if (error != null) throw error;
    return downloadsPath;
  }

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

class _DeniedFile extends Fake implements File {
  _DeniedFile(this.path);

  @override
  final String path;

  @override
  void createSync({bool recursive = false, bool exclusive = false}) {
    throw PathAccessException(
      path,
      const OSError('Operation not permitted', 1),
      'Creation failed',
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const fileChannel = MethodChannel('com.fluxdo/public_file');
  late Directory sandbox;
  late PathProviderPlatform originalPathProvider;
  late _FakePathProvider pathProvider;
  late List<MethodCall> nativeCalls;
  PlatformException? backupError;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('fluxdo-download-dir-test-');
    originalPathProvider = PathProviderPlatform.instance;
    pathProvider = _FakePathProvider(
      p.join(sandbox.path, 'Documents'),
      p.join(sandbox.path, 'Downloads'),
    );
    PathProviderPlatform.instance = pathProvider;
    DownloadService.debugIsIOSOverride = true;
    nativeCalls = [];
    backupError = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(fileChannel, (
      call,
    ) async {
      nativeCalls.add(call);
      expect(call.method, 'excludeDownloadsFromBackup');
      expect(call.arguments, isNull);
      expect(
        Directory(p.join(pathProvider.documentsPath, 'Downloads')).existsSync(),
        isTrue,
        reason: '创建应用下载目录后再设置备份属性',
      );
      if (backupError != null) throw backupError!;
      return null;
    });
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPathProvider;
    DownloadService.debugIsIOSOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(fileChannel, null);
    sandbox.deleteSync(recursive: true);
  });

  test('iOS 直接使用 Documents/Downloads，不访问系统下载目录', () async {
    pathProvider.downloadsError = StateError('iOS 不应查询系统下载目录');

    final directory = await DownloadService.resolveDownloadDirectory();

    expect(directory.path, p.join(pathProvider.documentsPath, 'Downloads'));
    expect(await directory.exists(), isTrue);
    expect(pathProvider.downloadsCalls, 0);
    expect(await Directory(pathProvider.downloadsPath!).exists(), isFalse);
    expect(nativeCalls, hasLength(1));
    final reservation = DownloadService.reserveAvailableDownload(
      directory: directory,
      fileName: '2026-10-19-人工智能.pdf',
    );
    await File(reservation.temporaryPath).writeAsString('download content');
    await reservation.commit();
    expect(File(reservation.savePath).readAsStringSync(), 'download content');
  });

  test('iOS 复用已有目录并保留已有文件', () async {
    final directory = Directory(
      p.join(pathProvider.documentsPath, 'Downloads'),
    );
    await directory.create(recursive: true);
    final existing = File(p.join(directory.path, 'existing.pdf'));
    await existing.writeAsString('existing content');

    expect(
      (await DownloadService.resolveDownloadDirectory()).path,
      directory.path,
    );
    expect(await existing.readAsString(), 'existing content');
    expect(nativeCalls, hasLength(1));
  });

  test('iOS 目录创建失败时不查询其他位置或设置备份属性', () async {
    await File(pathProvider.documentsPath).writeAsString('blocked');

    await expectLater(
      DownloadService.resolveDownloadDirectory(),
      throwsA(isA<FileSystemException>()),
    );
    expect(pathProvider.downloadsCalls, 0);
    expect(nativeCalls, isEmpty);
  });

  test('iOS 排除备份失败时向调用方报告异常', () async {
    backupError = PlatformException(code: 'BACKUP_EXCLUSION_FAILED');

    await expectLater(
      DownloadService.resolveDownloadDirectory(),
      throwsA(isA<PlatformException>()),
    );
    expect(pathProvider.downloadsCalls, 0);
  });

  test('其他平台继续使用系统下载目录', () async {
    DownloadService.debugIsIOSOverride = false;

    final directory = await DownloadService.resolveDownloadDirectory();

    expect(directory.path, pathProvider.downloadsPath);
    expect(await directory.exists(), isTrue);
    expect(pathProvider.downloadsCalls, 1);
    expect(nativeCalls, isEmpty);
  });

  for (final unsupported in [false, true]) {
    test('其他平台下载目录${unsupported ? '不支持' : '为空'}时保留原有文档目录回退', () async {
      DownloadService.debugIsIOSOverride = false;
      pathProvider.downloadsPath = null;
      if (unsupported) {
        pathProvider.downloadsError = UnsupportedError('downloads unavailable');
      }

      final directory = await DownloadService.resolveDownloadDirectory();

      expect(directory.path, p.join(pathProvider.documentsPath, 'Downloads'));
      expect(await directory.exists(), isTrue);
      expect(nativeCalls, isEmpty);
    });
  }

  for (final stage in ['创建目录', '预留文件', '设置属性']) {
    testWidgets('目录准备阶段$stage失败时提示用户，不生成下载记录', (tester) async {
      if (stage == '设置属性') {
        backupError = PlatformException(code: 'BACKUP_EXCLUSION_FAILED');
      } else if (stage == '创建目录') {
        File(pathProvider.documentsPath).writeAsStringSync('blocked');
      }
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = DownloadNotifier(prefs);
      addTearDown(notifier.dispose);
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: SizedBox.shrink()),
          ),
        ),
      );

      await tester.runAsync(
        () => IOOverrides.runZoned(
          () => notifier.startDownload(
            url: 'https://linux.do/uploads/short-url/example.pdf',
            suggestedFilename: '附件.pdf',
          ),
          createFile: stage == '预留文件' ? _DeniedFile.new : null,
        ),
      );
      await tester.pumpAndSettle();

      expect(notifier.state, isEmpty);
      expect(prefs.getString('download_items'), isNull);
      expect(find.text(S.current.myBrowser_downloadFailed), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }
}
