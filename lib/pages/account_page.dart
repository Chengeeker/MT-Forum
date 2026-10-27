import 'package:flutter/material.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/forum_avatar.dart';
import '../data/forum.dart';
import '../data/native_forum.dart';
import 'web_page.dart';

bool _signingOut = false;

Future<bool> logoutForum(
  BuildContext context,
  ForumClient client, {
  VoidCallback? onConfirmed,
}) async {
  if (_signingOut) return false;
  _signingOut = true;
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出当前账号？'),
        content: const Text('清除本机的论坛登录会话及未提交的编辑内容，之后可以重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    onConfirmed?.call();
    await client.logout();
    if ((await forumAuthCookie()).isNotEmpty) {
      throw const ForumFailure('论坛会话尚未清除，请重试退出登录。');
    }
    forumAuthenticated.value = false;
    sessionRevision.value++;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已退出登录')));
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('退出登录未完成，请重试。')));
    }
    return false;
  } finally {
    _signingOut = false;
  }
}

class ForumAccountPage extends StatefulWidget {
  const ForumAccountPage({super.key, required this.client});
  final ForumClient client;
  @override
  State<ForumAccountPage> createState() => _ForumAccountPageState();
}

class _ForumAccountPageState extends State<ForumAccountPage> {
  ForumAccount? account;
  String? error;
  bool loading = false, signingOut = false;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (loading || signingOut) return;
    final generation = ++revision;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final source = await widget.client
          .source('$forumOrigin/home.php?mod=space&do=profile')
          .timeout(const Duration(seconds: 30));
      final data = ForumAccount.parse(source);
      if (mounted && generation == revision) setState(() => account = data);
    } catch (e) {
      if (mounted && generation == revision) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && generation == revision) setState(() => loading = false);
    }
  }

  Future<void> logout() async {
    final success = await logoutForum(
      context,
      widget.client,
      onConfirmed: () {
        revision++;
        if (mounted) {
          setState(() {
            signingOut = true;
            loading = false;
          });
        }
      },
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() => signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: ReviewFrostedAppBar(
      title: const Text('论坛账号'),
      actions: [
        IconButton(
          tooltip: '刷新资料',
          onPressed: loading || signingOut ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: OutlinedButton.icon(
          onPressed: signingOut ? null : logout,
          icon: signingOut
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
          label: Text(signingOut ? '正在退出…' : '退出登录'),
        ),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            AppSectionCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(height: 12),
                    Text(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: signingOut ? null : load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          if (account != null) ...[
            AppSectionCard(
              child: ListTile(
                leading: ForumAvatar(url: account!.avatar, radius: 20),
                title: Text(account!.name),
                subtitle: Text('UID: ${account!.uid}'),
              ),
            ),
            const SizedBox(height: 12),
            AppSectionCard(
              child: Column(
                children: [
                  for (final field in account!.fields)
                    ListTile(title: Text(field.$1), subtitle: Text(field.$2)),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
