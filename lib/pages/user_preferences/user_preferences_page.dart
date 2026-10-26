import 'package:flutter/material.dart';

import '../../services/discourse/discourse_service.dart';
import '../../services/toast_service.dart';
import '../webview_page.dart';

/// 偏好设置（Discourse `/u/<username>/preferences/*` 的原生适配）
///
/// 网页版把偏好拆成「帐户 / 安全性 / 个人资料 / 电子邮件 / 通知 / 跟踪 / 用户 /
/// 界面 / 导航菜单 / 日历 / 保存的搜索 / 聊天」这些子页，底层其实是同一份数据
/// 加同一个写接口：
///   - 读：`GET /u/<username>.json`（资料字段 + `user_option` + 自定义字段）
///   - 写：`PUT /u/<username>.json`（参数**扁平**：`bio_raw`、`email_digests`…）
///
/// 本页把纯表单类子页（个人资料 / 通知 / 跟踪 / 界面）做成原生可编辑；
/// 帐户与电子邮件做成只读展示；改用户名、改邮箱、换头像、关联第三方账号、
/// 两步验证、日历/保存的搜索/聊天等涉及 OAuth、邮件验证或复杂交互的子页，
/// 一律提供网页版入口，避免用原生表单复刻安全流程。
class UserPreferencesPage extends StatefulWidget {
  const UserPreferencesPage({super.key, required this.username});

  final String username;

  @override
  State<UserPreferencesPage> createState() => _UserPreferencesPageState();
}

class _UserPreferencesPageState extends State<UserPreferencesPage>
    with SingleTickerProviderStateMixin {
  final _service = DiscourseService();
  late final TabController _tabs = TabController(length: 6, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  Map<String, dynamic> _user = const {};
  Map<String, dynamic> _option = const {};
  List<Map<String, dynamic>> _editableFields = const [];
  Map<String, dynamic>? _emails;

  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final Map<String, TextEditingController> _fieldCtrls = {};

  final Map<String, dynamic> _optionDraft = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _locationCtrl.dispose();
    _websiteCtrl.dispose();
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _profileDirty =>
      _nameCtrl.text.trim() != ((_user['name'] as String?) ?? '').trim() ||
      _bioCtrl.text.trim() != ((_user['bio_raw'] as String?) ?? '').trim() ||
      _locationCtrl.text.trim() != ((_user['location'] as String?) ?? '').trim() ||
      _websiteCtrl.text.trim() != ((_user['website'] as String?) ?? '').trim() ||
      _fieldCtrls.entries.any((e) {
        final raw = ((_user['user_fields'] as Map?)?[e.key] ?? '').toString();
        return e.value.text.trim() != raw.trim();
      });

  bool get _dirty => _profileDirty || _optionDraft.isNotEmpty;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _service.fetchUserPreferences(widget.username),
        _service.fetchEditableUserFields(),
        _service.fetchAccountEmails(widget.username),
      ]);
      if (!mounted) return;
      _user = results[0] as Map<String, dynamic>;
      _editableFields = results[1] as List<Map<String, dynamic>>;
      _emails = results[2] as Map<String, dynamic>?;
      _option = (_user['user_option'] as Map?)?.cast<String, dynamic>() ?? {};
      _optionDraft.clear();

      _nameCtrl.text = (_user['name'] as String?) ?? '';
      _bioCtrl.text = (_user['bio_raw'] as String?) ?? '';
      _locationCtrl.text = (_user['location'] as String?) ?? '';
      _websiteCtrl.text = (_user['website'] as String?) ?? '';

      final userFields = (_user['user_fields'] as Map?)?.cast<String, dynamic>();
      for (final f in _editableFields) {
        final id = f['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        _fieldCtrls.putIfAbsent(id, () => TextEditingController());
        _fieldCtrls[id]!.text = (userFields?[id] ?? '').toString();
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _setOption(String key, Object? value) {
    if (value == _option[key]) {
      _optionDraft.remove(key);
    } else {
      _optionDraft[key] = value;
    }
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    final payload = <String, dynamic>{};

    void addText(String key, TextEditingController ctrl) {
      final original = ((_user[key] as String?) ?? '').trim();
      if (ctrl.text.trim() != original) payload[key] = ctrl.text.trim();
    }

    addText('name', _nameCtrl);
    addText('bio_raw', _bioCtrl);
    addText('location', _locationCtrl);
    addText('website', _websiteCtrl);

    final userFields = (_user['user_fields'] as Map?)?.cast<String, dynamic>();
    for (final entry in _fieldCtrls.entries) {
      final original = (userFields?[entry.key] ?? '').toString().trim();
      if (entry.value.text.trim() != original) {
        payload['user_fields'] ??= <String, dynamic>{};
        (payload['user_fields'] as Map)[entry.key] = entry.value.text.trim();
      }
    }
    payload.addAll(_optionDraft);

    if (payload.isEmpty) {
      ToastService.show('没有需要保存的修改');
      return;
    }

    setState(() => _saving = true);
    final error = await _service.updateUserPreferences(widget.username, payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ToastService.showError(error);
      return;
    }
    ToastService.showSuccess('已保存');
    await _load();
  }

  Future<void> _openWeb(String subPath, String title) async {
    await WebViewPage.open(
      context,
      'https://linux.do/u/${widget.username}/preferences/$subPath',
      title: title,
    );
    if (mounted) await _load();
  }

  // ---------------- 取值助手 ----------------
  bool _boolOption(String key, {bool fallback = false}) {
    final v = _optionDraft.containsKey(key) ? _optionDraft[key] : _option[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) return v == 'true';
    return fallback;
  }

  int _intOption(String key, int fallback) {
    final v = _optionDraft.containsKey(key) ? _optionDraft[key] : _option[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('偏好设置'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _loading || _loadError != null ? null : _save,
              child: Text(
                '保存',
                style: TextStyle(
                  color: _dirty ? theme.colorScheme.primary : theme.disabledColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
        bottom: _loading || _loadError != null
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: '帐户'),
                  Tab(text: '资料'),
                  Tab(text: '电子邮件'),
                  Tab(text: '通知'),
                  Tab(text: '跟踪'),
                  Tab(text: '更多'),
                ],
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _buildError()
          : TabBarView(
              controller: _tabs,
              children: [
                _tabAccount(),
                _tabProfile(),
                _tabEmails(),
                _tabNotifications(),
                _tabTracking(),
                _tabMore(),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('加载偏好失败\n$_loadError', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _page(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: children,
      ),
    );
  }

  Widget _section({required String title, String? hint, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _webTile(String title, String subPath, {String? subtitle}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _openWeb(subPath, title),
    );
  }

  Widget _switchTile({
    required String title,
    String? subtitle,
    required String optionKey,
    bool fallback = false,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      value: _boolOption(optionKey, fallback: fallback),
      onChanged: (v) => _setOption(optionKey, v),
    );
  }

  Widget _dropdownTile({
    required String title,
    String? subtitle,
    required String optionKey,
    required int fallback,
    required Map<int, String> options,
  }) {
    final current = _intOption(optionKey, fallback);
    final safeValue = options.containsKey(current) ? current : fallback;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: DropdownButton<int>(
        value: safeValue,
        underline: const SizedBox.shrink(),
        items: options.entries
            .map((e) => DropdownMenuItem<int>(value: e.key, child: Text(e.value)))
            .toList(growable: false),
        onChanged: (v) {
          if (v != null) _setOption(optionKey, v);
        },
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  // ---------------- 帐户 ----------------
  Widget _tabAccount() {
    final email = _emails?['email'] as String?;
    final secondary = (_emails?['secondary_emails'] as List?) ?? const [];
    final associated = (_user['associated_accounts'] as List?) ??
        (_emails?['associated_accounts'] as List?) ??
        const [];
    return _page([
      _section(
        title: '用户名',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(widget.username),
            subtitle: const Text('其他人可以用 @用户名 提及你；改名请到网页版'),
            trailing: IconButton(
              tooltip: '网页版修改用户名',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => _openWeb('account', '修改用户名'),
            ),
          ),
        ],
      ),
      _section(
        title: '个人资料照片',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 22,
              backgroundImage: _avatarImage(),
            ),
            title: const Text('头像'),
            subtitle: const Text('上传/裁剪头像在网页版完成'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openWeb('account', '更换头像'),
          ),
        ],
      ),
      _section(
        title: '姓名',
        hint: '可选，展示在帖子署名处',
        children: [
          _textField(label: '姓名', controller: _nameCtrl),
          const SizedBox(height: 8),
        ],
      ),
      _section(
        title: '电子邮件',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(email ?? '未读取到邮箱'),
            subtitle: Text(
              [
                '不会向公众显示',
                if (secondary.isNotEmpty) '另有 ${secondary.length} 个备用邮箱',
              ].join(' · '),
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openWeb('emails', '电子邮件设置'),
          ),
        ],
      ),
      _section(
        title: '关联帐户',
        children: [
          if (associated.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('未连接第三方账号'),
              subtitle: Text('Google / GitHub / Discord / Apple 连接与断开在网页版完成'),
            )
          else
            for (final a in associated)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  ((a as Map)['provider_name'] ?? a['name'] ?? '第三方').toString(),
                ),
                subtitle: Text((a['provider_uid'] ?? '').toString()),
              ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openWeb('account', '关联帐户'),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('管理关联帐户（网页版）'),
            ),
          ),
        ],
      ),
      _section(
        title: '安全',
        children: [
          _webTile('修改密码', 'account', subtitle: '网页版（需当前密码校验）'),
          _webTile('两步验证 / 安全密钥', 'security'),
          _webTile('登录设备与会话', 'account'),
        ],
      ),
    ]);
  }

  ImageProvider? _avatarImage() {
    final template = _user['avatar_template'] as String?;
    if (template == null || template.isEmpty) return null;
    final url = template.replaceAll('{size}', '96');
    final full = url.startsWith('http') ? url : 'https://linux.do$url';
    return NetworkImage(full);
  }

  // ---------------- 个人资料 ----------------
  Widget _tabProfile() {
    final textFields = _editableFields.where(
      (f) => ((f['field_type'] as String?) ?? 'text') == 'text',
    );
    return _page([
      _section(
        title: '个人资料',
        hint: '与网页版「个人资料」页对应，保存后立即生效',
        children: [
          _textField(label: '姓名', controller: _nameCtrl),
          _textField(
            label: '简介',
            controller: _bioCtrl,
            maxLines: 4,
            hint: '支持 Markdown',
          ),
          _textField(label: '所在地', controller: _locationCtrl),
          _textField(label: '网站', controller: _websiteCtrl, hint: 'https://'),
          for (final f in textFields)
            _textField(
              label:
                  '${(f['name'] as String?) ?? '自定义字段'}'
                  '${f['required'] == true ? ' *' : ''}',
              controller: _fieldCtrls.putIfAbsent(
                '${f['id']}',
                () => TextEditingController(),
              ),
              maxLines: 2,
              hint: f['description'] as String?,
            ),
          const SizedBox(height: 8),
        ],
      ),
      _section(
        title: '头像与横幅',
        children: [
          _webTile('上传头像 / 个人资料横幅', 'account', subtitle: '需要裁剪交互，暂走网页版'),
        ],
      ),
    ]);
  }

  // ---------------- 电子邮件 ----------------
  Widget _tabEmails() {
    final email = _emails?['email'] as String?;
    final secondary = (_emails?['secondary_emails'] as List?) ?? const [];
    final unconfirmed = (_emails?['unconfirmed_emails'] as List?) ?? const [];
    return _page([
      _section(
        title: '常用邮箱',
        hint: '绝不向公众显示',
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.mail_outline),
            title: Text(email ?? '未读取到'),
            subtitle: const Text('主邮箱'),
          ),
        ],
      ),
      _section(
        title: '备用邮箱',
        children: [
          if (secondary.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('暂无备用邮箱'),
            )
          else
            for (final e in secondary)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.alternate_email),
                title: Text(e.toString()),
              ),
          for (final e in unconfirmed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.pending_outlined),
              title: Text(e.toString()),
              subtitle: const Text('待验证'),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _openWeb('emails', '添加备用邮箱'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加 / 管理备用邮箱（网页版）'),
            ),
          ),
        ],
      ),
      _section(
        title: '说明',
        children: const [
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '添加邮箱需要收验证邮件、点击激活链接，属于多步流程，'
              '为保证安全仍走网页版；本页只读取展示。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ]);
  }

  // ---------------- 通知 ----------------
  Widget _tabNotifications() {
    return _page([
      _section(
        title: '私信与隐私',
        children: [
          _switchTile(
            title: '允许其他用户给我发私信',
            optionKey: 'allow_private_messages',
            fallback: true,
          ),
          _switchTile(
            title: '隐藏在线状态',
            subtitle: '隐藏「正在输入 / 在线」等状态',
            optionKey: 'hide_presence',
          ),
          _switchTile(
            title: '隐藏公开资料',
            subtitle: '个人主页仅对登录用户可见',
            optionKey: 'hide_profile',
          ),
        ],
      ),
      _section(
        title: '邮件通知',
        hint: '摘要邮件、邮件频率、邮件列表模式、免打扰时段等只影响邮箱，'
            'App 内不可见，仍在网页版设置',
        children: [
          _webTile('邮件通知与时间表', 'notifications', subtitle: '网页版'),
        ],
      ),
    ]);
  }

  // ---------------- 跟踪 ----------------
  Widget _tabTracking() {
    return _page([
      _section(
        title: '默认跟踪行为',
        children: [
          _dropdownTile(
            title: '自动跟踪新话题',
            subtitle: '浏览多久后自动开始跟踪',
            optionKey: 'auto_track_topics_after_msecs',
            fallback: 300000,
            options: const {
              0: '立即',
              60000: '1 分钟',
              120000: '2 分钟',
              300000: '5 分钟',
              600000: '10 分钟',
            },
          ),
          _dropdownTile(
            title: '回复后的话题通知',
            optionKey: 'notification_level_when_replying',
            fallback: 2,
            options: const {1: '常规', 2: '跟踪', 3: '关注'},
          ),
          _switchTile(
            title: '链接到他人帖子时通知对方',
            optionKey: 'notify_on_linked_posts',
            fallback: true,
          ),
          _switchTile(
            title: '关注优先于免打扰',
            optionKey: 'watched_precedence_over_muted',
          ),
        ],
      ),
      _section(
        title: '分类与标签',
        children: [
          _webTile('按分类/标签设置跟踪与免打扰', 'tracking', subtitle: '网页版（数量多、需搜索）'),
        ],
      ),
    ]);
  }

  // ---------------- 更多 ----------------
  Widget _tabMore() {
    return _page([
      _section(
        title: '其它子页（网页版）',
        hint: '这些子页涉及复杂交互或站点插件，原生表单不便于完整还原',
        children: [
          _webTile('安全性（两步验证 / 安全密钥 / 会话）', 'security'),
          _webTile('用户（静音/忽略列表）', 'users'),
          _webTile('日历', 'calendar'),
          _webTile('保存的搜索', 'saved-searches'),
          _webTile('聊天', 'chat'),
          _webTile('应用授权（API key）', 'apps'),
        ],
      ),
      _section(
        title: '关于本页',
        children: const [
          Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '原生编辑：个人资料、隐私/私信、跟踪默认行为。\n'
              '只读展示：用户名、头像、邮箱、关联账号。\n'
              '界面外观、邮件通知、安全性等只影响网页/邮箱的选项，'
              '仍走网页版入口。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ]);
  }
}
