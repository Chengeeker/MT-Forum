import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/forum_avatar.dart';
import '../data/forum.dart';
import '../data/native_forum.dart';
import '../data/preferences.dart';
import '../data/user_home.dart';
import 'forum_page.dart';
import 'login_page.dart';
import 'native_forum_page.dart';
import 'web_page.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({
    super.key,
    required this.uri,
    required this.client,
    required this.preferences,
    this.name = '',
    this.title = '用户主页',
    this.initialHome,
    this.bottomNavigationBar,
    this.ownAccount = false,
  });
  final Uri uri;
  final ForumClient client;
  final Preferences preferences;
  final String name;
  final String title;
  final ForumUserHome? initialHome;
  final Widget? bottomNavigationBar;
  final bool ownAccount;
  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  static const sections = [
    ('thread', '主题'),
    ('follow', '广播'),
    ('wall', '留言板'),
    ('profile', '资料'),
  ];
  final contents = <String, ForumUserContent>{};
  final loading = <String>{};
  final errors = <String, String>{};
  final retryMore = <String, bool>{};
  final pages = <String, Set<String>>{};
  final controllers = <String, ScrollController>{};
  ForumUserHome? home;
  String? profileError;
  bool profileLoading = false, actionBusy = false;
  int selected = 0, revision = 0;
  String get section => sections[selected].$1;

  @override
  void initState() {
    super.initState();
    if (!widget.ownAccount) sessionRevision.addListener(accountChanged);
    for (final (key, _) in sections) {
      final controller = controllers[key] = ScrollController();
      controller.addListener(() {
        if (controller.hasClients &&
            controller.position.extentAfter < 600 &&
            contents[key]?.next != null &&
            errors[key] == null) {
          unawaited(loadSection(key, more: true));
        }
      });
    }
    home = widget.initialHome;
    if (home == null) unawaited(loadProfile());
    unawaited(loadSection('thread'));
  }

  @override
  void dispose() {
    if (!widget.ownAccount) sessionRevision.removeListener(accountChanged);
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void accountChanged() {
    revision++;
    setState(() {
      home = null;
      contents.clear();
      loading.clear();
      errors.clear();
      pages.clear();
      profileLoading = false;
    });
    unawaited(loadProfile());
    unawaited(loadSection('thread'));
  }

  Future<void> loadProfile() async {
    if (profileLoading) return;
    final generation = revision;
    setState(() {
      profileLoading = true;
      profileError = null;
    });
    try {
      final data = ForumUserHome(
        await widget.client.source(widget.uri.toString()),
        widget.uri,
      );
      final uid = widget.uri.queryParameters['uid'];
      if (uid != null && uid != data.account.uid) {
        throw const ForumFailure('论坛返回的用户资料与目标账号不一致，请重试。');
      }
      if (!mounted || generation != revision) return;
      setState(() => home = data);
    } catch (e) {
      if (mounted && generation == revision) {
        setState(() => profileError = '$e');
      }
    } finally {
      if (mounted && generation == revision) {
        setState(() => profileLoading = false);
        if (section != 'profile' &&
            section != 'thread' &&
            !contents.containsKey(section)) {
          unawaited(loadSection(section));
        }
      }
    }
  }

  Future<void> loadSection(String key, {bool more = false}) async {
    if (key == 'profile' || loading.contains(key)) return;
    final first = key == 'thread'
        ? userTopicsUri(widget.uri)
        : home?.sections[key];
    if (first == null) return;
    final target = more ? contents[key]?.next : first;
    if (target == null ||
        (more && (pages[key]?.contains(target.toString()) ?? false))) {
      return;
    }
    final generation = revision;
    setState(() {
      loading.add(key);
      errors.remove(key);
      retryMore[key] = more;
    });
    try {
      final data = ForumUserContent(
        await widget.client.source(target.toString()),
        target,
        topics: key == 'thread',
        archivedAvailable: contents[key]?.archiveAvailable ?? false,
      );
      if (!mounted || generation != revision) return;
      setState(() {
        final previous = contents[key];
        if (more && previous != null) {
          final ids = previous.threads.map((e) => e.url).toSet();
          previous.threads.addAll(data.threads.where((e) => ids.add(e.url)));
          final entryIds = previous.entries.map((e) => e.id).toSet();
          previous.entries.addAll(
            data.entries.where((e) => entryIds.add(e.id)),
          );
          previous.next = data.next;
          previous.archiveAvailable = data.archiveAvailable;
        } else {
          contents[key] = data;
          pages[key] = {};
        }
        pages.putIfAbsent(key, () => {}).add(target.toString());
        if (pages[key]!.contains(contents[key]?.next?.toString())) {
          contents[key]!.next = null;
        }
      });
    } catch (e) {
      if (mounted && generation == revision) setState(() => errors[key] = '$e');
    } finally {
      if (mounted && generation == revision) {
        setState(() => loading.remove(key));
      }
    }
  }

  Future<void> openLink(ForumLink link) =>
      openForum(context, link, widget.client, widget.preferences);

  Future<void> action(String type) async {
    if (actionBusy || home?.actions[type] == null) return;
    final targetUid = home!.account.uid;
    setState(() => actionBusy = true);
    try {
      if (!await showForumLogin(context, widget.client) || !mounted) return;
      final session = await forumAuthCookie();
      final generation = revision;
      final fresh = ForumUserHome(
        await widget.client.source(widget.uri.toString()),
        widget.uri,
      );
      if (fresh.account.uid != targetUid) {
        throw const ForumFailure('用户状态已变化，请刷新主页。');
      }
      final link = fresh.actions[type];
      final currentSession = await forumAuthCookie();
      if (!mounted || generation != revision || session != currentSession) {
        return;
      }
      if (link == null) throw const ForumFailure('此操作已不可用，请刷新主页。');
      if (type != 'follow') {
        await openForumWeb(
          context,
          link.title,
          link.url,
          client: widget.client,
          preferences: widget.preferences,
        );
      } else {
        if (Uri.parse(link.url).queryParameters['op'] == 'del') {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('取消收听此用户？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('确认'),
                ),
              ],
            ),
          );
          if (confirm != true) return;
        }
        if (!mounted ||
            generation != revision ||
            session != await forumAuthCookie()) {
          return;
        }
        final result = await widget.client.submit(
          Uri.parse(link.url),
          {},
          method: 'GET',
        );
        final message = html
            .parse(result.$1)
            .querySelector('#messagetext,.alert_error')
            ?.text
            .trim();
        if (message != null &&
            message.isNotEmpty &&
            !RegExp('成功|已收听|已关注').hasMatch(message)) {
          throw ForumFailure(message);
        }
      }
      if (mounted) await loadProfile();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e\n操作未自动重试。')));
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  Future<void> writeWall() async {
    if (!await showForumLogin(context, widget.client) || !mounted) return;
    await loadSection('wall');
    if (!mounted) return;
    final form = contents['wall']?.wallForm;
    if (form == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('论坛未提供可用的留言表单，请刷新后重试。')));
      return;
    }
    final session = await forumAuthCookie();
    final generation = revision;
    if (!mounted) return;
    var busy = false;
    var dirty = false;
    String? error;
    Future<void> closeEditor(BuildContext sheetContext) async {
      if (busy) return;
      if (dirty) {
        final discard = await showDialog<bool>(
          context: sheetContext,
          builder: (context) => AlertDialog(
            title: const Text('放弃这条留言？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃'),
              ),
            ],
          ),
        );
        if (discard != true) return;
      }
      if (sheetContext.mounted) Navigator.pop(sheetContext);
    }

    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => PopScope(
          canPop: !busy && !dirty,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && !busy) unawaited(closeEditor(sheetContext));
          },
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '写留言',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭留言',
                          onPressed: busy
                              ? null
                              : () => closeEditor(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    NativeForumFormView(
                      form: form,
                      busy: busy,
                      onChanged: () {
                        if (!dirty) setSheetState(() => dirty = true);
                      },
                      onLink: (url) => openForumWeb(
                        context,
                        '留言',
                        url,
                        client: widget.client,
                        preferences: widget.preferences,
                      ),
                      onSubmit: (form, values, button) async {
                        if (busy) return;
                        setSheetState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          if (session != await forumAuthCookie() ||
                              generation != revision) {
                            throw const ForumFailure('账号状态已变化，请重新打开留言。');
                          }
                          final name = button?.attributes['name'];
                          if (name != null && name.isNotEmpty) {
                            values[name] =
                                button?.attributes['value'] ?? 'true';
                          }
                          final result = await widget.client.submit(
                            form.action,
                            values,
                            method: form.method,
                          );
                          if (generation != revision ||
                              session != await forumAuthCookie()) {
                            throw const ForumFailure('账号状态已变化。');
                          }
                          final notice = NativeForumDocument(
                            result.$1,
                            result.$2,
                          ).notice;
                          if (!RegExp('成功|留言完成|操作完成').hasMatch(notice)) {
                            throw ForumFailure(
                              notice.isEmpty ? '尚未确认留言成功，请核实后再操作。' : notice,
                            );
                          }
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            setSheetState(() => error = '$e\n提交未自动重试，输入已保留。');
                          }
                        } finally {
                          if (sheetContext.mounted) {
                            setSheetState(() => busy = false);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (sent == true && mounted) await loadSection('wall');
  }

  Widget identity() {
    final theme = Theme.of(context);
    final user = home?.account;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ForumAvatar(
                url:
                    user?.avatar ??
                    authorAvatar(widget.uri.toString(), widget.uri),
                radius: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ??
                          (widget.name.isEmpty ? '用户主页' : widget.name),
                      style: theme.textTheme.titleLarge,
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (home?.role.isNotEmpty == true)
                          ForumLabel(home!.role),
                        if ((user?.uid ?? widget.uri.queryParameters['uid'])
                            case final String uid)
                          Text(
                            'UID: $uid',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (home?.signature.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                home!.signature,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          if (!widget.ownAccount && home?.actions.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in home!.actions.entries)
                    if (entry.key == 'pm')
                      FilledButton.tonalIcon(
                        onPressed: actionBusy ? null : () => action(entry.key),
                        icon: const Icon(Icons.mail_outline, size: 18),
                        label: Text(entry.value.title),
                      )
                    else
                      OutlinedButton(
                        onPressed: actionBusy ? null : () => action(entry.key),
                        child: Text(entry.value.title),
                      ),
                ],
              ),
            ),
          if (profileError != null)
            TextButton.icon(
              onPressed: loadProfile,
              icon: const Icon(Icons.refresh),
              label: const Text('用户信息加载失败，点击重试'),
            ),
        ],
      ),
    );
  }

  Widget entryCard(ForumUserEntry entry) => AppSectionCard(
    borderRadius: 12,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: entry.profile.isEmpty
                ? null
                : () => openLink(ForumLink(entry.author, entry.profile)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ForumAvatar(
                    url: entry.avatar ?? home?.account.avatar,
                    radius: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.author.isEmpty
                              ? home?.account.name ?? '匿名用户'
                              : entry.author,
                        ),
                        if (entry.date.isNotEmpty)
                          Text(
                            entry.date,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (entry.body.isNotEmpty)
            HtmlWidget(
              entry.body,
              baseUrl: widget.uri,
              textStyle: Theme.of(context).textTheme.bodyMedium,
              customStylesBuilder: (element) => {
                'overflow-wrap': 'anywhere',
                'max-width': '100%',
                'white-space': element.localName == 'pre'
                    ? 'pre-wrap'
                    : 'normal',
              },
              onTapUrl: (url) async {
                await openLink(ForumLink('查看', url));
                return true;
              },
            ),
          if (entry.thread != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                entry.thread!.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openLink(entry.thread!),
            ),
          if (entry.actions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final link in entry.actions)
                  TextButton(
                    onPressed: () => openForumWeb(
                      context,
                      link.title,
                      link.url,
                      client: widget.client,
                      preferences: widget.preferences,
                    ),
                    child: Text(link.title),
                  ),
              ],
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = contents[section];
    final tabHeight = (MediaQuery.textScalerOf(context).scale(14) * 2 + 20)
        .clamp(48.0, double.infinity);
    final count = section == 'profile'
        ? home?.account.fields.length ?? 0
        : section == 'thread'
        ? data?.threads.length ?? 0
        : data?.entries.length ?? 0;
    return DefaultTabController(
      length: sections.length,
      child: Scaffold(
        appBar: ReviewFrostedAppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: loading.contains(section) || profileLoading
                  ? null
                  : () {
                      unawaited(loadProfile());
                      unawaited(loadSection(section));
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(tabHeight),
            child: SizedBox(
              height: tabHeight,
              child: TabBar(
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                tabs: [
                  for (final (_, label) in sections)
                    Tab(
                      child: Text(
                        label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
                onTap: (index) {
                  if (index == selected) return;
                  HapticFeedbackUtil.light();
                  setState(() => selected = index);
                  if (!contents.containsKey(section)) {
                    unawaited(loadSection(section));
                  }
                },
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.bottomNavigationBar,
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 840),
              child: ListView.builder(
                key: PageStorageKey('user-${widget.uri}-$section'),
                controller: controllers[section],
                padding: const EdgeInsets.all(16),
                itemCount: count + 3,
                itemBuilder: (context, index) {
                  if (index == 0) return identity();
                  if (index == 1) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (loading.contains(section) ||
                            (profileLoading && home == null))
                          const LinearProgressIndicator(),
                        if (section == 'wall' && data?.wallAvailable == true)
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: writeWall,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('写留言'),
                            ),
                          ),
                        if (errors[section] != null)
                          FailurePanel(
                            message: errors[section]!,
                            retry: () => loadSection(
                              section,
                              more: retryMore[section] ?? false,
                            ),
                          ),
                        if (count == 0 &&
                            !loading.contains(section) &&
                            errors[section] == null &&
                            !profileLoading)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              section == 'profile'
                                  ? profileError ?? '暂无公开资料'
                                  : data?.emptyMessage.isNotEmpty == true
                                  ? data!.emptyMessage
                                  : data != null
                                  ? '暂无${sections[selected].$2}'
                                  : '论坛未提供该栏目的内容',
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    );
                  }
                  if (index == count + 2) {
                    return data?.next != null && !loading.contains(section)
                        ? TextButton(
                            onPressed: () => loadSection(section, more: true),
                            child: const Text('加载更多'),
                          )
                        : const SizedBox(height: 16);
                  }
                  if (section == 'profile') {
                    final field = home!.account.fields[index - 2];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      title: Text(field.$1),
                      subtitle: Text(field.$2),
                    );
                  }
                  if (section == 'thread') {
                    final item = data!.threads[index - 2];
                    final user = home?.account;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppSectionCard(
                        borderRadius: 12,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: ThreadTile(
                            key: ValueKey(item.url),
                            link: item.copyWith(
                              author: user?.name ?? widget.name,
                              imageUrl: user?.avatar,
                              role: home?.role,
                              profile: widget.uri.toString(),
                            ),
                            onTap: openLink,
                          ),
                        ),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: entryCard(data!.entries[index - 2]),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
