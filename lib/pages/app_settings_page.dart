import 'package:flutter/material.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/design_system/components/review_preference_tile.dart';
import '../core/design_system/components/review_switch_tile.dart';
import '../core/utils/account_status.dart';
import '../core/utils/app_dialog.dart';
import '../core/widgets/app_section_card.dart';
import '../data/account_validation.dart';
import '../data/forum.dart';
import '../data/preferences.dart';
import 'about_dialog.dart';
import 'account_page.dart';
import 'login_page.dart';
import 'settings_page.dart';
import 'storage_settings_page.dart';
import 'web_page.dart';
import 'webdav_backup_page.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    super.key,
    required this.preferences,
    required this.client,
  });
  final Preferences preferences;
  final ForumClient client;
  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool checking = false, signingOut = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    sessionRevision.addListener(changedAccount);
  }

  void changedAccount() {
    revision++;
    if (mounted) setState(() => checking = false);
  }

  @override
  void dispose() {
    sessionRevision.removeListener(changedAccount);
    super.dispose();
  }

  Future<void> checkAccount() async {
    if (checking || signingOut) return;
    final current = ++revision;
    setState(() => checking = true);
    try {
      final account = await validateForumAccount(widget.client);
      if (!mounted || current != revision) return;
      setState(() => checking = false);
      await showAppDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(account == null ? '账号凭据已失效' : '账号凭据有效'),
          content: Text(
            account == null
                ? '请重新登录后继续使用账号功能。'
                : '登录会话正常。\n\n账号：${account.name}\nUID：${account.uid}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
            if (account == null)
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  showForumLogin(context, widget.client, force: true);
                },
                child: const Text('重新登录'),
              ),
          ],
        ),
      );
    } catch (_) {
      if (mounted && current == revision) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('检测未完成，请检查网络或网站验证后重试；这不代表账号已失效。')),
        );
      }
    } finally {
      if (mounted && current == revision) setState(() => checking = false);
    }
  }

  Future<void> logout() async {
    if (checking || signingOut) return;
    setState(() => signingOut = true);
    final success = await logoutForum(context, widget.client);
    if (!mounted) return;
    setState(() => signingOut = false);
    if (success) showAccountStatus(ScaffoldMessenger.of(context), '已退出登录');
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 16, top: 28, bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
  void open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.preferences, forumAuthenticated]),
    builder: (context, _) => Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          heading('偏好与功能'),
          AppSectionCard(
            child: Column(
              children: [
                ReviewPreferenceTile(
                  title: '个性化',
                  leading: const Icon(Icons.palette_outlined),
                  onTap: () => open(
                    SettingsPage(
                      preferences: widget.preferences,
                      client: widget.client,
                    ),
                  ),
                ),
                ReviewSwitchTile(
                  title: '自动签到',
                  summary: '启动时在后台检查并完成当日签到',
                  leading: const Icon(Icons.event_available_outlined),
                  value: widget.preferences.autoSignIn,
                  onChanged: (value) {
                    widget.preferences.autoSignIn = value;
                    widget.preferences.save();
                  },
                ),
              ],
            ),
          ),
          heading('存储与备份'),
          AppSectionCard(
            child: Column(
              children: [
                ReviewPreferenceTile(
                  title: '存储设置',
                  leading: const Icon(Icons.folder_open_outlined),
                  onTap: () => open(
                    StorageSettingsPage(preferences: widget.preferences),
                  ),
                ),
                ReviewPreferenceTile(
                  title: '缓存管理',
                  leading: const Icon(Icons.cleaning_services_outlined),
                  onTap: () => open(
                    CacheManagementPage(preferences: widget.preferences),
                  ),
                ),
                ReviewPreferenceTile(
                  title: 'WebDAV备份',
                  leading: const Icon(Icons.cloud_sync_outlined),
                  onTap: () => open(
                    WebDavBackupPage(
                      preferences: widget.preferences,
                      client: widget.client,
                    ),
                  ),
                ),
              ],
            ),
          ),
          heading('账号设置'),
          AppSectionCard(
            child: Column(
              children: [
                if (!forumAuthenticated.value)
                  ReviewPreferenceTile(
                    title: '登录账号',
                    leading: const Icon(Icons.login_rounded),
                    onTap: () => showForumLogin(context, widget.client),
                  ),
                if (forumAuthenticated.value) ...[
                  ReviewPreferenceTile(
                    title: '检测账号凭据有效性',
                    subtitle: '向论坛核验当前登录会话',
                    leading: const Icon(Icons.verified_user_outlined),
                    trailing: checking
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: checking || signingOut ? null : checkAccount,
                  ),
                  ReviewPreferenceTile(
                    title: signingOut ? '正在退出…' : '退出登录',
                    leading: const Icon(Icons.logout_rounded),
                    onTap: checking || signingOut ? null : logout,
                  ),
                ],
              ],
            ),
          ),
          heading('关于与支持'),
          AppSectionCard(
            child: ReviewPreferenceTile(
              title: '关于应用',
              subtitle: '版本 $forumAppVersion',
              leading: const Icon(Icons.info_outline_rounded),
              onTap: () => showForumAboutDialog(context),
            ),
          ),
        ],
      ),
    ),
  );
}
