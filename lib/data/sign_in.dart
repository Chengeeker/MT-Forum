import 'package:html/parser.dart' as html;

import 'forum.dart';
import 'native_forum.dart';

final _signInRequests = Expando<Future<NativeForumDocument>>();

/// Share the full check/write/confirmation transaction with manual sign-in.
Future<NativeForumDocument> signInIfNeeded(
  ForumClient client, {
  required Future<bool> Function() canSubmit,
}) {
  final pending = _signInRequests[client];
  if (pending != null) return pending;
  late final Future<NativeForumDocument> job;
  job =
      () async {
        final uri = forumUri('k_misign-sign.html');
        Future<NativeForumDocument> read() async =>
            NativeForumDocument(await client.source(uri.toString()), uri);
        final current = await read();
        if (current.requiresLogin) throw const ForumFailure('请先登录论坛账号。');
        if (current.signIn?.signedIn == true) return current;
        final action = current.signAction;
        if (current.signIn == null ||
            action == null ||
            !isForumUri(action) ||
            action.path != '/plugin.php' ||
            action.queryParameters['id'] != 'k_misign:sign' ||
            action.queryParameters['operation'] != 'qiandao' ||
            (action.queryParameters['formhash'] ?? '').isEmpty) {
          throw const ForumFailure('未能确认可用的签到操作，请手动刷新签到页。');
        }
        if (!await canSubmit()) {
          throw const ForumFailure('签到已取消或账号状态已变化。');
        }
        final result = await client.submit(action, {}, method: 'GET');
        final message = html
            .parse(result.$1)
            .querySelector('#messagetext,.alert_error')
            ?.text
            .trim();
        if (message != null &&
            message.isNotEmpty &&
            !RegExp('成功|已签到').hasMatch(message)) {
          throw ForumFailure(message);
        }
        if (!await canSubmit()) {
          throw const ForumFailure('账号状态已变化。');
        }
        final confirmed = await read();
        if (confirmed.signIn?.signedIn != true) {
          throw const ForumFailure('论坛尚未确认签到成功，请刷新核实，避免重复操作。');
        }
        return confirmed;
      }().whenComplete(() {
        if (identical(_signInRequests[client], job)) {
          _signInRequests[client] = null;
        }
      });
  _signInRequests[client] = job;
  return job;
}
