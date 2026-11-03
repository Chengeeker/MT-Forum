import 'dart:convert';

import 'forum.dart';
import 'native_forum.dart';
import 'preferences.dart';
import 'webdav_service.dart';

class ForumBackupService {
  ForumBackupService(this.preferences, this.client);
  final Preferences preferences;
  final ForumClient client;
  static const boolKeys = {
    'pureBlack',
    'dynamicColor',
    'floatingNavigation',
    'liquidGlass',
    'haptics',
    'autoSignIn',
  };
  static const intKeys = {'themeMode', 'color', 'fontWeightAdjustment'};
  static const stringKeys = {
    'history',
    'webdav_url',
    'webdav_username',
    'webdav_directory',
  };
  static const allowedKeys = {
    ...boolKeys,
    ...intKeys,
    ...stringKeys,
    'textScale',
  };

  Future<String> _cookies() async =>
      await ForumClient.platform.invokeMethod<String>(
        'cookies',
        '$forumOrigin/',
      ) ??
      '';
  String _auth(String cookie) => cookie
      .split(';')
      .map((e) => e.trim())
      .where(
        (e) =>
            e.split('=').first.endsWith('_auth') &&
            e.indexOf('=') < e.length - 1,
      )
      .join(';');

  Future<Map<String, dynamic>> exportAllData({
    bool includeCredentials = false,
  }) async {
    final values = <String, dynamic>{};
    for (final key in {
      ...allowedKeys,
      if (includeCredentials) 'webdav_password',
    }) {
      if (preferences.store.containsKey(key)) {
        values[key] = preferences.store.get(key);
      }
    }
    final data = <String, dynamic>{
      'app': 'bbs.binmt.cc',
      'version': '1.0',
      'backup_mode': includeCredentials ? 'full' : 'safe',
      'exported_at': DateTime.now().toIso8601String(),
      'preferences': values,
    };
    if (includeCredentials) {
      final before = await _cookies();
      if (_auth(before).isNotEmpty) {
        final account = ForumAccount.parse(
          await client.source('$forumOrigin/home.php?mod=space&do=profile'),
          requireDetails: false,
        );
        final after = await _cookies();
        if (_auth(before) != _auth(after)) {
          throw const ForumFailure('账号已变化，请重新备份。');
        }
        data['forum_session'] = {'uid': account.uid, 'cookies': after};
      } else {
        data['forum_session'] = null;
      }
    }
    validateBackup(data);
    return data;
  }

  void validateBackup(Map<String, dynamic> data) {
    if (data['app'] != 'bbs.binmt.cc' ||
        data['version'] != '1.0' ||
        !const ['safe', 'full'].contains(data['backup_mode']) ||
        data['preferences'] is! Map<String, dynamic>) {
      throw const FormatException('不是有效的 MT论坛备份');
    }
    final full = data['backup_mode'] == 'full';
    for (final entry in (data['preferences'] as Map<String, dynamic>).entries) {
      if (!allowedKeys.contains(entry.key) &&
          !(full && entry.key == 'webdav_password')) {
        continue;
      }
      final value = entry.value;
      final valid = boolKeys.contains(entry.key)
          ? value is bool
          : intKeys.contains(entry.key)
          ? value is int
          : entry.key == 'textScale'
          ? value is num && value.isFinite && value >= .8 && value <= 1.4
          : value is String;
      if (!valid) throw const FormatException('备份设置类型无效');
      if (entry.key == 'themeMode' && (value < 0 || value > 2) ||
          entry.key == 'color' && (value < 0 || value > 7) ||
          entry.key == 'fontWeightAdjustment' &&
              !Preferences.fontWeightAdjustments.contains(value)) {
        throw const FormatException('备份设置超出支持范围');
      }
      if (entry.key == 'webdav_url' && (value as String).isNotEmpty) {
        WebDavService.serverUri(value);
      }
      if (entry.key == 'webdav_directory') {
        WebDavService.directory(value as String);
      }
      if (entry.key == 'history') {
        final rows = jsonDecode(value as String);
        if (rows is! List || rows.length > 100) {
          throw const FormatException('浏览历史无效');
        }
        for (final row in rows) {
          if (row is! Map<String, dynamic> ||
              row['title'] is! String ||
              row['url'] is! String ||
              (row.containsKey('subtitle') && row['subtitle'] is! String)) {
            throw const FormatException('浏览历史无效');
          }
          final uri = Uri.tryParse(row['url'] as String);
          if (uri == null || !isForumUri(uri) || !isThreadLink(uri)) {
            throw const FormatException('浏览历史地址无效');
          }
        }
      }
    }
    if (full) {
      if (!data.containsKey('forum_session')) {
        throw const FormatException('全量备份缺少会话信息');
      }
      final session = data['forum_session'];
      if (session != null) {
        if (session is! Map<String, dynamic> ||
            session['uid'] is! String ||
            !RegExp(r'^\d+$').hasMatch(session['uid'] as String) ||
            session['cookies'] is! String ||
            _auth(session['cookies'] as String).isEmpty) {
          throw const FormatException('备份会话无效');
        }
        _cookiePairs(session['cookies'] as String);
      }
    }
  }

  List<String> _cookiePairs(String raw) {
    if (raw.length > 65536 || raw.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('备份会话格式无效');
    }
    final pairs = raw
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (pairs.length > 128) throw const FormatException('备份 Cookie 数量异常');
    if (pairs.any((s) => !RegExp(r'^[A-Za-z0-9_.-]+=').hasMatch(s))) {
      throw const FormatException('备份 Cookie 无效');
    }
    return pairs;
  }

  Future<void> _replaceCookies(String raw) async {
    final pairs = _cookiePairs(raw);
    await client.logout();
    for (final pair in pairs) {
      await ForumClient.platform.invokeMethod<void>('setCookie', {
        'url': '$forumOrigin/',
        'cookie': '$pair; Path=/; Secure; HttpOnly',
      });
    }
    await ForumClient.platform.invokeMethod<void>(
      'flushForumCookies',
      '$forumOrigin/',
    );
  }

  Future<void> _write(String key, Object? value) async {
    final store = preferences.store;
    final saved = value == null
        ? await store.remove(key)
        : value is bool
        ? await store.setBool(key, value)
        : value is int && key != 'textScale'
        ? await store.setInt(key, value)
        : value is num
        ? await store.setDouble(key, value.toDouble())
        : await store.setString(key, value as String);
    if (!saved) throw const ForumFailure('备份数据写入失败');
  }

  Future<void> restoreAllData(Map<String, dynamic> data) async {
    validateBackup(data);
    final full = data['backup_mode'] == 'full';
    final incoming = Map<String, dynamic>.from(data['preferences'] as Map)
      ..removeWhere(
        (key, _) =>
            !allowedKeys.contains(key) && !(full && key == 'webdav_password'),
      );
    // A safe restore must not carry a local password to a different DAV account.
    final store = preferences.store;
    if (!full &&
        (incoming.containsKey('webdav_url') ||
            incoming.containsKey('webdav_username'))) {
      String normalize(String value) =>
          value.isEmpty ? '' : WebDavService.serverUri(value).toString();
      final changedServer =
          incoming.containsKey('webdav_url') &&
          normalize(incoming['webdav_url'] as String) !=
              normalize(store.getString('webdav_url') ?? '');
      final changedUser =
          incoming.containsKey('webdav_username') &&
          (incoming['webdav_username'] as String).trim() !=
              (store.getString('webdav_username') ?? '').trim();
      if (changedServer || changedUser) incoming['webdav_password'] = null;
    }
    if (full && !incoming.containsKey('webdav_password')) {
      incoming['webdav_password'] = null;
    }
    final before = {
      for (final key in incoming.keys) key: preferences.store.get(key),
    };
    final oldCookie = full ? await _cookies() : null;
    try {
      if (full) {
        await _replaceCookies(
          (data['forum_session'] as Map?)?['cookies'] as String? ?? '',
        );
      }
      for (final entry in incoming.entries) {
        await _write(entry.key, entry.value);
      }
    } catch (_) {
      // Keep a local rollback so a partial settings/session write cannot mix accounts.
      var rollbackFailed = false;
      if (oldCookie != null) {
        try {
          await _replaceCookies(oldCookie);
        } catch (_) {
          rollbackFailed = true;
        }
      }
      for (final entry in before.entries) {
        try {
          await _write(entry.key, entry.value);
        } catch (_) {
          rollbackFailed = true;
        }
      }
      if (rollbackFailed) {
        throw const ForumFailure('恢复失败且本机回滚未完成，请检查设置并重新登录论坛。');
      }
      rethrow;
    } finally {
      preferences.reload();
    }
  }
}
