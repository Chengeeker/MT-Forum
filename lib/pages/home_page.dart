import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/design_system/components/review_preference_tile.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/forum_avatar.dart';
import '../data/forum.dart';
import '../data/preferences.dart';
import 'forum_page.dart';
import 'login_page.dart';
import 'native_forum_page.dart';
import 'settings_page.dart';
import 'web_page.dart';
import '../data/native_forum.dart';

const boards = <(String, String, IconData)>[
  ('版本发布', '2', Icons.rocket_launch_outlined),
  ('插件交流', '37', Icons.extension_outlined),
  ('建议反馈', '38', Icons.fact_check_outlined),
  ('逆向交流', '41', Icons.code_outlined),
  ('玩机交流', '39', Icons.phone_android_outlined),
  ('编程开发', '42', Icons.terminal_outlined),
  ('求助问答', '40', Icons.help_outline),
  ('综合交流', '44', Icons.forum_outlined),
  ('休闲灌水', '50', Icons.coffee_outlined),
  ('官方公告', '46', Icons.campaign_outlined),
  ('申诉举报', '53', Icons.shield_outlined),
  ('站务专区', '92', Icons.admin_panel_settings_outlined),
];
const latestInitialBatchSize = 20;

const messageSections = <(String, String)>[
  ('消息', 'home.php?mod=space&do=pm'),
  ('我的帖子', 'home.php?mod=space&do=notice&view=mypost'),
  ('坛友互动', 'home.php?mod=space&do=notice&view=interactive'),
  ('系统提醒', 'home.php?mod=space&do=notice&view=system'),
  ('应用提醒', 'home.php?mod=space&do=notice&view=app'),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.client, required this.preferences});
  final ForumClient client;
  final Preferences preferences;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> openSite(String title, String path) => openForumWeb(
    context,
    title,
    path,
    client: widget.client,
    preferences: widget.preferences,
  );

  bool get useFloatingNavigation =>
      widget.preferences.floatingNavigation &&
      MediaQuery.textScalerOf(context).scale(12) <= 16;

  double get floatingNavigationWidth => math.min(
    440.0,
    MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal -
        32,
  );

  int tab = 0;
  bool messagesOpened = false;
  GlobalKey<NativeForumPageState> messageKey = GlobalKey();
  Uri messageUri = forumUri(messageSections.first.$2);
  List<ForumMessageTab> messageSubTabs = const [];
  final scroll = ScrollController();
  ForumDocument? document;
  List<ForumLink>? latest;
  String? latestNext, latestError;
  bool latestLoading = false;
  int feedRevision = 0;
  final latestPages = <String>{};
  String? error;
  bool loading = false, expanded = true;
  int revision = 0;
  ForumAccount? account;
  String? accountError;
  bool accountLoading = false;
  @override
  void initState() {
    super.initState();
    sessionRevision.addListener(accountChanged);
    forumAuthenticated.addListener(authChanged);
    scroll.addListener(() {
      if (scroll.position.extentAfter < 600 && latestError == null) {
        loadLatest();
      }
    });
    unawaited(forumAuthCookie());
    refresh();
  }

  @override
  void dispose() {
    sessionRevision.removeListener(accountChanged);
    forumAuthenticated.removeListener(authChanged);
    scroll.dispose();
    super.dispose();
  }

  void accountChanged() {
    revision++;
    setState(() {
      document = null;
      latest = null;
      feedRevision++;
      latestNext = null;
      latestError = null;
      latestLoading = false;
      latestPages.clear();
      error = null;
      loading = false;
      account = null;
      accountError = null;
      accountLoading = false;
      messageKey = GlobalKey();
      messageSubTabs = const [];
    });
    refresh();
    if (tab == 4) loadAccount();
  }

  void authChanged() {
    if (!forumAuthenticated.value) {
      setState(() {
        account = null;
        accountError = null;
      });
    } else {
      setState(() {});
      if (tab == 4) loadAccount();
    }
  }

  Future<void> loadAccount() async {
    if (accountLoading || account != null || !forumAuthenticated.value) return;
    final generation = revision;
    setState(() {
      accountLoading = true;
      accountError = null;
    });
    try {
      final data = ForumAccount.parse(
        await widget.client
            .source(forumUri('home.php?mod=space&do=profile').toString())
            .timeout(const Duration(seconds: 30)),
      );
      if (mounted && generation == revision && forumAuthenticated.value) {
        setState(() => account = data);
      }
    } catch (_) {
      if (mounted && generation == revision) {
        setState(() => accountError = '资料读取失败，点击重试或管理账号');
      }
    } finally {
      if (mounted && generation == revision) {
        setState(() => accountLoading = false);
      }
    }
  }

  Future<void> refresh() async {
    if (loading) return;
    final generation = revision;
    final feed = ++feedRevision;
    setState(() {
      loading = true;
      error = null;
      latestError = null;
      latestLoading = false;
    });
    try {
      final data = await widget.client.load('$forumOrigin/');
      if (!mounted || generation != revision) return;
      setState(() {
        document = data;
      });
      try {
        final guide = await widget.client.load(
          '$forumOrigin/forum.php?mod=guide&view=newthread',
        );
        if (mounted && generation == revision) {
          const guideUrl = '$forumOrigin/forum.php?mod=guide&view=newthread';
          final batchPages = <String>{guideUrl};
          final batchItems = [...guide.links];
          final seenItems = batchItems.map((item) => item.url).toSet();
          var batchNext = guide.next;
          String? batchError;
          while (batchItems.length < latestInitialBatchSize &&
              batchNext != null &&
              !batchPages.contains(batchNext)) {
            final target = batchNext;
            try {
              final page = await widget.client.load(target);
              if (!mounted || generation != revision || feed != feedRevision) {
                return;
              }
              batchPages.add(target);
              final added = page.links
                  .where((item) => seenItems.add(item.url))
                  .toList();
              batchItems.addAll(added);
              batchNext = added.isEmpty || batchPages.contains(page.next)
                  ? null
                  : page.next;
            } catch (e) {
              batchError = e.toString();
              break;
            }
          }
          if (batchNext != null && batchPages.contains(batchNext)) {
            batchNext = null;
          }
          setState(() {
            if (batchItems.isNotEmpty) latest = batchItems;
            latest ??= data.latest;
            latestPages.clear();
            latestPages.addAll(batchPages);
            latestNext = batchNext;
            latestError = batchError;
          });
        }
      } catch (_) {
        if (mounted && feed == feedRevision) {
          setState(() {
            latest ??= data.latest;
            latestPages.clear();
            latestNext = '$forumOrigin/forum.php?mod=guide&view=newthread';
            latestError = '最新帖子导读加载失败，已保留现有内容';
          });
        }
      }
    } catch (e) {
      if (mounted && generation == revision) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && generation == revision) setState(() => loading = false);
    }
  }

  Future<void> loadLatest() async {
    final target = latestNext;
    if (loading ||
        latestLoading ||
        target == null ||
        latestPages.contains(target)) {
      return;
    }
    final generation = revision, feed = feedRevision;
    setState(() {
      latestLoading = true;
      latestError = null;
    });
    try {
      final data = await widget.client.load(target);
      if (!mounted || generation != revision || feed != feedRevision) return;
      setState(() {
        final items = [...?latest];
        final seen = items.map((item) => item.url).toSet();
        final added = data.links.where((item) => seen.add(item.url)).toList();
        latest = [...items, ...added];
        latestPages.add(target);
        latestNext = added.isEmpty || latestPages.contains(data.next)
            ? null
            : data.next;
      });
    } catch (e) {
      if (mounted && generation == revision && feed == feedRevision) {
        setState(() => latestError = e.toString());
      }
    } finally {
      if (mounted && generation == revision && feed == feedRevision) {
        setState(() => latestLoading = false);
      }
    }
  }

  void browse(ForumLink link) =>
      openForum(context, link, widget.client, widget.preferences);
  void guide(String name, String view) =>
      browse(ForumLink(name, '$forumOrigin/forum.php?mod=guide&view=$view'));

  Widget boardAvatar((String, String, IconData) board) {
    final imageUrl = document?.boards
        .where((item) => item.url.contains('/forum-${board.$2}-'))
        .map((item) => item.imageUrl)
        .whereType<String>()
        .firstOrNull;
    final fallback = Icon(board.$3);
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
      foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
      child: imageUrl == null
          ? fallback
          : ClipOval(
              child: Image.network(
                imageUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }

  Future<void> compose() async {
    final selected = await showModalBottomSheet<(String, String, IconData)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('选择发帖板块', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .6,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final b in boards)
                      ListTile(
                        leading: Icon(b.$3),
                        title: Text(b.$1),
                        onTap: () => Navigator.pop(context, b),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      await openSite(
        '发帖 · ${selected.$1}',
        'forum.php?mod=post&action=newthread&fid=${selected.$2}',
      );
    }
  }

  void selectTab(int index) {
    HapticFeedbackUtil.selection();
    if (index == 2) {
      compose();
      return;
    }
    if (index == tab && index == 0) {
      scroll.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    setState(() {
      tab = index;
      if (index == 3) messagesOpened = true;
    });
    if (index == 4) {
      unawaited(forumAuthCookie().then((_) => loadAccount()));
    }
  }

  int get selectedMessageSection {
    final uri = messageUri;
    final view = uri.queryParameters['view'];
    if (uri.queryParameters['do'] == 'pm') return 0;
    return messageSections
        .indexWhere((section) {
          final target = forumUri(section.$2);
          return target.queryParameters['view'] == view;
        })
        .clamp(0, messageSections.length - 1);
  }

  Uri _messageCategoryUri(Uri uri) {
    final query = uri.queryParameters;
    if (uri.queryParameters['do'] == 'pm') {
      final filter = query['filter'];
      return forumUri('home.php').replace(
        queryParameters: {
          'mod': 'space',
          'do': 'pm',
          if (filter != null) 'filter': filter,
        },
      );
    }
    final view = query['view'];
    if (uri.queryParameters['do'] == 'notice' &&
        messageSections.any(
          (section) => forumUri(section.$2).queryParameters['view'] == view,
        )) {
      final type = query['type'];
      return forumUri('home.php').replace(
        queryParameters: {
          'mod': 'space',
          'do': 'notice',
          'view': view!,
          if (type != null && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(type))
            'type': type,
        },
      );
    }
    return forumUri(messageSections.first.$2);
  }

  void selectMessageSection(int index) {
    if (index == selectedMessageSection) return;
    final target = forumUri(messageSections[index].$2);
    if (!forumAuthenticated.value) {
      setState(() {
        messageUri = target;
        messageSubTabs = const [];
      });
      return;
    }
    unawaited(
      messageKey.currentState?.openLink(target.toString()) ??
          Future<void>.value(),
    );
  }

  void selectMessageSubTab(int index) {
    final selected = messageSubTabs[index];
    unawaited(
      messageKey.currentState?.openLink(selected.url, selected.label) ??
          Future<void>.value(),
    );
  }

  void messageDocumentChanged(NativeForumDocument document) {
    if (!mounted) return;
    final nextUri = _messageCategoryUri(document.uri);
    final nextTabs = document.messageTabs;
    if (nextUri == messageUri &&
        nextTabs
                .map((tab) => '${tab.label}:${tab.url}:${tab.selected}')
                .join('|') ==
            messageSubTabs
                .map((tab) => '${tab.label}:${tab.url}:${tab.selected}')
                .join('|')) {
      return;
    }
    setState(() {
      messageUri = nextUri;
      messageSubTabs = nextTabs;
    });
  }

  Widget messageTabRow(
    List<(String, String)> tabs,
    int selectedIndex,
    ValueChanged<int> onSelected,
    String keyPrefix,
  ) => DefaultTabController(
    key: ValueKey('$keyPrefix-$selectedIndex-${tabs.length}'),
    length: tabs.length,
    initialIndex: selectedIndex,
    child: Builder(
      builder: (tabContext) => SizedBox(
        height: messageTabHeight,
        child: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 12),
          tabs: [for (final item in tabs) Tab(text: item.$1)],
          onTap: (index) {
            if (index == selectedIndex) return;
            DefaultTabController.of(tabContext).index = selectedIndex;
            onSelected(index);
          },
        ),
      ),
    ),
  );

  double get messageTabHeight => math.max(
    kTextTabBarHeight,
    MediaQuery.textScalerOf(context).scale(15) * 1.5 + 16,
  );

  PreferredSizeWidget? messageTabsBottom() {
    if (tab != 3) return null;
    final sectionIndex = selectedMessageSection;
    final showSubTabs = forumAuthenticated.value && messageSubTabs.isNotEmpty;
    final rows = showSubTabs ? 2 : 1;
    return PreferredSize(
      preferredSize: Size.fromHeight(messageTabHeight * rows),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          messageTabRow(
            messageSections,
            sectionIndex,
            selectMessageSection,
            'message-primary',
          ),
          if (showSubTabs)
            messageTabRow(
              [for (final item in messageSubTabs) (item.label, item.url)],
              messageSubTabs
                  .indexWhere((item) => item.selected)
                  .clamp(0, messageSubTabs.length - 1),
              selectMessageSubTab,
              'message-secondary',
            ),
        ],
      ),
    );
  }

  double bottomContentPadding(BuildContext context) => !useFloatingNavigation
      ? 24
      : widget.preferences.liquidGlass
      ? MediaQuery.viewPaddingOf(context).bottom + 76
      : 72;

  Widget sectionTitle(String title, {VoidCallback? more}) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (more != null)
          IconButton(
            tooltip: '更多$title',
            onPressed: more,
            icon: const Icon(Icons.chevron_right),
          ),
      ],
    ),
  );

  Widget threadSection(String title, List<ForumLink> items, String view) =>
      AppSectionCard(
        borderRadius: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(
              title,
              more: () => view == 'hot'
                  ? openSite('排行榜', 'misc.php?mod=ranklist')
                  : guide(title, view),
            ),
            if (loading && items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!loading && items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error == null ? '暂时没有内容' : '内容未能加载',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            for (final (index, item)
                in items.take(view == 'hot' ? 10 : 5).indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: view == 'hot'
                    ? ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 24,
                          child: Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                        minLeadingWidth: 24,
                        horizontalTitleGap: 8,
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w400),
                        ),
                        onTap: () => browse(item),
                      )
                    : ThreadTile(
                        key: ValueKey('$revision:${item.url}'),
                        link: item,
                        loadSummary: (active) {
                          final generation = revision;
                          return widget.client.threadSummary(
                            item.url,
                            () => active() && mounted && generation == revision,
                          );
                        },
                        onTap: () => browse(item),
                      ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );

  Widget home() => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
    child: RefreshIndicator(
      onRefresh: refresh,
      edgeOffset: MediaQuery.paddingOf(context).top + kToolbarHeight,
      child: ListView.builder(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          10,
          MediaQuery.paddingOf(context).top + kToolbarHeight + 6,
          10,
          bottomContentPadding(context),
        ),
        itemCount: (latest ?? const <ForumLink>[]).length + 2,
        itemBuilder: (context, index) {
          final items = latest ?? const <ForumLink>[];
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in <(String, IconData, VoidCallback)>[
                        (
                          '签到',
                          Icons.event_available_outlined,
                          () => openSite('签到', 'k_misign-sign.html'),
                        ),
                        (
                          '精华',
                          Icons.star_outline_rounded,
                          () => guide('精华', 'digest'),
                        ),
                        (
                          '版规',
                          Icons.gavel_outlined,
                          () => browse(
                            const ForumLink(
                              'MT论坛总版规',
                              '$forumOrigin/thread-85763-1-1.html',
                            ),
                          ),
                        ),
                        (
                          '手册',
                          Icons.menu_book_outlined,
                          () => openExternal(
                            context,
                            Uri.parse('https://mt.cc/guide/'),
                          ),
                        ),
                      ])
                        SizedBox(
                          width: (constraints.maxWidth - 24) / 4,
                          child: AppSectionCard(
                            borderRadius: 12,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: item.$3,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                  horizontal: 2,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      item.$2,
                                      size: 24,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      item.$1,
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AppSectionCard(
                  borderRadius: 12,
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        minTileHeight: 48,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        title: Text(
                          '板块',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        trailing: Icon(
                          expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        onTap: () => setState(() => expanded = !expanded),
                      ),
                      if (expanded)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth > 650
                                ? 6
                                : (MediaQuery.textScalerOf(context).scale(14) >
                                          22
                                      ? 3
                                      : 4);
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: Wrap(
                                children: [
                                  for (final b in boards)
                                    SizedBox(
                                      width:
                                          (constraints.maxWidth - 16) / columns,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () => browse(
                                          ForumLink(
                                            b.$1,
                                            '$forumOrigin/forum-${b.$2}-1.html',
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 4,
                                            horizontal: 2,
                                          ),
                                          child: Column(
                                            children: [
                                              boardAvatar(b),
                                              const SizedBox(height: 4),
                                              Text(
                                                b.$1,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (error != null)
                  FailurePanel(message: error!, retry: refresh),
                threadSection('排行榜', document?.hot ?? [], 'hot'),
                const SizedBox(height: 8),
                sectionTitle('最新帖子', more: () => guide('最新帖子', 'newthread')),
              ],
            );
          }
          if (index <= items.length) {
            final item = items[index - 1];
            return ThreadTile(
              key: ValueKey('$revision:${item.url}'),
              link: item,
              onTap: () => browse(item),
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: latestLoading || (loading && items.isEmpty)
                ? const Center(child: CircularProgressIndicator())
                : latestError != null
                ? FailurePanel(message: latestError!, retry: loadLatest)
                : Center(
                    child: latestNext != null
                        ? TextButton(
                            onPressed: loadLatest,
                            child: const Text('加载更多帖子'),
                          )
                        : Text(items.isEmpty ? '暂时没有内容' : '已经到底了'),
                  ),
          );
        },
      ),
    ),
  );

  Widget discover() => ListView(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
      16,
      bottomContentPadding(context),
    ),
    children: [
      SearchBar(
        hintText: '搜索帖子、作者与内容',
        leading: const Padding(
          padding: EdgeInsetsDirectional.only(start: 8),
          child: Icon(Icons.search),
        ),
        onTap: () {
          HapticFeedbackUtil.light();
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SearchPage(client: widget.client),
            ),
          );
        },
        readOnly: true,
      ),
      const SizedBox(height: 24),
      AppSectionCard(
        child: Column(
          children: [
            for (final item in [
              ('最新发表', 'newthread', Icons.schedule),
              ('最新回复', 'new', Icons.chat_bubble_outline),
              ('人气热门', 'hot', Icons.local_fire_department_outlined),
              ('精华内容', 'digest', Icons.star_outline),
            ])
              ReviewPreferenceTile(
                title: item.$1,
                leading: Icon(item.$3),
                onTap: () => guide(item.$1, item.$2),
              ),
            ReviewPreferenceTile(
              title: '排行榜',
              leading: const Icon(Icons.leaderboard_outlined),
              onTap: () => openSite('排行榜', 'misc.php?mod=ranklist'),
            ),
          ],
        ),
      ),
    ],
  );

  Widget profile() => ListView(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + kToolbarHeight + 16,
      16,
      bottomContentPadding(context),
    ),
    children: [
      AppSectionCard(
        child: ReviewPreferenceTile(
          title:
              account?.name ?? (forumAuthenticated.value ? '论坛账号' : '登录 / 注册'),
          subtitle: account != null
              ? 'UID: ${account!.uid}'
              : accountLoading
              ? '正在读取账号资料…'
              : accountError ??
                    (forumAuthenticated.value ? '查看资料及管理账号' : '登录、查看资料及管理账号'),
          leading: ForumAvatar(url: account?.avatar, radius: 20),
          onTap: () async {
            await openSite('我的账号', 'home.php?mod=space&do=profile');
            if (mounted) {
              setState(() => account = null);
              await loadAccount();
            }
          },
        ),
      ),
      const SizedBox(height: 24),
      AppSectionCard(
        child: Column(
          children: [
            ReviewPreferenceTile(
              title: '我的帖子',
              leading: const Icon(Icons.article_outlined),
              onTap: () =>
                  openSite('我的帖子', 'home.php?mod=space&do=thread&view=me'),
            ),
            ReviewPreferenceTile(
              title: '我的收藏',
              leading: const Icon(Icons.bookmark_border),
              onTap: () =>
                  openSite('我的收藏', 'home.php?mod=space&do=favorite&view=me'),
            ),
            ReviewPreferenceTile(
              title: '浏览历史',
              leading: const Icon(Icons.history),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => HistoryPage(
                    client: widget.client,
                    preferences: widget.preferences,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      AppSectionCard(
        child: Column(
          children: [
            ReviewPreferenceTile(
              title: '个性化',
              subtitle: '主题、配色与触感',
              leading: const Icon(Icons.palette_outlined),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(preferences: widget.preferences),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget navigationBar() {
    if (!useFloatingNavigation) {
      final theme = Theme.of(context);
      return Theme(
        data: theme.copyWith(
          navigationBarTheme: theme.navigationBarTheme.copyWith(
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? Colors.transparent
                  : null,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: '首页',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: '发现'),
            NavigationDestination(icon: Icon(Icons.add), label: '发帖'),
            NavigationDestination(icon: Icon(Icons.mail_outline), label: '消息'),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      );
    }
    if (!widget.preferences.liquidGlass) return floatingNavigationBar();
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom > 0 ? 6 : 14,
          ),
          child: RepaintBoundary(
            child: SizedBox(
              width: floatingNavigationWidth,
              height: 56,
              child: GlassTabBar.bottom(
                tabs: const [
                  GlassTab(
                    icon: Icon(Icons.home_outlined),
                    activeIcon: Icon(Icons.home_rounded),
                    label: '首页',
                  ),
                  GlassTab(icon: Icon(Icons.search), label: '发现'),
                  GlassTab(icon: Icon(Icons.add), label: '发帖'),
                  GlassTab(icon: Icon(Icons.mail_outline), label: '消息'),
                  GlassTab(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: '我的',
                  ),
                ],
                selectedIndex: tab,
                onTabSelected: selectTab,
                barHeight: 56,
                horizontalPadding: 0,
                verticalPadding: 0,
                barBorderRadius: 9999,
                indicatorBorderRadius: 9999,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x66000000),
                  bodyMode: GlassBodyMode.clear,
                  thickness: 10,
                  blur: 2,
                  lightIntensity: 0.25,
                  ambientStrength: 0,
                  refractiveIndex: 1.19,
                  chromaticAberration: 0.008,
                  shadowElevation: 0,
                ),
                indicatorSettings: const LiquidGlassSettings(
                  refractiveIndex: 1.18,
                  chromaticAberration: 0.025,
                ),
                quality: GlassQuality.premium,
                backgroundQuality: GlassQuality.premium,
                maskingQuality: MaskingQuality.high,
                enableBlend: true,
                innerBlur: 6,
                interactionBehavior: GlassInteractionBehavior.none,
                indicatorPinchStrength: 0,
                indicatorColor: const Color(0x66000000),
                selectedIconColor: Colors.white,
                selectedLabelColor: Colors.white,
                unselectedIconColor: Colors.white,
                unselectedLabelColor: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget floatingNavigationBar() {
    final scheme = Theme.of(context).colorScheme;
    const destinations = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home_rounded, '首页'),
      (Icons.search, Icons.search, '发现'),
      (Icons.add, Icons.add, '发帖'),
      (Icons.mail_outline, Icons.mail, '消息'),
      (Icons.person_outline, Icons.person, '我的'),
    ];
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom > 0 ? 6 : 14,
          ),
          child: Container(
            width: floatingNavigationWidth,
            height: 56,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.35
                        : 0.12,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / destinations.length;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: itemWidth,
                        child: AnimatedSlide(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          offset: Offset(tab.toDouble(), 0),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          for (
                            var index = 0;
                            index < destinations.length;
                            index++
                          )
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(28),
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: () => selectTab(index),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        tab == index
                                            ? destinations[index].$2
                                            : destinations[index].$1,
                                        size: 21,
                                        color: tab == index
                                            ? scheme.onSecondaryContainer
                                            : scheme.onSurfaceVariant,
                                      ),
                                      Text(
                                        destinations[index].$3,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: tab == index
                                                  ? scheme.onSecondaryContainer
                                                  : scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: tab != 3,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || tab != 3) return;
      final messages = messageKey.currentState;
      if (messages?.submitting == true) return;
      if (messages?.dirty == true && !await messages!.confirmDiscard()) return;
      if (mounted) selectTab(0);
    },
    child: Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: useFloatingNavigation,
      appBar: ReviewFrostedAppBar(
        title: Text(
          tab == 0
              ? 'MT论坛'
              : tab == 1
              ? '发现'
              : tab == 3
              ? '消息'
              : '我的',
        ),
        actions: [
          if (tab == 0 && document?.online != null)
            Center(
              child: Text(
                '在线 ${document!.online}',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          if (tab == 0)
            IconButton(
              tooltip: '刷新首页',
              onPressed: loading ? null : refresh,
              icon: const Icon(Icons.refresh),
            ),
          if (tab == 3 && forumAuthenticated.value)
            IconButton(
              tooltip: '刷新消息',
              onPressed: () => messageKey.currentState?.load(),
              icon: const Icon(Icons.refresh),
            )
          else if (tab != 3)
            IconButton(
              tooltip: '消息',
              onPressed: () => selectTab(3),
              icon: const Icon(Icons.notifications_none),
            ),
        ],
        bottom: messageTabsBottom(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: IndexedStack(
            index: tab == 0
                ? 0
                : tab == 1
                ? 1
                : tab == 3
                ? 2
                : 3,
            children: [
              home(),
              discover(),
              if (messagesOpened && forumAuthenticated.value)
                NativeForumPage(
                  key: messageKey,
                  title: '消息',
                  uri: messageUri,
                  client: widget.client,
                  preferences: widget.preferences,
                  embedded: true,
                  onMessageDocument: messageDocumentChanged,
                  contentPadding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.paddingOf(context).top +
                        kToolbarHeight +
                        messageTabHeight *
                            (forumAuthenticated.value &&
                                    messageSubTabs.isNotEmpty
                                ? 2
                                : 1) +
                        16,
                    16,
                    bottomContentPadding(context),
                  ),
                )
              else if (messagesOpened)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.mail_outline, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          '登录后查看消息',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              showForumLogin(context, widget.client),
                          child: const Text('登录 / 注册'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              profile(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: navigationBar(),
    ),
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.client});
  final ForumClient client;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void submit() {
    final query = input.text.trim();
    if (query.isEmpty) return;
    HapticFeedbackUtil.light();
    FocusScope.of(context).unfocus();
    openForumWeb(
      context,
      '搜索 · $query',
      '/',
      client: widget.client,
      search: query,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const ReviewFrostedAppBar(title: Text('搜索论坛')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchBar(
            controller: input,
            onTap: HapticFeedbackUtil.light,
            autoFocus: true,
            hintText: '输入关键词',
            leading: const Icon(Icons.search),
            trailing: [
              IconButton(
                tooltip: '搜索',
                onPressed: submit,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
            onSubmitted: (_) => submit(),
          ),
          const SizedBox(height: 24),
          Text(
            '搜索结果由论坛提供，权限和搜索间隔以网站规则为准。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    ),
  );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.client,
    required this.preferences,
  });
  final ForumClient client;
  final Preferences preferences;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([preferences, sessionRevision]),
    builder: (context, _) => Scaffold(
      appBar: ReviewFrostedAppBar(
        title: const Text('浏览历史'),
        actions: [
          IconButton(
            tooltip: '清空历史',
            icon: const Icon(Icons.delete_outline),
            onPressed: preferences.history.isEmpty
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清空浏览历史？'),
                        content: const Text('此操作只清除本机记录。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) await preferences.clearHistory();
                  },
          ),
        ],
      ),
      body: preferences.history.isEmpty
          ? const Center(child: Text('还没有浏览记录'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: preferences.history.length,
              itemBuilder: (context, index) {
                final link = preferences.history[index];
                return ThreadTile(
                  key: ValueKey('${sessionRevision.value}:${link.url}'),
                  link: link,
                  loadSummary: (active) {
                    final revision = sessionRevision.value;
                    return client.threadSummary(
                      link.url,
                      () => active() && revision == sessionRevision.value,
                    );
                  },
                  onTap: () => openForum(context, link, client, preferences),
                );
              },
            ),
    ),
  );
}
