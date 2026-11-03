import 'package:flutter/material.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/design_system/components/review_choice_tile.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../data/backup_service.dart';
import '../data/forum.dart';
import '../data/preferences.dart';
import '../data/webdav_service.dart';
import 'web_page.dart';

/// Review's backup page, adapted to MT settings and the forum session store.
class WebDavBackupPage extends StatefulWidget {
  const WebDavBackupPage({
    super.key,
    required this.preferences,
    required this.client,
    this.service,
  });
  final Preferences preferences;
  final ForumClient client;
  final WebDavService? service;
  @override
  State<WebDavBackupPage> createState() => _WebDavBackupPageState();
}

class _WebDavBackupPageState extends State<WebDavBackupPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController,
      _usernameController,
      _passwordController,
      _dirController;
  late final _webDavService = widget.service ?? WebDavService();
  late final _backup = ForumBackupService(widget.preferences, widget.client);
  bool _isTesting = false,
      _isBackingUp = false,
      _isRestoring = false,
      _includeCredentials = false;
  bool _isConfirmingRestore = false;
  bool get _isBusy =>
      _isTesting || _isBackingUp || _isRestoring || _isConfirmingRestore;
  @override
  void initState() {
    super.initState();
    final store = widget.preferences.store;
    _urlController = TextEditingController(
      text: store.getString('webdav_url') ?? '',
    );
    _usernameController = TextEditingController(
      text: store.getString('webdav_username') ?? '',
    );
    _passwordController = TextEditingController(
      text: store.getString('webdav_password') ?? '',
    );
    _dirController = TextEditingController(
      text: store.getString('webdav_directory') ?? defaultWebDavDirectory,
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _urlController,
      _usernameController,
      _passwordController,
      _dirController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _saveConfig() async {
    if (_usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      throw const ForumFailure('请填写账号和授权密码');
    }
    final saved = await Future.wait([
      widget.preferences.store.setString(
        'webdav_url',
        WebDavService.serverUri(_urlController.text).toString(),
      ),
      widget.preferences.store.setString(
        'webdav_username',
        _usernameController.text.trim(),
      ),
      widget.preferences.store.setString(
        'webdav_password',
        _passwordController.text,
      ),
      widget.preferences.store.setString(
        'webdav_directory',
        WebDavService.directory(_dirController.text),
      ),
    ]);
    if (saved.any((value) => !value)) throw const ForumFailure('连接配置保存失败');
  }

  Future<void> _testConnection() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;
    setState(() => _isTesting = true);
    HapticFeedbackUtil.light();
    try {
      await _saveConfig();
      final success = await _webDavService.testConnection(
        serverUrl: _urlController.text,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      message(success ? 'WebDAV 服务器连接成功！' : '连接失败，请检查服务器地址、账号与授权密码');
    } catch (_) {
      message('连接配置保存失败，请重试');
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _performBackup() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;
    setState(() => _isBackingUp = true);
    HapticFeedbackUtil.light();
    try {
      await _saveConfig();
      final data = await _backup.exportAllData(
        includeCredentials: _includeCredentials,
      );
      final success = await _webDavService.uploadBackup(
        serverUrl: _urlController.text,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        directoryName: _dirController.text,
        data: data,
      );
      message(success ? '应用数据已成功备份到 WebDAV 云盘！' : '备份上传失败，请检查连接状态');
    } catch (_) {
      message('备份失败，未能读取完整备份数据');
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _performRestore() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;
    setState(() => _isConfirmingRestore = true);
    HapticFeedbackUtil.light();
    var sessionChanged = false;
    try {
      await _saveConfig();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('从 WebDAV 恢复备份？'),
          content: const Text(
            '恢复备份将覆盖其中的设置和浏览历史。若云端是全量备份，还会替换论坛登录会话和 WebDAV 密码；安全备份保留本机登录凭据。是否继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
      setState(() {
        _isConfirmingRestore = false;
        _isRestoring = true;
      });
      final data = await _webDavService.downloadLatestBackup(
        serverUrl: _urlController.text,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        directoryName: _dirController.text,
      );
      if (data == null) {
        message('未找到可用云端备份文件或下载失败');
        return;
      }
      _backup.validateBackup(data);
      sessionChanged = data['backup_mode'] == 'full';
      await _backup.restoreAllData(data);
      final store = widget.preferences.store;
      _urlController.text = store.getString('webdav_url') ?? '';
      _usernameController.text = store.getString('webdav_username') ?? '';
      _passwordController.text = store.getString('webdav_password') ?? '';
      _dirController.text =
          store.getString('webdav_directory') ?? defaultWebDavDirectory;
      message(
        _passwordController.text.isEmpty
            ? '备份已恢复。WebDAV 配置已变化，请重新填写授权密码。'
            : '备份已成功恢复！设置已更新，登录有效性以论坛校验为准',
      );
    } catch (e) {
      message(e is ForumFailure ? e.message : '恢复失败，备份格式无效或数据写入失败');
    } finally {
      if (sessionChanged) {
        await forumAuthCookie();
        sessionRevision.value++;
      }
      if (mounted) {
        setState(() {
          _isRestoring = false;
          _isConfirmingRestore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: !_isBusy,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const ReviewFrostedAppBar(
          title: Text(
            'WebDAV 云端备份与恢复',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(context).top + kToolbarHeight + 14,
              16,
              14,
            ),
            children: [
              // 1. Info Banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '备份内容',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '备份应用设置和浏览历史，不包含图片和视频缓存。',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              AbsorbPointer(
                absorbing: _isBackingUp || _isRestoring,
                child: AppSectionCard(
                  child: Column(
                    children: [
                      ReviewChoiceTile<bool>(
                        title: '全量安全备份',
                        summary: '论坛 Cookie 和 WebDAV 密码不会上传。',
                        value: false,
                        groupValue: _includeCredentials,
                        onSelected: () =>
                            setState(() => _includeCredentials = false),
                      ),
                      ReviewChoiceTile<bool>(
                        title: '全量备份',
                        summary:
                            '同时上传论坛 Cookie 和 WebDAV 密码。备份文件含明文凭据，请妥善保管云盘及历史备份。',
                        value: true,
                        groupValue: _includeCredentials,
                        onSelected: () =>
                            setState(() => _includeCredentials = true),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Configuration Card
              AppSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'WebDAV 服务器配置',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        enabled: !_isBusy,
                        controller: _urlController,
                        decoration: const InputDecoration(
                          labelText: '服务器 URL',
                          hintText: '例如: https://dav.jianguoyun.com/dav/',
                          prefixIcon: Icon(Icons.link_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return '请输入 WebDAV 服务器地址';
                          }
                          try {
                            WebDavService.serverUri(v);
                          } on FormatException catch (e) {
                            return e.message;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        enabled: !_isBusy,
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '账号 / 邮箱',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '请输入账号'
                            : v.contains(RegExp(r'[:\r\n]'))
                            ? '账号不能包含冒号或换行'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        enabled: !_isBusy,
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '应用密码 / Token',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '请输入密码或授权 Token'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        enabled: !_isBusy,
                        controller: _dirController,
                        validator: (value) {
                          try {
                            WebDavService.directory(value ?? '');
                            return null;
                          } on FormatException catch (e) {
                            return e.message;
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: '备份文件夹名称',
                          hintText: '默认: MT论坛',
                          prefixIcon: Icon(Icons.folder_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.wifi_tethering_rounded,
                                  size: 18,
                                ),
                          label: Text(_isTesting ? '正在测试连接...' : '测试服务器连接'),
                          onPressed: _isBusy ? null : _testConnection,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. Actions Section
              AppSectionCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '云端备份与还原操作',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              icon: _isBackingUp
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_upload_rounded),
                              label: Text(_isBackingUp ? '正在上传...' : '立即备份到云端'),
                              onPressed: _isBusy ? null : _performBackup,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              icon: _isRestoring
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.cloud_download_rounded),
                              label: Text(_isRestoring ? '正在拉取...' : '从云端恢复备份'),
                              onPressed: _isBusy ? null : _performRestore,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
