import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'account_validation.dart';
import 'forum.dart';
import 'preferences.dart';

class MediaStorage {
  MediaStorage._();
  static const maxVideoBytes = 512 * 1024 * 1024;

  static String safeFolderName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'^\.+|[.\s]+$'), '')
        .trim();
    return cleaned.isEmpty
        ? '未知作者'
        : String.fromCharCodes(cleaned.runes.take(40));
  }

  static Future<String> album({
    Preferences? preferences,
    ForumClient? client,
    required bool video,
    String author = '',
  }) async {
    final type = video
        ? preferences?.videoSavePathType ?? 0
        : preferences?.imageSavePathType ?? 0;
    if (type == 0) return 'MT论坛';
    if (type == 2) return 'MT论坛/${safeFolderName(author)}';
    final account = await validateForumAccount(client ?? ForumClient());
    if (account == null) throw const ForumFailure('按本人昵称保存需要有效账号，请登录后重试。');
    return 'MT论坛/${safeFolderName(account.name)}';
  }

  static bool canSaveVideo(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      RegExp(r'\.(mp4|webm|mov|mkv)$', caseSensitive: false).hasMatch(uri.path);

  static Future<void> saveVideo(
    Uri uri, {
    Preferences? preferences,
    ForumClient? client,
    String author = '',
    required CancelToken cancelToken,
    Dio? dio,
  }) async {
    if (!canSaveVideo(uri)) throw const ForumFailure('仅支持保存直接链接的视频文件。');
    final folder = await album(
      preferences: preferences,
      client: client,
      video: true,
      author: author,
    );
    final http =
        dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            maxRedirects: 0,
          ),
        );
    Directory? temp;
    try {
      final response = await _response(http, uri, cancelToken);
      final body = response.data;
      if (body == null) throw const ForumFailure('视频内容为空。');
      final mime = response.headers
          .value(Headers.contentTypeHeader)
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      const mimeTypes = {
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mov': 'video/quicktime',
        'mkv': 'video/x-matroska',
      };
      final extension = uri.path.split('.').last.toLowerCase();
      if (mime != null &&
          mime != 'application/octet-stream' &&
          !mimeTypes.values.contains(mime)) {
        await body.stream.listen((_) {}).cancel();
        throw const ForumFailure('服务器没有返回可保存的视频文件。');
      }
      final size =
          int.tryParse(
            response.headers.value(Headers.contentLengthHeader) ?? '',
          ) ??
          0;
      if (size > maxVideoBytes) {
        await body.stream.listen((_) {}).cancel();
        throw const ForumFailure('视频超过512 MB，无法保存。');
      }
      final root = Directory(
        '${(await getTemporaryDirectory()).path}/media-downloads',
      );
      await root.create(recursive: true);
      temp = await root.createTemp('save-');
      final file = File('${temp.path}/media.$extension');
      final output = await file.open(mode: FileMode.write);
      var received = 0;
      try {
        await for (final chunk in body.stream) {
          if (cancelToken.isCancelled) throw const ForumFailure('已取消保存');
          received += chunk.length;
          if (received > maxVideoBytes) {
            throw const ForumFailure('视频超过512 MB，无法保存。');
          }
          await output.writeFrom(chunk);
        }
      } finally {
        await output.close();
      }
      if (received == 0 || cancelToken.isCancelled) {
        throw const ForumFailure('视频为空或保存已取消。');
      }
      await ForumClient.platform.invokeMethod<String>('saveMediaToGallery', {
        'sourcePath': file.path,
        'fileName':
            'mt_forum_${DateTime.now().microsecondsSinceEpoch}.$extension',
        'mimeType': mimeTypes[extension],
        'album': folder,
      });
    } finally {
      if (dio == null) http.close(force: true);
      if (temp != null && await temp.exists()) {
        await temp.delete(recursive: true);
      }
    }
  }

  static Future<Response<ResponseBody>> _response(
    Dio http,
    Uri uri,
    CancelToken token,
  ) async {
    var target = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final response = await http.get<ResponseBody>(
        target.toString(),
        options: Options(
          responseType: ResponseType.stream,
          headers: forumMediaHeaders(target),
          followRedirects: false,
          validateStatus: (status) =>
              status != null &&
              (status >= 200 && status < 300 ||
                  const {301, 302, 303, 307, 308}.contains(status)),
        ),
        cancelToken: token,
      );
      if (response.statusCode! < 300) return response;
      await response.data?.stream.listen((_) {}).cancel();
      final location = response.headers.value('location');
      final next = location == null ? null : target.resolve(location);
      if (next == null ||
          next.scheme != 'https' ||
          next.host.isEmpty ||
          next.userInfo.isNotEmpty) {
        throw const ForumFailure('视频下载跳转地址无效。');
      }
      target = next;
    }
    throw const ForumFailure('视频下载跳转次数过多。');
  }
}
