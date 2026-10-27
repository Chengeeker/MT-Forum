import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'forum.dart';

class ForumAccount {
  ForumAccount(this.name, this.uid, this.fields, {this.avatar});
  final String name, uid;
  final String? avatar;
  final List<(String, String)> fields;

  factory ForumAccount.parse(String source) {
    final doc = html.parse(source);
    if (doc.querySelector('form[id^="loginform_"]') != null) {
      throw const ForumFailure('登录会话已失效，请退出后重新登录。');
    }
    final heading = doc.querySelector('#ct h2');
    final uid =
        RegExp(r'UID:\s*(\d+)').firstMatch(heading?.text ?? '')?.group(1) ?? '';
    final name =
        (doc.querySelector('#uhd h2')?.text ??
                heading?.nodes.firstOrNull?.text ??
                '')
            .trim();
    final fields = <(String, String)>[];
    for (final item in doc.querySelectorAll('#ct li')) {
      final label = item.querySelector('em')?.text.trim() ?? '';
      if (label.isEmpty || label.contains('IP')) continue;
      final value = item.clone(true);
      value.querySelector('em')?.remove();
      final text = value.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isNotEmpty) fields.add((label, text));
    }
    if (name.isEmpty || uid.isEmpty || fields.isEmpty) {
      throw const ForumFailure('未能读取账号资料，请刷新重试。仍可使用退出登录重新验证账号。');
    }
    final image = forumUri(
      doc.querySelector('#uhd img')?.attributes['src'] ?? '',
    );
    return ForumAccount(
      name,
      uid,
      fields,
      avatar:
          image.scheme == 'https' &&
              (image.host == 'cdn.binmt.cc' || isForumUri(image)) &&
              image.path != '/'
          ? image.toString()
          : null,
    );
  }
}

Uri registrationUriFromHtml(String source) {
  for (final anchor in html.parse(source).querySelectorAll('a[href]')) {
    final uri = forumUri(anchor.attributes['href']!);
    if (isForumUri(uri) &&
        uri.path == '/member.php' &&
        RegExp(r'^register\d*$').hasMatch(uri.queryParameters['mod'] ?? '')) {
      return uri;
    }
  }
  throw const ForumFailure('官网没有返回有效注册入口，请稍后重试。');
}

class NativeForumForm {
  NativeForumForm(this.element, this.base);
  final Element element;
  final Uri base;
  Uri get action =>
      base.resolve(element.attributes['action'] ?? base.toString());
  String get method => (element.attributes['method'] ?? 'GET').toUpperCase();
  List<Element> get fields => element.querySelectorAll('input,textarea,select');
  List<Element> get buttons => element.querySelectorAll(
    'button[type="submit"],input[type="submit"],button:not([type])',
  );
  String get title => element.id == 'postform'
      ? (base.queryParameters['action'] == 'reply' ? '回复内容' : '发布帖子')
      : base.queryParameters['ac'] == 'pm'
      ? '发送消息'
      : base.queryParameters['do'] == 'pm'
      ? '管理消息'
      : element.id == 'scform'
      ? '搜索论坛'
      : base.queryParameters['ac'] == 'privacy'
      ? (element
                    .querySelector('caption h2,caption h3,legend')
                    ?.text
                    .trim()
                    .isNotEmpty ==
                true
            ? element.querySelector('caption h2,caption h3,legend')!.text.trim()
            : '筛选设置')
      : '填写信息';
  Map<String, dynamic> values() {
    final result = <String, dynamic>{};
    for (final field in fields) {
      final name = field.attributes['name'];
      if (name == null ||
          name.isEmpty ||
          field.attributes.containsKey('disabled')) {
        continue;
      }
      final type = field.attributes['type'] ?? field.localName;
      if (['file', 'submit', 'button', 'reset'].contains(type)) continue;
      if (['checkbox', 'radio'].contains(type) &&
          !field.attributes.containsKey('checked')) {
        continue;
      }
      final value = field.localName == 'textarea'
          ? field.text
          : field.localName == 'select'
          ? (field.querySelector('option[selected]') ??
                        field.querySelector('option'))
                    ?.attributes['value'] ??
                ''
          : field.attributes['value'] ??
                (['checkbox', 'radio'].contains(type) ? 'on' : '');
      if (result.containsKey(name)) {
        final previous = result[name];
        result[name] = previous is List
            ? [...previous, value]
            : [previous, value];
      } else {
        result[name] = value;
      }
    }
    // The native editor supplies BBCode text, never the website's rich-text HTML.
    if (element.id == 'postform') result['wysiwyg'] = '0';
    return result;
  }

  String label(Element field) {
    final name = field.attributes['name'] ?? '';
    const known = {
      'subject': '标题',
      'message': '内容',
      'description': '收藏备注',
      'srchtxt': '关键词',
      'username': '用户名',
      'password': '密码',
      'password2': '确认密码',
      'email': '邮箱',
      'seccodeverify': '验证码',
      'secanswer': '验证答案',
      'tousername': '收件人',
      'touid': '收件人',
      'typeid': '帖子分类',
      'questionid': '安全提问',
      'answer': '安全提问答案',
      'usesig': '使用个人签名',
      'agreebbrule': '我已阅读并同意论坛注册协议',
      'invitecode': '邀请码',
    };
    if (known.containsKey(name)) return known[name]!;
    if (name.startsWith('deletepm_')) {
      for (
        Element? node = field.parent;
        node != null && node != element;
        node = node.parent
      ) {
        if (node.localName == 'dl') {
          final summary = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (summary.isNotEmpty) return summary;
        }
      }
      return '选择消息';
    }
    final id = field.id;
    final label = id.isEmpty
        ? null
        : element
              .querySelectorAll('label')
              .where((e) => e.attributes['for'] == id)
              .firstOrNull;
    final enclosingLabel = field.parent?.localName == 'label'
        ? field.parent?.text.replaceAll(RegExp(r'\s+'), ' ').trim()
        : null;
    Element? row = field.parent;
    while (row != null && row != element && row.localName != 'tr') {
      row = row.parent;
    }
    final rowLabel =
        base.queryParameters['ac'] == 'privacy' && row?.localName == 'tr'
        ? row?.querySelector('th')?.text.trim()
        : null;
    return (label?.text.trim().isNotEmpty == true
            ? label!.text.trim()
            : enclosingLabel?.isNotEmpty == true
            ? enclosingLabel
            : rowLabel?.isNotEmpty == true
            ? rowLabel
            : null) ??
        field.attributes['placeholder'] ??
        field.attributes['title'] ??
        (name.isEmpty ? '选项' : name);
  }
}

class ForumSignIn {
  ForumSignIn(Element content, Uri base) {
    String text(Element? node) =>
        node?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    status = text(content.querySelector('.paiming .font'));
    name = text(content.querySelector('.qdright .user .author'));
    final image = content
        .querySelector('.qdright .user img')
        ?.attributes['src'];
    final imageUri = image == null ? null : base.resolve(image);
    avatar =
        imageUri != null &&
            imageUri.scheme == 'https' &&
            (isForumUri(imageUri) || imageUri.host == 'cdn.binmt.cc')
        ? imageUri.toString()
        : null;
    stats = content
        .querySelectorAll('.countqian li')
        .map((item) {
          final label = text(item.querySelector('h4'));
          final value = text(item.querySelector('p'))
              .replaceAll(RegExp(r'\s+'), '');
          return (label, value);
        })
        .where((item) => item.$1.isNotEmpty && item.$2.isNotEmpty)
        .toList();
    participants = text(content.querySelector('.weather_p .con'));
    highlights = content
        .querySelectorAll('#pt .xg1')
        .where((e) => e.querySelector('a') == null)
        .map(text)
        .where((e) => e.isNotEmpty)
        .toList();
    final rule = content.querySelector('a[href*="operation=rewardrule"]');
    final target = rule == null
        ? null
        : base.resolve(rule.attributes['href'] ?? '');
    rules = target != null && isForumUri(target)
        ? ForumLink('奖励规则', target.toString())
        : null;
    ranks = content.querySelector('#ranklist')?.clone(true);
    if (status.isEmpty || stats.isEmpty) {
      throw const ForumFailure('未能读取签到状态和统计，请刷新重试。');
    }
  }
  late final String status, name, participants;
  late final String? avatar;
  late final List<(String, String)> stats;
  late final List<String> highlights;
  late final ForumLink? rules;
  Element? ranks;
}

class ForumFavorite {
  ForumFavorite(this.id, this.link);
  final String id;
  final ForumLink link;
}

List<ForumFavorite> parseFavorites(String source, Uri base) {
  final result = <ForumFavorite>[];
  for (final item in html.parse(source).querySelectorAll('#favorite_ul > li')) {
    final id = item
        .querySelector('input[name="favorite[]"]')
        ?.attributes['value'];
    for (final a in item.querySelectorAll('a[href]')) {
      final uri = base.resolve(a.attributes['href']!);
      if (!isForumUri(uri) || (threadId(uri) == null && boardId(uri) == null)) {
        continue;
      }
      if (id != null && a.text.trim().isNotEmpty) {
        result.add(ForumFavorite(id, ForumLink(a.text.trim(), uri.toString())));
        break;
      }
    }
  }
  return result;
}

class ForumMessageTab {
  const ForumMessageTab({
    required this.label,
    required this.url,
    required this.selected,
  });

  final String label;
  final String url;
  final bool selected;
}

class NativeForumDocument {
  NativeForumDocument(
    this.source,
    this.uri, {
    this.extractMessageTabs = false,
  }) {
    final document = html.parse(source);
    requiresLogin = document.querySelector('form[id^="loginform_"]') != null;
    title =
        document.querySelector('h1')?.text.trim() ??
        document.querySelector('title')?.text.trim() ??
        'MT论坛';
    if (title.contains('403') ||
        source.contains('Sorry, you have been blocked')) {
      throw const ForumFailure('论坛拒绝访问，请检查中国大陆网络后重试。');
    }
    notice =
        document
            .querySelector('#messagetext,.alert_error,.alert_info')
            ?.text
            .trim() ??
        '';
    final root =
        document.querySelector('#postform')?.parent ??
        document.querySelector('#ct .mn') ??
        document.querySelector('#ct') ??
        document.querySelector('#wp') ??
        document.body;
    content = root?.clone(true) ?? Element.tag('div');
    messageTabs = extractMessageTabs ? _messageTabs(document) : const [];
    privacyTabs = _privacyTabs(document);
    if (privacyTabs.isNotEmpty) content.querySelector('.tb')?.remove();
    if (uri.path == '/home.php' &&
        ['pm', 'notice'].contains(uri.queryParameters['do'])) {
      final navigation = extractMessageTabs
          ? null
          : document.querySelector('#ct .appl .tbn ul')?.clone(true);
      if (navigation != null) {
        navigation.attributes['data-native-navigation'] = 'true';
        content.nodes.insert(0, navigation);
      }
      if (extractMessageTabs) {
        final tabs = content.querySelector('.tb');
        if (tabs != null) {
          for (final item in tabs.children.toList()) {
            if (!item.classes.any(['o', 'y'].contains)) item.remove();
          }
          if (tabs.querySelector('a[href]') == null) tabs.remove();
        }
      }
    }
    const digits = {
      'zero': '0',
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
    };
    for (final span in content.querySelectorAll('.pics span')) {
      if (span.text.isEmpty) {
        span.text = span.classes
            .map((c) => digits[c])
            .whereType<String>()
            .join();
      }
    }
    final sign = content.querySelector('#JD_sign');
    final signHref = sign?.attributes['href'];
    if (signHref != null) {
      final target = uri.resolve(signHref);
      if (isForumUri(target) &&
          target.queryParameters['operation'] == 'qiandao') {
        signAction = target;
      }
      sign?.remove();
    }
    // Only translate the site's read-only ajax navigation, never execute page scripts.
    for (final anchor in content.querySelectorAll('a[onclick]')) {
      final match = RegExp("ajaxget\\('([^']+)'\\s*,\\s*'ranklist'\\)")
          .firstMatch(anchor.attributes['onclick'] ?? '');
      if (match != null) {
        final target = uri.resolve(match.group(1)!);
        if (isForumUri(target) &&
            target.queryParameters['operation'] == 'list') {
          anchor.attributes['href'] = target.toString();
        }
      }
    }
    if (content.querySelector('.lineB .paiming') != null) {
      signIn = ForumSignIn(content, uri);
    }
    for (final node in content.querySelectorAll('#pt,#hd,#ft,.appl,.sd')) {
      node.remove();
    }
    for (final node in content.querySelectorAll('.tb,.tbmu,.pg,.paihang')) {
      if (node.classes.contains('tbmu') &&
          node.querySelector('a[href]') == null) {
        continue;
      }
      if (node.querySelector('input:not([type="hidden"]),select,textarea') ==
          null) {
        node.attributes['data-native-navigation'] = 'true';
        if (node.classes.contains('pg')) {
          node.attributes['data-native-pagination'] = 'true';
        }
      }
    }
    for (final anchor in content.querySelectorAll(
      '[data-native-navigation] a[href]',
    )) {
      if (anchor.parent?.classes.any(['a', 'active'].contains) == true) {
        anchor.attributes['data-native-selected'] = 'true';
      }
      if (anchor.parent?.classes.any(['o', 'y'].contains) == true) {
        anchor.attributes['data-native-action'] = 'true';
        if (anchor.parent?.classes.contains('o') == true) {
          anchor.attributes['data-native-primary'] = 'true';
        }
      }
    }
    for (final node in content.querySelectorAll('.emp')) {
      node.attributes['data-native-empty'] = 'true';
    }
    for (final node in content.querySelectorAll('.nts dl,.pml dl')) {
      node.attributes['data-native-message'] = 'true';
      if (uri.queryParameters['do'] == 'notice') {
        node.attributes['data-native-notice'] = 'true';
      }
    }
    for (final node in content.querySelectorAll('h1.mt,h2.mt')) {
      node.remove();
    }
    if (uri.path == '/search.php') {
      final results = document.querySelector('#threadlist');
      if (results != null) content = results.clone(true);
    }
    for (final node in content.querySelectorAll(
      'script,style,iframe,object,embed,link,meta,#hd,#ft,.appl,.sd,#e_controls,#e_menus,#e_bbar,.p_pof,.p_pop,[id^="imgattachform"],[id^="attachform"]',
    )) {
      node.remove();
    }
    for (final node in [content, ...content.querySelectorAll('*')]) {
      for (final attr in node.attributes.keys.toList()) {
        if (attr.toString().startsWith('on') ||
            [
              'style',
              'width',
              'height',
              'bgcolor',
              'align',
              'class',
            ].contains(attr)) {
          node.attributes.remove(attr);
        }
      }
    }
    if (signIn != null) {
      signIn!.ranks = content.querySelector('#ranklist')?.clone(true);
    }
    final seen = <String>{};
    if (content.text.trim().isEmpty && notice.isNotEmpty) {
      content = Element.tag('p')..text = notice;
    }
    if (content.text.trim().isEmpty &&
        notice.isEmpty &&
        signAction == null &&
        content.querySelector(
              'form input:not([type="hidden"]),form textarea,form select,img[src]',
            ) ==
            null) {
      throw const ForumFailure('页面没有可显示的内容，请刷新重试。');
    }
    links = content
        .querySelectorAll('a[href]')
        .map((a) {
          final href = a.attributes['href'] ?? '';
          if (href.startsWith('javascript:') || href.startsWith('#')) {
            return null;
          }
          final target = uri.resolve(href);
          final label = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (label.isEmpty || !seen.add(target.toString())) return null;
          return ForumLink(label, target.toString());
        })
        .whereType<ForumLink>()
        .toList();
  }
  final String source;
  final Uri uri;
  final bool extractMessageTabs;
  late final List<ForumMessageTab> messageTabs;
  late final List<ForumMessageTab> privacyTabs;
  late final bool requiresLogin;
  late final String title, notice;
  late Element content;
  late final List<ForumLink> links;
  Uri? signAction;
  ForumSignIn? signIn;

  List<ForumMessageTab> _privacyTabs(Document document) {
    if (uri.queryParameters['mod'] != 'spacecp' ||
        uri.queryParameters['ac'] != 'privacy') {
      return const [];
    }
    final tabs = <ForumMessageTab>[];
    for (final item in document.querySelectorAll('.tb > li')) {
      final a = item.querySelector('a[href]');
      if (a == null) continue;
      final target = uri.resolve(a.attributes['href']!);
      if (!isForumUri(target) ||
          target.path != '/home.php' ||
          target.queryParameters['mod'] != 'spacecp' ||
          target.queryParameters['ac'] != 'privacy') {
        continue;
      }
      final label = a.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (label.isEmpty) continue;
      tabs.add(
        ForumMessageTab(
          label: label,
          url: target.toString(),
          selected: item.classes.any(['a', 'active'].contains) || target == uri,
        ),
      );
    }
    return tabs;
  }

  List<ForumMessageTab> _messageTabs(Document document) {
    final tabs = <ForumMessageTab>[];
    for (final item in document.querySelectorAll('#ct .mn > .tb > li')) {
      if (item.classes.any(['o', 'y'].contains)) continue;
      final anchor = item.querySelector('a[href]');
      if (anchor == null) continue;
      final target = uri.resolve(anchor.attributes['href']!);
      final label = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!isForumUri(target) ||
          target.path != uri.path ||
          target.queryParameters['mod'] != 'space' ||
          target.queryParameters['do'] != uri.queryParameters['do'] ||
          (uri.queryParameters['do'] == 'notice' &&
              target.queryParameters['view'] != uri.queryParameters['view']) ||
          label.isEmpty) {
        continue;
      }
      tabs.add(
        ForumMessageTab(
          label: label,
          url: target.toString(),
          selected: item.classes.any(['a', 'active'].contains) || target == uri,
        ),
      );
    }
    return tabs;
  }
}
