import 'package:html/parser.dart' as html;

import 'forum.dart';
import 'native_forum.dart';
import '../pages/web_page.dart';

Future<ForumAccount?> validateForumAccount(ForumClient client) async {
  final revision = sessionRevision.value;
  final cookie = await forumAuthCookie();
  if (cookie.isEmpty) return null;
  final source = await client
      .source(
        forumUri('home.php')
            .replace(
              queryParameters: {
                'mod': 'space',
                'do': 'profile',
                '_check': DateTime.now().microsecondsSinceEpoch.toString(),
              },
            )
            .toString(),
      )
      .timeout(const Duration(seconds: 15));
  final currentCookie = await forumAuthCookie();
  if (revision != sessionRevision.value || cookie != currentCookie) {
    throw const ForumFailure('账号已变化，请重新检测。');
  }
  final doc = html.parse(source);
  if (doc.querySelector(
        'form[id^="loginform"] input[type="password"], form[action*="logging"] input[type="password"]',
      ) !=
      null) {
    return null;
  }
  return ForumAccount.parse(source, requireDetails: false);
}
