import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../cf_challenge_service.dart';
import '../../cf_challenge_logger.dart';
import '../../cf_clearance_refresh_service.dart';
import '../../cf_clearance_authority.dart';
import '../../app_logger.dart';
import '../adapters/platform_adapter.dart';
import '../cookie/boundary_sync_service.dart';
import '../cookie/cookie_jar_service.dart';
import '../system_proxy_service.dart';
import '../webview/webview_adapter_settings_service.dart';
import '../../../l10n/s.dart';
import '../../../utils/platform_utils.dart';
import '../exceptions/api_exception.dart';
import '../flux_request_spec.dart';
import '../health/network_health_controller.dart';

/// Cloudflare 验证拦截器
///
/// **为什么它不在恢复层里**(2026-08 评估结论,别再迁):
///
/// 恢复层的契约是"策略只产决策、Coordinator 统一执行重放",这对无状态恢复
/// (限流等待、瞬态重放、会话自愈、引擎降级)成立,但 CF 的重试**之后**还有
/// 三段有状态处置:
/// 1. 重试成功 → 广播 [CfChallengeService.clearanceResolvedAt],
///    BrowserTrustCoordinator 靠它 force 重跑被同一次 CF 挡下的 bootstrap;
/// 2. 重试仍被拦 → 在同一上下文里判断能否切兼容、弹询问、撤 skipWebViewAdapter,
///    **换传输方式再重放一次**;
/// 3. 兼容重放失败 → 回滚 sessionFallback,否则后续请求全锁死在坏通道上。
///
/// 第 2、3 步要求"拿到重试结果后决定下一次用什么传输方式,并在失败时回滚
/// 副作用",而策略拿不到重试结果——重放执行权在 Coordinator 手里。硬迁的
/// 三条路都有害:为单个策略给 RecoveryDecision 加变体会污染通用抽象;策略
/// 自己调 dio.fetch 违反"重放只有一处"这条铁律(等于把六个重放入口的病灶
/// 重新引入);拆成多策略靠预算串联会丢掉回滚的时序保证。
///
/// 所以现状是**终态**:恢复层管无状态重放,本拦截器管需要 UI 交互与传输
/// 切换的有状态恢复。分界由 RateLimitPolicy 的 isChallengeResponse 钩子
/// 划定——挑战型 429 放行给这里,真限流归恢复层。
class CfChallengeInterceptor extends Interceptor {
  CfChallengeInterceptor({required this.dio, required this.cookieJarService});

  final Dio dio;
  final CookieJarService cookieJarService;

  /// 共享的 cookie 同步 Future：验证成功后只执行一次 sync
  static Future<void>? _activeSyncFuture;

  static const _mutationMethods = {'POST', 'PUT', 'DELETE', 'PATCH'};

  /// 验证成功后的共享 Cookie 同步（只执行一次）
  Future<void> _syncCookiesOnce() async {
    // 如果已有同步任务在进行，复用结果
    if (_activeSyncFuture != null) return _activeSyncFuture!;

    _activeSyncFuture = _doSync();
    try {
      return await _activeSyncFuture!;
    } finally {
      _activeSyncFuture = null;
    }
  }

  Future<void> _doSync() async {
    try {
      await CfChallengeService().waitForCompletionCookieSync();
      // 已有值时直接复用；没有时只同步一次当前快照。验证入口可能直接
      // 放行而不签发 Cookie，不能等待续期，也不能因此拒绝原请求。
      final clearance = await cookieJarService.getCfClearance();
      if (clearance != null && clearance.isNotEmpty) return;
      await BoundarySyncService.instance.syncFromWebView(
        cookieNames: {'cf_clearance'},
      );
    } catch (e) {
      CfChallengeLogger.log(
        '[INTERCEPTOR] Cookie sync unavailable; retrying with current cookies: $e',
        level: 'warning',
      );
    }
  }

  bool _shouldShowActionPrompt(RequestOptions options) {
    final spec = options.spec;
    if (spec.isSilent) return false;
    if (spec.hasExplicitErrorToast) {
      return spec.showErrorToast;
    }
    return _mutationMethods.contains(options.method.toUpperCase());
  }

  String _requestMode(RequestOptions options) {
    if (options.spec.isSilent) return 'silent';
    return _shouldShowActionPrompt(options) ? 'action' : 'data';
  }

  Future<void> _refreshCookieHeader(RequestOptions options) async {
    options.headers.remove('cookie');
    options.headers.remove('Cookie');

    final cookieHeader = await cookieJarService.getCookieHeaderForRequest(
      options.uri,
    );
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      options.headers['Cookie'] = cookieHeader;
    }
  }

  /// 用浏览器网络栈（WebViewHttpAdapter：ArkWeb 内 JS fetch）重放请求。
  ///
  /// HarmonyOS 上这是唯一稳定能过 CF 的通道：请求由 ArkWeb 内核发出，
  /// HttpOnly 的 `cf_clearance` 由内核自己带，不需要导出到原生 CookieJar。
  ///
  /// 成功返回 response（并顺手关闭可能正在展示的验证浮层）；失败返回 null
  /// 并回滚本次调用引入的副作用（会话兼容开关 / extra 标记），让调用方可以
  /// 继续走原有的验证流程。
  /// 浏览器网络栈重放的单次上限。
  ///
  /// 第 3 轮回归实测过：WebViewAdapter 在 OHOS 上可能挂死（JS fetch 结果
  /// 回不到 Dart），若不加这层上限，请求会一直挂着、冷启动卡在启动页。
  /// 超时后直接放弃这次重放、回退到原有的验证流程/错误处理，保证「失败也
  /// 要能自动回退」。
  static const Duration _browserStackReplayTimeout = Duration(seconds: 12);

  Future<Response<dynamic>?> _replayViaBrowserStack(
    RequestOptions options, {
    required CfChallengeService cfService,
    required String reason,
    required String url,
  }) async {
    final settings = WebViewAdapterSettingsService.instance;
    final wasEffective = settings.effectiveEnabled;
    final hadSkipCf = options.extra.containsKey(
      FluxRequestKeys.skipCfChallenge,
    );
    final hadSkipBlock = options.extra.containsKey(FluxRequestKeys.skipCfBlock);
    final hadSkipAdapter =
        options.extra[FluxRequestKeys.skipWebViewAdapter] == true;

    settings.enableSessionFallback();
    options.extra[FluxRequestKeys.skipCfChallenge] = true;
    options.extra[FluxRequestKeys.skipCfBlock] = true;
    options.extra.remove(FluxRequestKeys.skipWebViewAdapter);

    void rollback() {
      if (!wasEffective && !settings.persistentEnabled) {
        settings.disableSessionFallback();
      }
      if (!hadSkipCf) options.extra.remove(FluxRequestKeys.skipCfChallenge);
      if (!hadSkipBlock) options.extra.remove(FluxRequestKeys.skipCfBlock);
      if (hadSkipAdapter) {
        options.extra[FluxRequestKeys.skipWebViewAdapter] = true;
      }
    }

    try {
      final response = await dio
          .fetch(options)
          .timeout(
            _browserStackReplayTimeout,
            onTimeout: () => throw TimeoutException(
              'browser stack replay timeout '
              '(${_browserStackReplayTimeout.inSeconds}s)',
            ),
          );
      debugPrint(
        '[Dio][OHOS] 浏览器网络栈重放成功($reason): '
        'status=${response.statusCode} url=$url',
      );
      // 兜底成功 = CF 已解决：主动关闭可能正在展示的验证浮层，避免用户
      // 必须先点「退出」再点页面的「重试连接」。
      cfService.dismissActiveVerificationAsSuccess(reason: reason);
      return response;
    } catch (e) {
      rollback();
      debugPrint('[Dio][OHOS] 浏览器网络栈重放失败($reason): $e');
      CfChallengeLogger.log(
        '[INTERCEPTOR][OHOS] browser stack replay failed ($reason): $e',
        level: 'warning',
      );
      return null;
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;

    // 检查是否标记跳过 CF 验证（防止重试后再次触发）
    final skipCfChallenge = err.requestOptions.spec.skipCfChallenge;

    // CF 速率限制规则的 action 配为 managed_challenge / js_challenge / challenge 时,
    // 触发后返回 429 + cf-mitigated: challenge + 挑战页,而不是 403。
    // 因此 403 / 429 都要走 CF 验证流程,由 isCfChallengeResponse 精确判定。
    if ((statusCode == 403 || statusCode == 429) &&
        !skipCfChallenge &&
        CfChallengeService.isCfChallengeResponse(err.response)) {
      // 备选提取 sitekey（从 403 响应体中）
      CfClearanceRefreshService().extractAndUpdateSitekey(
        err.response?.data?.toString() ?? '',
      );
      // 403 说明 cf_clearance 已失效，停止自动续期（避免与手动验证冲突）。
      // 这里不需要 await——真正要建验证 WebView 前，showManualVerify 内部
      // 会自己再 await 一次 stop()，确保销毁完成。
      unawaited(CfClearanceRefreshService().stop());

      final requestUrl = err.requestOptions.uri.toString();
      final requestMethod = err.requestOptions.method.toUpperCase();
      final requestTag = err.requestOptions.spec.requestTag;
      final logMessage =
          'CF Challenge detected: $requestMethod $requestUrl '
          '(status=$statusCode, silent=${err.requestOptions.spec.isSilent}, '
          'tag=${requestTag ?? '-'}, skipCsrf=${err.requestOptions.spec.skipCsrf})';
      debugPrint('[Dio] $logMessage');
      AppLogger.warning(logMessage, tag: 'CfChallengeInterceptor');
      // 撞盾是排查网络问题的关键时刻:把此刻的通道健康全貌拍进日志,
      // 免得事后只有"某请求 403"这一条结果、没有引擎/降级/凭证状态。
      NetworkHealthController.instance.dumpToLog('cf_challenge_detected');
      // 命中 CF 盾时立即重读系统代理状态:若用户刚开/关了系统代理,
      // 下一个请求就能用一致的出口重试,而不是等 10s 周期刷新。
      SystemProxyService.instance.refresh();
      CfChallengeLogger.logInterceptorDetected(
        url: requestUrl,
        statusCode: statusCode!,
      );
      // 记录在位值被撞：本次请求携带的 cf_clearance 已被 CF 挑战（= 已死），
      // 打开换届窗口——之后 sync 可以替换它（过盾新值继位，或 Turnstile
      // 最新铸值无缝补位）。这里不做任何候选值判定、不分 403/429：
      // 撞了就过盾，语义见 CfClearanceAuthority。
      CfClearanceAuthority.instance.noteIncumbentChallenged(
        CfClearanceAuthority.extractFromCookieHeader(
          err.requestOptions.headers['Cookie']?.toString() ??
              err.requestOptions.headers['cookie']?.toString(),
        ),
      );
      final cfService = CfChallengeService();
      final isSilent = err.requestOptions.spec.isSilent;
      final shouldShowActionPrompt = _shouldShowActionPrompt(
        err.requestOptions,
      );
      final requestMode = _requestMode(err.requestOptions);

      DioException cfException(CfChallengeException error) {
        return DioException(
          requestOptions: err.requestOptions,
          error: error,
          type: DioExceptionType.unknown,
        );
      }

      if (!cfService.autoVerifyEnabled) {
        CfChallengeLogger.log(
          '[INTERCEPTOR] Auto verify disabled, rejecting: '
          '$requestMethod $requestUrl mode=$requestMode',
        );
        return handler.reject(
          cfException(CfChallengeException(autoVerifyDisabled: true)),
        );
      }

      // 注:这里刻意**不**用 NetworkHealthController.hasForegroundUi 提前判掉
      // 无 UI 环境。它的判据是 navigatorKey.currentContext,而主 isolate 启动
      // 早期那也是 null —— 提前 reject 会毁掉"启动时撞盾、等 context 就绪后
      // 补弹验证"这条路径(启动窗口恰恰是验证最该成功的时候)。
      // 无 UI 环境由 showManualVerify 内部的 10s context 等待上限收口。

      if (cfService.isInCooldown) {
        debugPrint('[Dio] CF Challenge in cooldown, rejecting request');
        CfChallengeLogger.log(
          '[INTERCEPTOR] Cooldown after 403: $requestMethod $requestUrl '
          'mode=$requestMode',
        );
        if (shouldShowActionPrompt) {
          CfChallengeService.showGlobalMessage(
            S.current.cf_operationBlockedByChallenge,
          );
        }
        return handler.reject(
          cfException(CfChallengeException(inCooldown: true)),
        );
      }

      // HarmonyOS：CF 只认浏览器会话（宿主机直连实测 403 + cf-mitigated:
      // challenge），原生 dart:io 栈拿不到 HttpOnly 的 cf_clearance。冷启动
      // 第一个主站请求若先走原生，必然 403 并弹出「安全验证」浮层，用户还得
      // 「退出 + 重试连接」两步才能看到数据。这里在**弹浮层之前**先用浏览器
      // 网络栈重放：成功就直接返回，全程无感。
      if (PlatformUtils.isOhos &&
          requestCanUseWebViewAdapter(err.requestOptions)) {
        debugPrint(
          '[CfChallenge][OHOS] 首次即走浏览器栈: $requestMethod $requestUrl '
          '(mode=$requestMode)',
        );
        final replay = await _replayViaBrowserStack(
          err.requestOptions,
          cfService: cfService,
          reason: 'pre_verify',
          url: requestUrl,
        );
        if (replay != null) {
          return handler.resolve(replay);
        }
        debugPrint('[CfChallenge][OHOS] 首次即走浏览器栈未成功，回退验证浮层');
      }

      // 静默请求只在后台尝试验证；页面数据/操作请求在前台展示验证。
      // (Windows 曾因插件析构竞态崩溃 0xc0000005 禁用过静默后台验证;
      // vendored 插件的 aliveGuard/TextureBridge 修复落地后恢复。)
      final result = await cfService.showManualVerify(null, !isSilent);

      if (result == true) {
        await _syncCookiesOnce();

        // 各自重试自己的原始请求（每个请求 URL/参数不同，无法共享）
        final retryOptions = err.requestOptions;
        try {
          retryOptions.extra[FluxRequestKeys.skipCfChallenge] = true;
          // 绕过 RequestScheduler 的 CF 冻结判定。retry 时序上 isVerifying 已经
          // 复位为 false，但加这个标记是双保险，防止未来逻辑变更引入 race。
          retryOptions.extra[FluxRequestKeys.skipCfBlock] = true;
          // 清除原始请求中残留的 cookie header，并补上最新 Cookie。
          // 这样即使 dio.fetch 不重新经过 CookieManager，也不会继续发送旧值。
          await _refreshCookieHeader(retryOptions);
          // 诊断：记录 CookieJar 中的 cookie 名称和 cf_clearance 状态
          final cookieHeader =
              retryOptions.headers['Cookie']?.toString() ??
              retryOptions.headers['cookie']?.toString();
          final hasCfClearance =
              cookieHeader?.contains('cf_clearance=') ?? false;
          final cookieNames = cookieHeader
              ?.split('; ')
              .map((c) => c.split('=').first)
              .join(', ');
          debugPrint(
            '[Dio] Retry cookies: ${hasCfClearance ? "✓ 包含 cf_clearance" : "⚠️ 缺少 cf_clearance"}, '
            'names=[$cookieNames], total=${cookieHeader?.length ?? 0} chars',
          );
          final response = await dio.fetch(retryOptions);
          CfChallengeLogger.logInterceptorRetry(
            url: requestUrl,
            success: true,
            statusCode: response.statusCode,
          );
          // 广播:Dio 侧真实重试成功。供 BrowserTrustCoordinator
          // 感知"CF 已解决",从而 force 重跑因同一 CF 失败的 WebView session bootstrap。
          cfService.clearanceResolvedAt.value = DateTime.now();
          return handler.resolve(response);
        } catch (e) {
          final retryStillBlockedByCf =
              e is DioException &&
              (e.response?.statusCode == 403 ||
                  e.response?.statusCode == 429) &&
              CfChallengeService.isCfChallengeResponse(e.response);

          // 验证入口已无盾，原生链路仍被 CF 拒绝。浏览器与原生通道的
          // 放行结果可能不同，仅对用户可见请求询问一次，
          // 用户确认后本次会话改用浏览器网络栈，并立即重放原请求。
          //
          // HarmonyOS 例外：验证页「无盾」不等于原生栈能过 CF —— linux.do
          // 前置的 Cloudflare 对所有非浏览器客户端返回
          // `403 + cf-mitigated: challenge`（宿主机 Node 直连实测）。而
          // cf_clearance 是 HttpOnly cookie，ArkWeb 只暴露
          // `WebCookieManager.fetchCookieSync(url)`，原生 dio 侧拿不到它。
          // 唯一稳定通过的通道是让请求由 ArkWeb 内核自己发出（浏览器网络
          // 栈）。因此该平台上不弹「切兼容模式」询问，直接自动切换重放。
          final retryHeaderHasClearance =
              (retryOptions.headers['Cookie']?.toString() ??
                      retryOptions.headers['cookie']?.toString() ??
                      '')
                  .contains('cf_clearance=');
          final canUseBrowserStack = requestCanUseWebViewAdapter(retryOptions);
          final ohosAutoFallback =
              PlatformUtils.isOhos &&
              canUseBrowserStack &&
              !retryHeaderHasClearance;
          if (PlatformUtils.isOhos && retryStillBlockedByCf) {
            // 判定行：无论走不走兜底，都把三个闸门值打出来，避免「没触发」
            // 时只能靠猜（上一轮就是卡在 canUseBrowserStack=false）。
            debugPrint(
              '[Dio][OHOS] 重试仍被 CF 挡: '
              'hasClearance=${retryHeaderHasClearance ? 1 : 0} '
              'canUseBrowserStack=${canUseBrowserStack ? 1 : 0} '
              'autoFallback=${ohosAutoFallback ? 1 : 0} '
              'silent=${isSilent ? 1 : 0}',
            );
          }
          if (ohosAutoFallback) {
            CfChallengeLogger.log(
              '[INTERCEPTOR][OHOS] no cf_clearance in retry cookie header; '
              'auto switch to browser network stack',
              level: 'warning',
            );
          }

          if (retryStillBlockedByCf &&
              (!isSilent || ohosAutoFallback) &&
              canUseBrowserStack) {
            final webViewSettings = WebViewAdapterSettingsService.instance;
            final shouldFallback =
                webViewSettings.effectiveEnabled ||
                ohosAutoFallback ||
                await cfService.confirmSessionCompatibilityMode();
            if (shouldFallback) {
              webViewSettings.enableSessionFallback();
              // 撤销原请求的"禁走 WebView 适配器"标记,这一行才是让重放
              // 真正改走浏览器网络栈的开关。
              retryOptions.extra.remove(FluxRequestKeys.skipWebViewAdapter);
              try {
                // 与 _replayViaBrowserStack 一致：给浏览器栈重放一个硬上限，
                // 防止 WebViewAdapter 在 OHOS 上挂死把请求（乃至冷启动）拖住。
                final fallbackResponse = await dio
                    .fetch(retryOptions)
                    .timeout(
                      _browserStackReplayTimeout,
                      onTimeout: () => throw TimeoutException(
                        'browser stack retry timeout '
                        '(${_browserStackReplayTimeout.inSeconds}s)',
                      ),
                    );
                CfChallengeService.showGlobalMessage(
                  S.current.cf_sessionCompatEnabled,
                  isError: false,
                );
                debugPrint(
                  '[Dio][OHOS] 浏览器网络栈重放成功: '
                  'status=${fallbackResponse.statusCode} url=$requestUrl',
                );
                // 兜底成功 = CF 已解决：主动关闭可能正在展示的验证浮层。
                cfService.dismissActiveVerificationAsSuccess(
                  reason: 'retry_blocked_fallback',
                );
                CfChallengeLogger.log(
                  '[INTERCEPTOR] Native retry still blocked; '
                  'session WebView fallback succeeded',
                );
                return handler.resolve(fallbackResponse);
              } catch (fallbackError) {
                // 会话级兼容必须以首次真实请求成功为准；失败时立即回滚，
                // 避免所有后续请求被锁在一个坏掉的 WebView 传输状态里。
                if (!webViewSettings.persistentEnabled) {
                  webViewSettings.disableSessionFallback();
                }
                CfChallengeLogger.log(
                  '[INTERCEPTOR] Session WebView fallback failed: '
                  '$fallbackError',
                  level: 'warning',
                );
                // HarmonyOS 自动兜底失败：浏览器栈也没放行说明 CF 连 WebView
                // 都还在挡（或 adapter 本身不可用）。必须记一次无效 clearance
                // 冷却，否则每个后续请求都会再弹一轮验证页。
                if (ohosAutoFallback) {
                  cfService.startIneffectiveClearanceCooldown();
                  CfChallengeLogger.log(
                    '[INTERCEPTOR][OHOS] browser stack fallback also blocked by CF; '
                    'entering cooldown',
                    level: 'warning',
                  );
                }
                if (fallbackError is DioException) {
                  return handler.reject(fallbackError);
                }
                return handler.reject(
                  DioException(
                    requestOptions: retryOptions,
                    error: fallbackError,
                    type: DioExceptionType.unknown,
                  ),
                );
              }
            }
          }

          // 诊断：记录完整的重试失败信息
          if (e is DioException) {
            debugPrint(
              '[Dio] Retry failed: status=${e.response?.statusCode}, '
              'type=${e.type}, url=${e.requestOptions.uri}',
            );
            if (e.response?.statusCode == 403 ||
                e.response?.statusCode == 429) {
              debugPrint(
                '[Dio] Verification entry is clear, but API retry returned ${e.response?.statusCode}',
              );
              // 以真实重试仍命中 CF 为冷却依据。入口无盾不保证 API 放行，
              // 也不保证本轮有新 Cookie；避免立刻反复打开同一个验证入口。
              if (CfChallengeService.isCfChallengeResponse(e.response)) {
                cfService.startIneffectiveClearanceCooldown();
                // 仅记录这次重试实际携带的值；可能没有 clearance，不能把
                // 「Cookie 未签发」本身当成失败或拉黑依据。
                CfClearanceAuthority.instance.noteIncumbentChallenged(
                  CfClearanceAuthority.extractFromCookieHeader(
                    retryOptions.headers['Cookie']?.toString() ??
                        retryOptions.headers['cookie']?.toString(),
                  ),
                );
                CfChallengeLogger.log(
                  '[INTERCEPTOR] Origin verification finished but API still challenged '
                  '(retry ${e.response?.statusCode}), entering cooldown: '
                  '$requestMethod $requestUrl',
                  level: 'warning',
                );
                if (shouldShowActionPrompt) {
                  CfChallengeService.showGlobalMessage(
                    S.current.cf_challengeNotEffective,
                  );
                }
              }
            }
          } else {
            debugPrint('[Dio] Retry failed (non-Dio): $e');
          }
          CfChallengeLogger.logInterceptorRetry(
            url: requestUrl,
            success: false,
            error: e.toString(),
          );
          // 验证页面已经结束；保留真实重试错误和状态码，供调用方判断恢复。
          if (e is DioException) {
            return handler.reject(e);
          }
          return handler.reject(
            DioException(
              requestOptions: err.requestOptions,
              error: e,
              type: DioExceptionType.unknown,
            ),
          );
        }
      }

      // HarmonyOS：验证没拿到成功结果（用户取消 / 超时 / 冷却期 / 无 UI）时，
      // 原生重试必然还是 403 —— 不要把用户丢在错误页。CF 的挑战只认浏览器
      // 会话，而 ArkWeb 内核天生带 cookie，直接切浏览器网络栈重放一次。
      // 成功则本次会话保持兼容模式（后续主站请求都走 WebView）。
      if (PlatformUtils.isOhos &&
          requestCanUseWebViewAdapter(err.requestOptions)) {
        debugPrint(
          '[CfChallenge][OHOS] 验证未成功(result=$result)，直接切浏览器网络栈重放: '
          '$requestMethod $requestUrl',
        );
        final replay = await _replayViaBrowserStack(
          err.requestOptions,
          cfService: cfService,
          reason: 'verify_incomplete',
          url: requestUrl,
        );
        if (replay != null) {
          return handler.resolve(replay);
        }
      }

      if (result == null) {
        if (cfService.isInCooldown) {
          CfChallengeLogger.log(
            '[INTERCEPTOR] Verification skipped by cooldown: '
            '$requestMethod $requestUrl mode=$requestMode',
          );
          if (shouldShowActionPrompt) {
            CfChallengeService.showGlobalMessage(
              S.current.cf_operationBlockedByChallenge,
            );
          }
          return handler.reject(
            cfException(CfChallengeException(inCooldown: true)),
          );
        }

        // 无 context（应用刚启动，context 还没设置好）
        debugPrint(
          '[Dio] CF Challenge: no context available, cannot show verify page',
        );
        CfChallengeLogger.log('[INTERCEPTOR] No context available');
        if (shouldShowActionPrompt) {
          CfChallengeService.showGlobalMessage(
            S.current.cf_cannotOpenVerifyPage,
          );
        }
        return handler.reject(
          cfException(CfChallengeException(cause: '无法获取 context，验证页面未展示')),
        );
      }

      // 用户取消或验证失败。页面数据请求交给 ErrorView 展示按钮；操作请求给即时提示；静默请求不打扰。
      CfChallengeLogger.log(
        '[INTERCEPTOR] User cancelled or verify failed: '
        '$requestMethod $requestUrl mode=$requestMode',
      );
      if (shouldShowActionPrompt) {
        CfChallengeService.showGlobalMessage(S.current.cf_verifyIncomplete);
      }
      return handler.reject(
        cfException(CfChallengeException(userCancelled: true)),
      );
    }

    handler.next(err);
  }
}
