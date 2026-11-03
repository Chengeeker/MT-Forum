import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

const defaultWebDavDirectory = 'MT论坛';
const maxBackupBytes = 4 * 1024 * 1024;

/// Adapted from Review's WebDAV service; MT backups use their own file names.
class WebDavService {
  WebDavService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
  final Dio _dio;

  static Uri serverUri(String url) {
    var value = url.trim();
    if (!value.contains('://')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !(uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                const {'localhost', '127.0.0.1', '::1'}.contains(uri.host)))) {
      throw const FormatException('请使用有效的 HTTPS WebDAV 服务器地址');
    }
    return uri.replace(
      path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
    );
  }

  static String directory(String value) {
    final name = value.trim().isEmpty ? defaultWebDavDirectory : value.trim();
    if (name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\\x00-\x1f\x7f]'))) {
      throw const FormatException('请输入单个文件夹名称，不要包含斜杠或上级目录');
    }
    return name;
  }

  Options _options(
    String method,
    String username,
    String password, {
    ResponseType? responseType,
    Map<String, dynamic> headers = const {},
  }) {
    if (username.contains(RegExp(r'[:\r\n]')) ||
        password.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('账号或密码格式无效');
    }
    return Options(
      method: method,
      followRedirects: false,
      responseType: responseType,
      validateStatus: (_) => true,
      headers: {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        ...headers,
      },
    );
  }

  Future<bool> testConnection({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.requestUri(
        serverUri(serverUrl),
        options: _options(
          'PROPFIND',
          username,
          password,
          headers: {'Depth': '0'},
        ),
      );
      return const [200, 207].contains(response.statusCode);
    } catch (_) {
      return false;
    }
  }

  Future<bool> uploadBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directoryName,
    required Map<String, dynamic> data,
  }) async {
    try {
      final base = serverUri(serverUrl);
      final folder = base.resolve(
        '${Uri.encodeComponent(directory(directoryName))}/',
      );
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      if (bytes.length > maxBackupBytes) return false;
      final mkdir = await _dio.requestUri(
        folder,
        options: _options('MKCOL', username, password),
      );
      if (!const [200, 201, 405].contains(mkdir.statusCode)) return false;
      Future<Response<dynamic>> upload(String name) => _dio.requestUri(
        folder.resolve(name),
        data: Stream.value(bytes),
        options: _options(
          'PUT',
          username,
          password,
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Content-Length': bytes.length,
          },
        ),
      );
      final latest = await upload('backup_mt_forum_latest.json');
      if (!const [200, 201, 204].contains(latest.statusCode)) return false;
      // As in Review, a failed historical copy does not invalidate the latest file.
      try {
        await upload(
          'backup_mt_forum_${DateTime.now().millisecondsSinceEpoch}.json',
        );
      } catch (_) {
        /* Best effort history. */
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> downloadLatestBackup({
    required String serverUrl,
    required String username,
    required String password,
    required String directoryName,
  }) async {
    try {
      final base = serverUri(serverUrl);
      final uri = base.resolve(
        '${Uri.encodeComponent(directory(directoryName))}/backup_mt_forum_latest.json',
      );
      final response = await _dio.requestUri<ResponseBody>(
        uri,
        options: _options(
          'GET',
          username,
          password,
          responseType: ResponseType.stream,
        ),
      );
      final body = response.data;
      if (body == null) return null;
      if (response.statusCode != 200) {
        await body.stream.listen((_) {}).cancel();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > maxBackupBytes) {
          throw const FormatException('备份文件过大');
        }
        bytes.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
