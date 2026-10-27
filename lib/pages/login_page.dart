import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/design_system/components/review_switch_tile.dart';
import '../core/widgets/app_section_card.dart';
import '../data/forum.dart';
import '../data/preferences.dart';
import 'native_forum_page.dart';
import 'forum_page.dart';
import 'account_page.dart';
import 'web_page.dart';

Future<bool> showForumLogin(
  BuildContext context,
  ForumClient client, {
  bool force = false,
}) async {
  final initial = await forumAuthCookie();
  if (!force && initial.isNotEmpty) return true;
  if (!context.mounted) return false;
  final before = sessionRevision.value;
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(builder: (_) => ForumLoginPage(client: client)),
  );
  // Back/cancel can race a successful server response; reconcile the shared session.
  final after = await forumAuthCookie();
  final authenticated = after.isNotEmpty;
  if (authenticated && sessionRevision.value == before) sessionRevision.value++;
  return result == true || (authenticated && (!force || initial != after));
}

Future<void> openForumWeb(
  BuildContext context,
  String title,
  String path, {
  required ForumClient client,
  String? search,
  Preferences? preferences,
}) async {
  final uri = forumUri(path);
  if (!isForumUri(uri)) {
    await openExternal(context, uri);
    return;
  }
  if (isForumLoginUri(uri)) {
    await showForumLogin(context, client);
    return;
  }
  if (requiresForumLogin(uri)) {
    final authenticated = (await forumAuthCookie()).isNotEmpty;
    if (!context.mounted) return;
    if (!authenticated && !await showForumLogin(context, client)) return;
  }
  if (!context.mounted) return;
  if (uri.path == '/home.php' &&
      uri.queryParameters['do'] == 'profile' &&
      !uri.queryParameters.containsKey('uid') &&
      !uri.queryParameters.containsKey('username')) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ForumAccountPage(client: client)),
    );
    return;
  }
  final settings =
      preferences ?? Preferences(await SharedPreferences.getInstance());
  if (!context.mounted) return;
  if (isThreadLink(uri)) {
    await openForum(
      context,
      ForumLink(title, uri.toString()),
      client,
      settings,
    );
    return;
  }
  final before = await forumAuthCookie();
  final revision = sessionRevision.value;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NativeForumPage(
        title: title,
        uri: uri,
        client: client,
        preferences: settings,
        search: search,
      ),
    ),
  );
  if (before != await forumAuthCookie() && sessionRevision.value == revision) {
    sessionRevision.value++;
  }
}

class ForumLoginPage extends StatefulWidget {
  const ForumLoginPage({super.key, required this.client});

  final ForumClient client;

  @override
  State<ForumLoginPage> createState() => _ForumLoginPageState();
}

class _ForumLoginPageState extends State<ForumLoginPage> {
  static const questions = <(int, String)>[
    (0, '无安全提问'),
    (1, '母亲的名字'),
    (2, '爷爷的名字'),
    (3, '父亲出生的城市'),
    (4, '您其中一位老师的名字'),
    (5, '您个人计算机的型号'),
    (6, '您最喜欢的餐馆名称'),
    (7, '驾驶执照最后四位数字'),
  ];

  final formKey = GlobalKey<FormState>();
  final username = TextEditingController();
  final password = TextEditingController();
  final answer = TextEditingController();
  int questionId = 0;
  int loginAttempt = 0;
  Timer? sessionPoll;
  String loginField = 'username';
  bool qqOpening = false;
  bool remember = false, passwordVisible = false, submitting = false;

  @override
  void dispose() {
    sessionPoll?.cancel();
    loginAttempt++;
    if (submitting) unawaited(widget.client.cancelLogin());
    username.dispose();
    password.dispose();
    answer.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (submitting || !formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final account = username.text.trim();
    final secret = password.text;
    final securityAnswer = answer.text.trim();
    final method = loginField;
    final attempt = ++loginAttempt;
    password.clear();
    setState(() => submitting = true);
    try {
      final result = await (() async {
        final before = await forumAuthCookie();
        if (attempt != loginAttempt) throw const ForumFailure('登录已取消。');
        final response = widget.client.login(
          loginField: method,
          username: account,
          password: secret,
          questionId: questionId,
          answer: securityAnswer,
          remember: remember,
        );
        final message = await Future.any<String>([
          response,
          waitForSession(attempt, before),
        ]);
        return (before, message, await forumAuthCookie());
      })().timeout(const Duration(seconds: 45));
      if (!mounted || attempt != loginAttempt) return;
      final (before, message, after) = result;
      if (after.isEmpty) {
        throw const ForumFailure('论坛没有建立登录会话，请检查账号信息后重试。');
      }
      if (before != after) sessionRevision.value++;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } on TimeoutException {
      await widget.client.cancelLogin();
      if (mounted && attempt == loginAttempt) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('登录超时，请检查网络后重试。')));
      }
    } on ForumFailure catch (error) {
      if (mounted && attempt == loginAttempt) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted && attempt == loginAttempt) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('登录失败，请检查网络后重试。')));
      }
    } finally {
      if (mounted && attempt == loginAttempt) {
        sessionPoll?.cancel();
        setState(() => submitting = false);
        unawaited(widget.client.cancelLogin());
      }
    }
  }

  Future<String> waitForSession(int attempt, String before) async {
    final result = Completer<String>();
    var reading = false;
    sessionPoll = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (reading || !mounted || !submitting || attempt != loginAttempt) return;
      reading = true;
      final after = await forumAuthCookie();
      reading = false;
      if (!mounted || !submitting || attempt != loginAttempt) return;
      if (after.isNotEmpty && after != before && !result.isCompleted) {
        result.complete('登录成功');
      }
    });
    return result.future;
  }

  Future<void> cancelLogin() async {
    sessionPoll?.cancel();
    loginAttempt++;
    await widget.client.cancelLogin();
    if (mounted) setState(() => submitting = false);
  }

  Future<void> qqLogin() async {
    if (submitting || qqOpening) return;
    qqOpening = true;
    try {
      final before = await forumAuthCookie();
      if (!mounted) return;
      final success = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => const ForumWebPage(
            title: 'QQ 官方授权',
            url:
                '$forumOrigin/connect.php?mod=login&op=init&referer=%2F&statfrom=login',
            qqLogin: true,
          ),
        ),
      );
      if (success != true || !mounted) return;
      final after = await forumAuthCookie();
      if (!mounted || after.isEmpty) return;
      if (before != after) sessionRevision.value++;
      Navigator.of(context).pop(true);
    } finally {
      qqOpening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('登录 MT论坛')),
      body: SafeArea(
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                    child: const Icon(Icons.forum_outlined, size: 34),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '登录论坛账号',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  '登录信息由论坛验证，密码不会保存在本机。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'username', label: Text('用户名')),
                    ButtonSegment(value: 'email', label: Text('邮箱')),
                  ],
                  selected: {loginField},
                  onSelectionChanged: submitting
                      ? null
                      : (value) => setState(() => loginField = value.single),
                ),
                const SizedBox(height: 16),
                AppSectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: username,
                          enabled: !submitting,
                          maxLength: 256,
                          textInputAction: TextInputAction.next,
                          keyboardType: loginField == 'email'
                              ? TextInputType.emailAddress
                              : TextInputType.text,
                          autofillHints: loginField == 'email'
                              ? const [AutofillHints.email]
                              : const [AutofillHints.username],
                          validator: (value) {
                            final account = value?.trim() ?? '';
                            if (account.isEmpty) {
                              return loginField == 'email' ? '请输入邮箱' : '请输入用户名';
                            }
                            if (account.length > 256) return '账号长度无效';
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: loginField == 'email' ? '邮箱' : '用户名',
                            prefixIcon: Icon(
                              loginField == 'email'
                                  ? Icons.email_outlined
                                  : Icons.person_outline,
                            ),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: password,
                          enabled: !submitting,
                          maxLength: 256,
                          obscureText: !passwordVisible,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => login(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '请输入密码';
                            }
                            if (value.length > 256) return '密码长度无效';
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(Icons.lock_outline),
                            counterText: '',
                            suffixIcon: IconButton(
                              tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                              onPressed: submitting
                                  ? null
                                  : () => setState(
                                      () => passwordVisible = !passwordVisible,
                                    ),
                              icon: Icon(
                                passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: questionId,
                          decoration: const InputDecoration(
                            labelText: '安全提问（如未设置可跳过）',
                            prefixIcon: Icon(Icons.security_outlined),
                          ),
                          items: [
                            for (final item in questions)
                              DropdownMenuItem(
                                value: item.$1,
                                child: Text(item.$2),
                              ),
                          ],
                          onChanged: submitting
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    questionId = value;
                                    answer.clear();
                                  });
                                },
                        ),
                        if (questionId != 0) ...[
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: answer,
                            enabled: !submitting,
                            maxLength: 100,
                            textInputAction: TextInputAction.done,
                            validator: (_) =>
                                questionId != 0 && answer.text.trim().isEmpty
                                ? '请输入安全提问答案'
                                : null,
                            decoration: const InputDecoration(
                              labelText: '安全提问答案',
                              prefixIcon: Icon(Icons.key_outlined),
                              counterText: '',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ReviewSwitchTile(
                  title: '自动登录',
                  value: remember,
                  onChanged: submitting
                      ? (_) {}
                      : (value) => setState(() => remember = value),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    onPressed: submitting ? null : login,
                    child: submitting
                        ? const SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                ),
                if (submitting)
                  TextButton(onPressed: cancelLogin, child: const Text('取消登录')),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: submitting ? null : qqLogin,
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('使用 QQ 登录'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => openForumWeb(
                          context,
                          '注册 MT论坛账号',
                          'member.php?mod=register',
                          client: widget.client,
                        ),
                  child: const Text('没有账号？注册'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
