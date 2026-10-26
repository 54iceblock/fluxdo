part of 'discourse_service.dart';

/// 用户偏好（对应 Discourse 网页版 `/u/<username>/preferences/*` 的原生适配）
///
/// 网页版这些子页面最终都是同一套数据 + 同一个写接口：
/// - 读：`GET /u/<username>.json`（`user` 里含 `name/bio_raw/location/website`、
///   `user_option`（邮件/通知/跟踪/界面偏好）、`user_fields`（站点自定义字段））
/// - 写：`PUT /u/<username>.json`，参数**全部扁平**（`name`、`bio_raw`、
///   `email_digests`、`email_level`…），服务端由 `UsersController#update` +
///   `UserUpdater::OPTION_ATTR` 接收。不要包成 `user_option[...]`。
mixin _PreferencesMixin on _DiscourseServiceBase {
  /// 读取「我」的完整用户对象（原始 JSON，未收窄成 User 模型）。
  ///
  /// 返回 `user` 节点：含资料字段、`user_option`、`user_fields`、`email`（本人）。
  Future<Map<String, dynamic>> fetchUserPreferences(String username) async {
    final response = await _dio.get(
      '/u/$username.json',
      queryParameters: const {'include_raw': '1'},
      options: Options(
        extra: const {'skipAuthCheck': true, 'skipCsrf': true},
      ),
    );
    final data = response.data;
    if (data is Map && data['user'] is Map) {
      return Map<String, dynamic>.from(data['user'] as Map);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('用户资料响应格式异常');
  }

  /// 保存偏好（扁平参数）。只传要改的字段。
  ///
  /// 成功返回 null，失败返回可直接展示给用户的错误文案（服务端 `errors` 优先）。
  Future<String?> updateUserPreferences(
    String username,
    Map<String, dynamic> fields,
  ) async {
    if (fields.isEmpty) return null;
    try {
      await _dio.put(
        '/u/$username.json',
        data: fields,
        options: Options(
          headers: const {'Content-Type': 'application/json'},
          extra: const {'skipRedirect': true},
        ),
      );
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final errors = data['errors'];
        if (errors is List && errors.isNotEmpty) {
          return errors.join('；');
        }
        final error = data['error'];
        if (error is String && error.isNotEmpty) return error;
      }
      return '保存失败（HTTP ${e.response?.statusCode ?? '网络异常'}）';
    }
  }

  /// 站点可编辑的自定义用户字段（`GET /user_fields.json`）。
  ///
  /// 只返回 `editable == true` 的字段；返回结构：
  /// `{id, name, description, field_type, required, options?}`
  Future<List<Map<String, dynamic>>> fetchEditableUserFields() async {
    try {
      final response = await _dio.get(
        '/user_fields.json',
        options: Options(
          extra: const {'skipAuthCheck': true, 'skipCsrf': true},
        ),
      );
      final data = response.data;
      final list = data is Map ? data['user_fields'] : null;
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e['editable'] == true)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[Preferences] 自定义字段读取失败: $e');
      return const [];
    }
  }

  /// 当前账号的邮箱 + 关联账号信息。
  ///
  /// 优先用网页版「电子邮件」子页的数据源 `GET /u/<username>/preferences/email`
  /// （返回 `{email, secondary_emails, unconfirmed_emails, associated_accounts}`），
  /// 失败再退回 `GET /u/<username>/emails`；都不可用时返回 null。
  Future<Map<String, dynamic>?> fetchAccountEmails(String username) async {
    for (final path in <String>[
      '/u/$username/preferences/email.json',
      '/u/$username/emails.json',
    ]) {
      try {
        final response = await _dio.get(
          path,
          options: Options(
            extra: const {'skipAuthCheck': true, 'skipCsrf': true},
          ),
        );
        final data = response.data;
        if (data is Map) return Map<String, dynamic>.from(data);
      } catch (e) {
        debugPrint('[Preferences] $path 读取失败: $e');
      }
    }
    return null;
  }
}
