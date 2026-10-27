import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/widgets/app_section_card.dart';
import '../core/widgets/forum_avatar.dart';
import '../data/forum.dart';
import '../data/native_forum.dart';
import '../data/preferences.dart';
import 'forum_page.dart';
import 'login_page.dart';
import 'web_page.dart';

class NativeForumPage extends StatefulWidget {
  const NativeForumPage({
    super.key,
    required this.title,
    required this.uri,
    required this.client,
    required this.preferences,
    this.search,
    this.embedded = false,
    this.contentPadding,
    this.onMessageDocument,
  });
  final String title;
  final Uri uri;
  final ForumClient client;
  final Preferences preferences;
  final String? search;
  final bool embedded;
  final EdgeInsets? contentPadding;
  final ValueChanged<NativeForumDocument>? onMessageDocument;
  @override
  State<NativeForumPage> createState() => NativeForumPageState();
}

class NativeForumPageState extends State<NativeForumPage> {
  NativeForumDocument? document;
  String? error;
  String? documentSession;
  bool loading = false, submitting = false, prompted = false, dirty = false;
  bool sessionExpired = false;
  late Uri currentUri = widget.uri;
  final scroll = ScrollController();
  final selectedFavorites = <String>{};
  bool managingFavorites = false;
  int collectionRevision = 0;
  bool get isFavorites => widget.uri.queryParameters['do'] == 'favorite';
  bool get isPrivacy =>
      currentUri.queryParameters['mod'] == 'spacecp' &&
      currentUri.queryParameters['ac'] == 'privacy';
  double get privacyTabHeight =>
      (MediaQuery.textScalerOf(context).scale(14) + 28).clamp(
        48.0,
        double.infinity,
      );
  @override
  void initState() {
    super.initState();
    sessionRevision.addListener(accountChanged);
    load();
  }

  @override
  void dispose() {
    sessionRevision.removeListener(accountChanged);
    scroll.dispose();
    super.dispose();
  }

  void accountChanged() {
    if (!mounted) return;
    setState(() {
      document = null;
      documentSession = null;
      dirty = false;
      collectionRevision++;
      selectedFavorites.clear();
      error = '账号状态已变化，请返回后重新打开。';
    });
  }

  Future<void> load() async {
    if (loading || submitting) return;
    if (dirty && !await confirmDiscard()) return;
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
      sessionExpired = false;
    });
    var session = sessionRevision.value;
    try {
      final uri =
          widget.uri.path == '/member.php' &&
              widget.uri.queryParameters['mod'] == 'register'
          ? registrationUriFromHtml(
              await widget.client.source(
                forumUri('member.php?mod=logging&action=login').toString(),
              ),
            )
          : currentUri;
      var source = await widget.client.source(uri.toString());
      var data = NativeForumDocument(
        source,
        uri,
        extractMessageTabs: widget.embedded,
      );
      if (data.requiresLogin && widget.embedded) {
        sessionExpired = true;
        throw const ForumFailure('登录会话已失效，请重新登录。');
      }
      if (data.requiresLogin && !prompted && mounted) {
        prompted = true;
        if (!await showForumLogin(context, widget.client, force: true)) {
          if (mounted) Navigator.pop(context);
          return;
        }
        session = sessionRevision.value;
        source = await widget.client.source(uri.toString());
        data = NativeForumDocument(
          source,
          uri,
          extractMessageTabs: widget.embedded,
        );
      }
      if (data.requiresLogin) throw const ForumFailure('登录会话已失效，请重新登录后重试。');
      documentSession = await forumAuthCookie();
      if (!mounted || session != sessionRevision.value) return;
      if (!widget.embedded) {
        final page = html.parse(source);
        if (page.querySelector('#thread_subject') != null &&
            page.querySelector('[id^="postmessage_"]') != null) {
          final thread = parseForum(source, uri);
          if (thread.posts.isNotEmpty) {
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => ForumPage(
                  link: ForumLink(thread.title, uri.toString()),
                  client: widget.client,
                  preferences: widget.preferences,
                  initialDocument: thread,
                  forceThread: true,
                ),
              ),
            );
            return;
          }
        }
      }
      setState(() {
        document = data;
        collectionRevision++;
        selectedFavorites.clear();
        error = null;
      });
      if (data.messageTabs.isNotEmpty ||
          (widget.embedded &&
              ['pm', 'notice'].contains(data.uri.queryParameters['do']))) {
        widget.onMessageDocument?.call(data);
      }
      if (widget.search != null && mounted) {
        final form = html.parse(source).querySelector('form#scform');
        if (form == null) throw const ForumFailure('官网未返回搜索表单。');
        final model = NativeForumForm(form, widget.uri);
        final values = model.values()..['srchtxt'] = widget.search;
        await submit(model, values, model.buttons.firstOrNull);
      }
    } catch (e) {
      if (mounted && session == sessionRevision.value) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未提交的内容？'),
        content: const Text('当前编辑内容尚未提交。'),
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
    if (discard == true && mounted) setState(() => dirty = false);
    return discard == true;
  }

  Future<void> openLink(String href, [String title = 'MT论坛']) async {
    final uri = (document?.uri ?? widget.uri).resolve(href);
    if (!isForumUri(uri)) {
      if (mounted) await openExternal(context, uri);
      return;
    }
    if (!widget.embedded &&
        isPrivacy &&
        uri.path == '/home.php' &&
        uri.queryParameters['mod'] == 'spacecp' &&
        uri.queryParameters['ac'] == 'privacy') {
      if (loading || submitting) return;
      if (dirty && !await confirmDiscard()) return;
      if (!mounted) return;
      setState(() => currentUri = uri);
      await load();
      return;
    }
    if (widget.embedded &&
        uri.path == '/home.php' &&
        uri.queryParameters['mod'] == 'space' &&
        ['pm', 'notice'].contains(uri.queryParameters['do'])) {
      if (loading || submitting) return;
      if (dirty && !await confirmDiscard()) return;
      if (!mounted) return;
      setState(() => currentUri = uri);
      await load();
      return;
    }
    if (['delete', 'remove', 'logout'].contains(uri.queryParameters['op']) ||
        [
          'delete',
          'remove',
          'logout',
        ].contains(uri.queryParameters['action'])) {
      if (!await confirmAction() || !mounted) return;
    }
    if (isThreadLink(uri) ||
        boardId(uri) != null ||
        uri.queryParameters['mod'] == 'guide') {
      if (mounted) {
        await openForum(
          context,
          ForumLink(title, uri.toString()),
          widget.client,
          widget.preferences,
        );
      }
    } else if (mounted) {
      await openForumWeb(
        context,
        title,
        uri.toString(),
        client: widget.client,
        preferences: widget.preferences,
      );
    }
  }

  Future<bool> confirmAction() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认执行此操作？'),
          content: const Text('此操作会更改论坛中的数据或账号状态。'),
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
      ) ==
      true;

  Future<void> signIn() async {
    final action = document?.signAction;
    if (action == null || submitting) return;
    setState(() {
      submitting = true;
      error = null;
    });
    final session = sessionRevision.value;
    try {
      if (documentSession != await forumAuthCookie()) {
        throw const ForumFailure('账号状态已变化，请刷新后再签到。');
      }
      final result = await widget.client.submit(action, {}, method: 'GET');
      if (!mounted || session != sessionRevision.value) return;
      final response = html
          .parse(result.$1)
          .querySelector('#messagetext,.alert_error')
          ?.text
          .trim();
      if (response != null &&
          response.isNotEmpty &&
          !RegExp('成功|已签到').hasMatch(response)) {
        throw ForumFailure(response);
      }
      setState(() => submitting = false);
      await load();
      if (mounted &&
          session == sessionRevision.value &&
          error == null &&
          document?.signAction != null) {
        setState(() => error = '论坛尚未确认签到成功，请刷新核实，避免重复操作。');
      }
    } catch (e) {
      if (mounted && session == sessionRevision.value) {
        setState(() => error = '$e\n签到未自动重试。');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget nativeLinks(dom.Element element) {
    final links = element
        .querySelectorAll('a[href]')
        .where(
          (a) =>
              a.text.trim().isNotEmpty &&
              !(a.attributes['href'] ?? '').startsWith('javascript:'),
        )
        .toList();
    if (element.attributes.containsKey('data-native-navigation') &&
        !element.attributes.containsKey('data-native-pagination') &&
        links.isNotEmpty) {
      final tabs = {
        for (final a in links.where(
          (a) => !a.attributes.containsKey('data-native-action'),
        ))
          a.attributes['href']!: a,
      };
      final selected = tabs.entries
          .where(
            (e) =>
                e.value.attributes.containsKey('data-native-selected') ||
                document!.uri.resolve(e.key) == document!.uri,
          )
          .firstOrNull
          ?.key;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tabs.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  emptySelectionAllowed: true,
                  selected: {if (selected != null) selected},
                  segments: [
                    for (final tab in tabs.entries)
                      ButtonSegment(
                        value: tab.key,
                        label: Text(tab.value.text.trim()),
                      ),
                  ],
                  onSelectionChanged: submitting
                      ? null
                      : (selection) {
                          if (selection.isNotEmpty) openLink(selection.first);
                        },
                ),
              ),
            if (links.any(
              (a) => a.attributes.containsKey('data-native-action'),
            ))
              Wrap(
                spacing: 8,
                children: [
                  for (final a in links.where(
                    (a) => a.attributes.containsKey('data-native-action'),
                  ))
                    if (a.attributes.containsKey('data-native-primary'))
                      FilledButton.icon(
                        onPressed: submitting
                            ? null
                            : () => openLink(
                                a.attributes['href']!,
                                a.text.trim(),
                              ),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(a.text.trim()),
                      )
                    else
                      TextButton(
                        onPressed: submitting
                            ? null
                            : () => openLink(
                                a.attributes['href']!,
                                a.text.trim(),
                              ),
                        child: Text(a.text.trim()),
                      ),
                ],
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final anchor in element.querySelectorAll('a[href]'))
            if (anchor.text.trim().isNotEmpty &&
                !(anchor.attributes['href'] ?? '').startsWith('javascript:'))
              TextButton(
                onPressed: submitting
                    ? null
                    : () => openLink(
                        anchor.attributes['href']!,
                        anchor.text.trim(),
                      ),
                child: Text(anchor.text.trim()),
              ),
        ],
      ),
    );
  }

  Widget? nativeElement(dom.Element element) {
    if (element.attributes.containsKey('data-native-navigation')) {
      return nativeLinks(element);
    }
    if (element.attributes.containsKey('data-native-empty')) {
      return SizedBox(
        width: double.infinity,
        child: AppSectionCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(element.text.trim(), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }
    if (element.attributes.containsKey('data-native-message')) {
      if (element.attributes.containsKey('data-native-notice')) {
        final body = element.clone(true);
        for (final a in body.querySelectorAll('a[href]').toList()) {
          if (['屏蔽', '查看'].contains(a.text.trim())) a.remove();
        }
        final actions = element
            .querySelectorAll('a[href]')
            .where((a) => ['屏蔽', '查看'].contains(a.text.trim()));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(body.text.replaceAll(RegExp(r'\s+'), ' ').trim()),
                  if (actions.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (final a in actions)
                            TextButton(
                              onPressed: submitting
                                  ? null
                                  : () => openLink(
                                      a.attributes['href']!,
                                      a.text.trim(),
                                    ),
                              child: Text(a.text.trim()),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: AppSectionCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(element.text.replaceAll(RegExp(r'\s+'), ' ').trim()),
                nativeLinks(element),
              ],
            ),
          ),
        ),
      );
    }
    final children = element.children;
    if (element.localName == 'ul' &&
        children.isNotEmpty &&
        children.every(
          (e) => e.localName == 'li' && e.querySelector('em') != null,
        ) &&
        element.querySelector('input,select,textarea') == null) {
      return AppSectionCard(
        child: Column(
          children: [
            for (final item in children)
              ListTile(
                title: Text(item.querySelector('em')!.text.trim()),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item.clone(true)..querySelector('em')?.remove()).text
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim(),
                    ),
                    if (item.querySelector('a[href]') != null)
                      nativeLinks(item),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    if (element.localName == 'table' &&
        element.querySelector('form,input,select,textarea') == null) {
      final rows = element.querySelectorAll('tr');
      final headers =
          rows.firstOrNull?.querySelectorAll('th') ?? <dom.Element>[];
      if (headers.isNotEmpty &&
          rows
              .skip(1)
              .every(
                (row) =>
                    (row.children.length == headers.length &&
                        row.querySelector('[colspan]') == null) ||
                    row.querySelector('[data-native-navigation]') != null,
              )) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows.skip(1))
              if (row.children.length == headers.length &&
                  row.querySelector('[colspan]') == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppSectionCard(
                    borderRadius: 12,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < row.children.length; i++)
                            if (row.children[i].text.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child:
                                    i == 0 &&
                                        row.children[i].querySelector(
                                              'a[href]',
                                            ) !=
                                            null
                                    ? TextButton(
                                        onPressed: () => openLink(
                                          row.children[i]
                                              .querySelector('a[href]')!
                                              .attributes['href']!,
                                        ),
                                        child: Text(
                                          row.children[i].text.trim(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall,
                                        ),
                                      )
                                    : Text(
                                        i == 0
                                            ? row.children[i].text.trim()
                                            : '${headers[i].text.trim()}：${row.children[i].text.trim()}',
                                        style: i == 0
                                            ? Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                            : Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                      ),
                              ),
                          for (final cell in row.children.skip(1))
                            if (cell.querySelector('a[href]') != null)
                              nativeLinks(cell),
                        ],
                      ),
                    ),
                  ),
                ),
            for (final pagination in element.querySelectorAll(
              '[data-native-navigation]',
            ))
              nativeLinks(pagination),
          ],
        );
      }
    }
    if (element.localName == 'form') {
      return NativeForumFormView(
        form: NativeForumForm(element, document!.uri),
        busy: submitting,
        onSubmit: submit,
        onLink: openLink,
        onChanged: () {
          if (!dirty) setState(() => dirty = true);
        },
      );
    }
    if (['input', 'button', 'select', 'textarea'].contains(element.localName)) {
      return const SizedBox.shrink();
    }
    return null;
  }

  Widget contentView(dom.Element content) => HtmlWidget(
    content.outerHtml,
    key: ObjectKey(content),
    baseUrl: document!.uri,
    textStyle: Theme.of(context).textTheme.bodyMedium,
    onTapUrl: (href) async {
      await openLink(href);
      return true;
    },
    customStylesBuilder: (element) => {
      'color': 'inherit',
      'line-height': '1.45',
      if ([
        'p',
        'ul',
        'ol',
        'dl',
        'h1',
        'h2',
        'h3',
        'h4',
      ].contains(element.localName)) ...{
        'margin': '8px 0',
        'padding': '0',
      },
      if (element.localName == 'table') 'width': '100%',
      if (['h1', 'h2', 'h3', 'h4'].contains(element.localName))
        'font-size': '16px',
    },
    customWidgetBuilder: nativeElement,
  );

  Future<void> submit(
    NativeForumForm form,
    Map<String, dynamic> values,
    dom.Element? button,
  ) async {
    if (submitting) return;
    final requestRevision = sessionRevision.value;
    if (!isForumUri(form.action)) throw const ForumFailure('已阻止站外表单。');
    if ((form.element.id == 'delform' ||
            RegExp('删除|注销|退出登录').hasMatch(button?.text ?? '')) &&
        !await confirmAction()) {
      return;
    }
    if (!mounted || requestRevision != sessionRevision.value) return;
    final buttonName = button?.attributes['name'];
    if (buttonName != null && buttonName.isNotEmpty) {
      values[buttonName] = button?.attributes['value'] ?? 'yes';
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      if (documentSession != null &&
          documentSession != await forumAuthCookie()) {
        throw const ForumFailure('账号状态已变化，编辑内容已保留，请刷新表单后再提交。');
      }
      final result = await widget.client.submit(
        form.action,
        values,
        method: form.method,
      );
      if (!mounted || requestRevision != sessionRevision.value) return;
      final data = NativeForumDocument(
        result.$1,
        result.$2,
        extractMessageTabs: widget.embedded,
      );
      if (data.requiresLogin) throw const ForumFailure('会话已失效，内容已保留，请返回登录后重试。');
      if (!mounted) return;
      final success =
          RegExp(r'成功|感谢|审核|已经收藏').hasMatch(data.notice) ||
          threadId(result.$2) != null;
      if (data.notice.isNotEmpty && !success) throw ForumFailure(data.notice);
      if (!success && form.element.id == 'postform') {
        throw const ForumFailure('论坛尚未确认发布成功，请先刷新帖子核实，避免重复发送。');
      }
      if (!success &&
          form.method == 'POST' &&
          form.element.id != 'scform' &&
          data.content.querySelector('form') != null) {
        throw const ForumFailure('论坛要求检查填写内容，原输入已保留。');
      }
      if (form.element.id == 'postform' && success) {
        dirty = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data.notice.isEmpty ? '已提交' : data.notice)),
        );
        Navigator.pop(context, true);
        return;
      }
      if (form.element.id == 'delform') {
        if (!success) throw const ForumFailure('论坛尚未确认删除成功，请刷新核实。');
        submitting = false;
        await load();
        return;
      }
      setState(() => document = data);
      if (data.messageTabs.isNotEmpty ||
          (widget.embedded &&
              ['pm', 'notice'].contains(data.uri.queryParameters['do']))) {
        widget.onMessageDocument?.call(data);
      }
      if (scroll.hasClients) scroll.jumpTo(0);
      await forumAuthCookie();
    } catch (e) {
      if (mounted && requestRevision == sessionRevision.value) {
        setState(() => error = '$e\n提交未自动重试，编辑内容已保留。');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget favoritesView() {
    final data = document!;
    final items = parseFavorites(data.source, data.uri);
    final formElement = html.parse(data.source).querySelector('form#delform');
    final revision = collectionRevision;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final type in [
              ('all', '全部'),
              ('thread', '帖子'),
              ('forum', '板块'),
              ('group', '群组'),
            ])
              FilterChip(
                label: Text(type.$2),
                selected:
                    (data.uri.queryParameters['type'] ?? 'all') == type.$1,
                onSelected: submitting
                    ? null
                    : (_) => openLink(
                        'home.php?mod=space&do=favorite&type=${type.$1}',
                        '我的收藏',
                      ),
              ),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              html.parse(data.source).querySelector('#favorite_ul,.emp') != null
                  ? '暂无收藏'
                  : '未能读取收藏列表，请刷新重试。',
            ),
          ),
        for (final item in items)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (managingFavorites && formElement != null)
                Checkbox(
                  semanticLabel: '选择 ${item.link.title}',
                  value: selectedFavorites.contains(item.id),
                  onChanged: submitting
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            selectedFavorites.add(item.id);
                          } else {
                            selectedFavorites.remove(item.id);
                          }
                        }),
                ),
              Expanded(
                child: ThreadTile(
                  key: ValueKey('$revision:${item.id}'),
                  link: item.link,
                  loadSummary: threadId(forumUri(item.link.url)) == null
                      ? null
                      : (active) => widget.client.threadSummary(
                          item.link.url,
                          () =>
                              active() &&
                              mounted &&
                              revision == collectionRevision,
                        ),
                  onTap: () => openLink(item.link.url, item.link.title),
                ),
              ),
            ],
          ),
        if (managingFavorites && formElement != null && items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.delete_outline),
              label: Text('删除选中收藏（${selectedFavorites.length}）'),
              onPressed: submitting || selectedFavorites.isEmpty
                  ? null
                  : () {
                      final form = NativeForumForm(formElement, data.uri);
                      submit(
                        form,
                        form.values()
                          ..['favorite[]'] = selectedFavorites.toList(),
                        form.buttons.firstOrNull,
                      );
                    },
            ),
          ),
        for (final a in html.parse(data.source).querySelectorAll('.pg a[href]'))
          TextButton(
            onPressed: () => openLink(a.attributes['href']!, '我的收藏'),
            child: Text(a.text.trim()),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.embedded || (!dirty && !submitting),
    onPopInvokedWithResult: (didPop, _) async {
      if (widget.embedded) return;
      if (!didPop && !submitting && await confirmDiscard() && context.mounted) {
        Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: widget.embedded
          ? null
          : ReviewFrostedAppBar(
              title: Text(widget.title),
              bottom: isPrivacy && (document?.privacyTabs.isNotEmpty ?? false)
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(privacyTabHeight),
                      child: DefaultTabController(
                        key: ValueKey(currentUri.toString()),
                        length: document!.privacyTabs.length,
                        initialIndex: document!.privacyTabs
                            .indexWhere((tab) => tab.selected)
                            .clamp(0, document!.privacyTabs.length - 1),
                        child: SizedBox(
                          height: privacyTabHeight,
                          child: Builder(
                            builder: (tabContext) => TabBar(
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              tabs: [
                                for (final tab in document!.privacyTabs)
                                  Tab(text: tab.label),
                              ],
                              onTap: (index) {
                                final selected = document!.privacyTabs
                                    .indexWhere((tab) => tab.selected)
                                    .clamp(0, document!.privacyTabs.length - 1);
                                DefaultTabController.of(tabContext).index =
                                    selected;
                                if (index != selected) {
                                  openLink(document!.privacyTabs[index].url);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    )
                  : null,
              actions: [
                if (isFavorites)
                  TextButton(
                    onPressed: submitting
                        ? null
                        : () => setState(() {
                            managingFavorites = !managingFavorites;
                            selectedFavorites.clear();
                          }),
                    child: Text(managingFavorites ? '完成' : '管理收藏'),
                  ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: loading || submitting ? null : load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: SafeArea(
        top: !widget.embedded,
        bottom: !widget.embedded,
        child: ListView(
          controller: scroll,
          padding: widget.contentPadding ?? const EdgeInsets.all(16),
          children: [
            if (loading || submitting) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (document == null && !loading)
              FilledButton.tonal(
                onPressed: sessionExpired
                    ? () async {
                        if (await showForumLogin(
                              context,
                              widget.client,
                              force: true,
                            ) &&
                            mounted) {
                          await load();
                        }
                      }
                    : load,
                child: Text(sessionExpired ? '重新登录' : '重试'),
              ),
            if (document != null)
              if (isFavorites)
                favoritesView()
              else if (document!.signIn != null)
                ForumSignInView(
                  data: document!.signIn!,
                  busy: loading || submitting,
                  onSignIn: document!.signAction == null ? null : signIn,
                  onLink: openLink,
                  ranking: document!.signIn!.ranks == null
                      ? null
                      : contentView(document!.signIn!.ranks!),
                )
              else
                contentView(document!.content),
          ],
        ),
      ),
    ),
  );
}

class ForumSignInView extends StatelessWidget {
  const ForumSignInView({
    super.key,
    required this.data,
    required this.busy,
    required this.onSignIn,
    required this.onLink,
    this.ranking,
  });
  final ForumSignIn data;
  final bool busy;
  final VoidCallback? onSignIn;
  final Future<void> Function(String) onLink;
  final Widget? ranking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionCard(
          borderRadius: 16,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ForumAvatar(url: data.avatar, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (data.name.isNotEmpty)
                            Text(data.name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(data.status, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : onSignIn,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(
                    busy
                        ? '处理中…'
                        : onSignIn != null
                        ? '立即签到'
                        : RegExp('已经签到|已签到|签到成功').hasMatch(data.status)
                        ? '今日已签到'
                        : '当前不可签到',
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        MediaQuery.textScalerOf(context).scale(14) > 22 ? 1 : 2;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final stat in data.stats)
                          SizedBox(
                            width:
                                (constraints.maxWidth - (columns - 1) * 16) /
                                columns,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  stat.$1,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  stat.$2,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppSectionCard(
          borderRadius: 16,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.participants.isNotEmpty)
                  Text(
                    '今日签到 · ${data.participants}',
                    style: theme.textTheme.titleSmall,
                  ),
                for (final line in data.highlights)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(line, style: theme.textTheme.bodySmall),
                  ),
                if (data.rules != null)
                  TextButton.icon(
                    onPressed: busy ? null : () => onLink(data.rules!.url),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('奖励规则'),
                  ),
              ],
            ),
          ),
        ),
        if (ranking != null) ...[
          const SizedBox(height: 20),
          Text('签到排行', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ranking!,
        ],
      ],
    );
  }
}

class _ReplyLinkDialog extends StatefulWidget {
  const _ReplyLinkDialog({required this.image});
  final bool image;
  @override
  State<_ReplyLinkDialog> createState() => _ReplyLinkDialogState();
}

class _ReplyLinkDialogState extends State<_ReplyLinkDialog> {
  final url = TextEditingController(), label = TextEditingController();
  String? error;
  @override
  void dispose() {
    url.dispose();
    label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.image ? '插入网络图片' : '插入链接'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: 'HTTPS 地址', errorText: error),
        ),
        if (!widget.image)
          TextField(
            controller: label,
            decoration: const InputDecoration(labelText: '显示文字（可选）'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          final uri = Uri.tryParse(url.text.trim());
          if (uri == null ||
              uri.scheme != 'https' ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            setState(() => error = '请输入有效的 HTTPS 地址');
            return;
          }
          Navigator.pop(context, (uri.toString(), label.text.trim()));
        },
        child: const Text('插入'),
      ),
    ],
  );
}

class NativeForumFormView extends StatefulWidget {
  const NativeForumFormView({
    super.key,
    required this.form,
    required this.busy,
    required this.onSubmit,
    this.onChanged,
    this.onLink,
    this.compactReply = false,
    this.onCollapse,
    this.replyFocus,
  });
  final NativeForumForm form;
  final bool busy;
  final VoidCallback? onChanged;
  final Future<void> Function(String)? onLink;
  final bool compactReply;
  final VoidCallback? onCollapse;
  final FocusNode? replyFocus;
  final Future<void> Function(
    NativeForumForm,
    Map<String, dynamic>,
    dom.Element?,
  )
  onSubmit;
  @override
  State<NativeForumFormView> createState() => _NativeForumFormViewState();
}

class _NativeForumFormViewState extends State<NativeForumFormView> {
  final key = GlobalKey<FormState>();
  late final values = widget.form.values();
  final controllers = <String, TextEditingController>{};
  String quote = '';
  bool get isReply =>
      widget.form.element.id == 'postform' &&
      widget.form.base.queryParameters['action'] == 'reply';
  @override
  void initState() {
    super.initState();
    if (isReply) {
      final match = RegExp(
        r'^\s*(\[quote\][\s\S]*?\[/quote\])\s*',
        caseSensitive: false,
      ).firstMatch(values['message']?.toString() ?? '');
      if (match != null) {
        quote = match.group(1)!;
        values['message'] = values['message'].toString().substring(match.end);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> send(dom.Element button) async {
    if (widget.busy || !key.currentState!.validate()) return;
    if (!widget.compactReply) FocusScope.of(context).unfocus();
    final data = Map<String, dynamic>.from(values);
    for (final entry in controllers.entries) {
      data[entry.key] = entry.value.text;
    }
    if (quote.isNotEmpty) data['message'] = '$quote\n${data['message'] ?? ''}';
    await widget.onSubmit(widget.form, data, button);
  }

  TextEditingController get message => controllers.putIfAbsent(
    'message',
    () => TextEditingController(text: values['message']?.toString() ?? ''),
  );

  dom.Element? get replyButton => widget.form.buttons
      .where(
        (e) => e.attributes['name'] == 'replysubmit' || e.id == 'postsubmit',
      )
      .firstOrNull;
  List<dom.Element> get replyExtras => widget.form.fields
      .where(
        (e) =>
            !['message', 'subject'].contains(e.attributes['name']) &&
            ![
              'hidden',
              'submit',
              'button',
              'reset',
            ].contains(e.attributes['type']),
      )
      .toList();

  void insert(String start, [String end = '']) {
    final controller = message;
    final selection = controller.selection;
    final from = selection.isValid ? selection.start : controller.text.length;
    final to = selection.isValid ? selection.end : controller.text.length;
    final text = end.isEmpty ? '' : controller.text.substring(from, to);
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(from, to, '$start$text$end'),
      selection: TextSelection.collapsed(
        offset: from + start.length + text.length,
      ),
    );
    widget.onChanged?.call();
    widget.replyFocus?.requestFocus();
  }

  Future<void> insertLink({bool image = false}) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _ReplyLinkDialog(image: image),
    );
    if (result == null || !mounted) return;
    insert(
      image
          ? '[img]${result.$1}[/img]'
          : '[url=${result.$1}]${result.$2.isEmpty ? result.$1 : result.$2}[/url]',
    );
  }

  Future<void> emoji() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            children: [
              for (final item in [
                '😀',
                '😊',
                '😂',
                '🤔',
                '👍',
                '👏',
                '🙏',
                '🎉',
                '❤️',
                '🔥',
                '🚀',
                '👀',
              ])
                TextButton(
                  onPressed: () => Navigator.pop(context, item),
                  child: Text(item, style: const TextStyle(fontSize: 24)),
                ),
            ],
          ),
        ),
      ),
    );
    if (mounted && value != null) insert(value);
  }

  Widget compactEditor() => Form(
    key: key,
    onChanged: widget.onChanged,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final action in <(String, IconData, VoidCallback)>[
                      ('表情', Icons.sentiment_satisfied_outlined, emoji),
                      ('加粗', Icons.format_bold, () => insert('[b]', '[/b]')),
                      ('链接', Icons.link, () => insertLink()),
                      (
                        '引用',
                        Icons.format_quote,
                        () => insert('[quote]', '[/quote]'),
                      ),
                      ('代码', Icons.code, () => insert('[code]', '[/code]')),
                      (
                        '网络图片',
                        Icons.image_outlined,
                        () => insertLink(image: true),
                      ),
                    ])
                      IconButton(
                        tooltip: action.$1,
                        onPressed: widget.busy ? null : action.$3,
                        icon: Icon(action.$2),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '收起编辑栏',
              onPressed: widget.busy ? null : widget.onCollapse,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
        if (quote.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Text(
                  quote.replaceAll(RegExp(r'\[[^\]]+\]'), '').trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: '移除引用',
                onPressed: widget.busy
                    ? null
                    : () {
                        widget.onChanged?.call();
                        setState(() => quote = '');
                      },
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextFormField(
                controller: message,
                focusNode: widget.replyFocus,
                enabled: !widget.busy,
                minLines: 1,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: '说点什么吧…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                ),
                validator: (text) =>
                    (text ?? '').trim().isEmpty ? '请填写回复内容' : null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送回复',
              onPressed: widget.busy || replyButton == null
                  ? null
                  : () => send(replyButton!),
              icon: widget.busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
        for (final item in replyExtras.where(
          (e) => e.attributes['type'] != 'checkbox',
        ))
          Padding(padding: const EdgeInsets.only(top: 8), child: field(item)),
        if (replyExtras.any((e) => e.attributes['type'] == 'checkbox'))
          ExpansionTile(
            title: const Text('更多选项'),
            tilePadding: EdgeInsets.zero,
            children: [
              for (final item in replyExtras.where(
                (e) => e.attributes['type'] == 'checkbox',
              ))
                field(item),
            ],
          ),
      ],
    ),
  );

  Widget field(dom.Element field) {
    final name = field.attributes['name'] ?? '';
    final type = field.attributes['type'] ?? field.localName;
    // shortcut: plugin uploads need their own native protocol adapter before enabling file fields.
    if (type == 'file') return const Text('此附件上传方式暂未适配。');
    if (name.isEmpty ||
        ['hidden', 'submit', 'reset', 'button', 'file'].contains(type) ||
        field.attributes.containsKey('disabled')) {
      return const SizedBox.shrink();
    }
    final label = widget.form.label(field);
    if (type == 'checkbox') {
      final value = field.attributes['value'] ?? 'on';
      final group =
          widget.form.fields
              .where(
                (e) =>
                    e.attributes['name'] == name &&
                    e.attributes['type'] == 'checkbox',
              )
              .length >
          1;
      final selected = values[name] is List
          ? (values[name] as List).contains(value)
          : values[name] == value;
      return CheckboxListTile(
        dense: widget.form.base.queryParameters['ac'] == 'privacy',
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: selected,
        onChanged: widget.busy
            ? null
            : (checked) => setState(() {
                widget.onChanged?.call();
                if (group) {
                  final current = values[name];
                  final selected = current is List
                      ? [...current]
                      : [if (current != null) current];
                  if (checked == true) {
                    if (!selected.contains(value)) selected.add(value);
                  } else {
                    selected.remove(value);
                  }
                  if (selected.isEmpty) {
                    values.remove(name);
                  } else {
                    values[name] = selected;
                  }
                  return;
                }
                if (checked == true) {
                  values[name] = value;
                } else {
                  values.remove(name);
                }
              }),
      );
    }
    if (type == 'radio') {
      return RadioGroup<String>(
        groupValue: values[name]?.toString(),
        onChanged: (value) {
          if (!widget.busy) setState(() => values[name] = value);
        },
        child: RadioListTile<String>(
          title: Text(field.parent?.text.trim() ?? label),
          value: field.attributes['value'] ?? '',
          enabled: !widget.busy,
        ),
      );
    }
    if (field.localName == 'select') {
      final options = <String, String>{
        for (final o in field.querySelectorAll('option'))
          o.attributes['value'] ?? o.text: o.text.trim(),
      };
      return DropdownButtonFormField<String>(
        initialValue: options.containsKey(values[name])
            ? values[name]
            : options.keys.firstOrNull,
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        items: [
          for (final option in options.entries)
            DropdownMenuItem(
              value: option.key,
              child: Text(option.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: widget.busy ? null : (value) => values[name] = value,
      );
    }
    final controller = controllers.putIfAbsent(
      name,
      () => TextEditingController(text: values[name]?.toString() ?? ''),
    );
    return TextFormField(
      controller: controller,
      enabled: !widget.busy,
      readOnly: field.attributes.containsKey('readonly'),
      obscureText: type == 'password',
      minLines: field.localName == 'textarea' ? (name == 'message' ? 5 : 3) : 1,
      maxLines: field.localName == 'textarea' ? null : 1,
      maxLength: int.tryParse(field.attributes['maxlength'] ?? ''),
      keyboardType: field.localName == 'textarea'
          ? TextInputType.multiline
          : type == 'email'
          ? TextInputType.emailAddress
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
      validator: (value) =>
          (field.attributes.containsKey('required') ||
                  ['message', 'srchtxt'].contains(name) ||
                  (name == 'subject' &&
                      widget.form.base.queryParameters['action'] ==
                          'newthread')) &&
              (value ?? '').trim().isEmpty
          ? '请填写$label'
          : null,
    );
  }

  Widget privacyEditor() {
    final tables = widget.form.element.querySelectorAll('table');
    final tableFields = tables
        .expand((table) => table.querySelectorAll('input,textarea,select'))
        .toSet();
    final tableButtons = tables
        .expand(
          (table) => table.querySelectorAll(
            'button[type="submit"],input[type="submit"],button:not([type])',
          ),
        )
        .toSet();
    bool insideLabel(dom.Element element) {
      for (
        var parent = element.parent;
        parent != null && parent != widget.form.element;
        parent = parent.parent
      ) {
        if (parent.localName == 'label') return true;
      }
      return false;
    }

    Widget saveButton(dom.Element button) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FilledButton(
        onPressed: widget.busy ? null : () => send(button),
        child: Text(
          button.text.trim().isNotEmpty
              ? button.text.trim()
              : button.attributes['value'] ?? '保存',
        ),
      ),
    );
    return Form(
      key: key,
      onChanged: widget.onChanged,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final table in tables)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppSectionCard(
                borderRadius: 16,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (table.querySelector('caption h2,caption h3')
                          case final heading?)
                        Text(
                          heading.text.trim(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      if (table.querySelector('caption p')
                          case final description?)
                        Padding(
                          padding: const EdgeInsets.only(top: 6, bottom: 8),
                          child: Text(
                            description.text.trim(),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      for (final item in table.querySelectorAll(
                        'input,textarea,select',
                      ))
                        field(item),
                      if (table.querySelector(
                            'input:not([type="hidden"]),textarea,select',
                          ) ==
                          null)
                        Text(
                          (table.clone(true)
                                ..querySelector('caption')?.remove())
                              .text
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim(),
                        ),
                      for (final button in widget.form.buttons.where(
                        (button) =>
                            tableButtons.contains(button) &&
                            table
                                .querySelectorAll('button,input[type="submit"]')
                                .contains(button),
                      ))
                        saveButton(button),
                    ],
                  ),
                ),
              ),
            ),
          for (final item in widget.form.fields.where(
            (item) => !tableFields.contains(item),
          ))
            field(item),
          for (final link
              in widget.form.element
                  .querySelectorAll('a[href]')
                  .where(
                    (link) =>
                        !insideLabel(link) &&
                        link.text.trim().isNotEmpty &&
                        !(link.attributes['href'] ?? '').startsWith(
                          'javascript:',
                        ),
                  ))
            TextButton(
              onPressed: widget.busy || widget.onLink == null
                  ? null
                  : () => widget.onLink!(link.attributes['href']!),
              child: Text(link.text.trim()),
            ),
          for (final button in widget.form.buttons.where(
            (button) => !tableButtons.contains(button),
          ))
            saveButton(button),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.compactReply
      ? compactEditor()
      : widget.form.base.queryParameters['ac'] == 'privacy' &&
            widget.form.element.querySelector('table') != null
      ? privacyEditor()
      : AppSectionCard(
          borderRadius: 16,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: key,
              onChanged: widget.onChanged,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.form.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  if (quote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(context).colorScheme.outline,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(child: Text('引用内容')),
                                  IconButton(
                                    tooltip: '移除引用',
                                    onPressed: widget.busy
                                        ? null
                                        : () {
                                            widget.onChanged?.call();
                                            setState(() => quote = '');
                                          },
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                                ],
                              ),
                              Text(
                                quote
                                    .replaceAll(RegExp(r'\[[^\]]+\]'), '')
                                    .trim(),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  for (final item in widget.form.fields.where(
                    (e) =>
                        ![
                          'hidden',
                          'submit',
                          'button',
                          'reset',
                        ].contains(e.attributes['type']) &&
                        (!isReply || e.attributes['name'] != 'subject'),
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: field(item),
                    ),
                  for (final link
                      in widget.form.element
                          .querySelectorAll('a[href]')
                          .where(
                            (e) =>
                                widget.form.base.queryParameters['ac'] !=
                                    'privacy' &&
                                !(e.attributes['href'] ?? '').startsWith(
                                  'javascript:',
                                ) &&
                                e.text.trim().isNotEmpty,
                          ))
                    TextButton(
                      onPressed: widget.busy || widget.onLink == null
                          ? null
                          : () => widget.onLink!(link.attributes['href']!),
                      child: Text(link.text.trim()),
                    ),
                  for (final button in widget.form.buttons)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton(
                        onPressed: widget.busy ? null : () => send(button),
                        child: Text(
                          button.attributes['name'] == 'replysubmit'
                              ? '发送回复'
                              : button.text.trim().isNotEmpty
                              ? button.text.trim()
                              : button.attributes['value'] ?? '提交',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
}
