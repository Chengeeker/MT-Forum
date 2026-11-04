import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Adapted from Review: conservatively manages MD5-named image cache files.
class ImageCacheMaintenance {
  ImageCacheMaintenance._();
  static final _cacheName = RegExp(r'^[a-f0-9]{32}$');
  static String formatBytes(int bytes) {
    var value = bytes.toDouble();
    var index = 0;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    return '${value.toStringAsFixed(index == 0 ? 0 : 2)} ${units[index]}';
  }

  static Future<Directory> _directory() async =>
      Directory('${(await getTemporaryDirectory()).path}/cacheimage');

  static Future<int> getDiskCacheSize() async => scan(await _directory());
  static Future<int> clearDiskCache() async =>
      scan(await _directory(), clear: true);

  static Future<int> scan(Directory directory, {bool clear = false}) async {
    if (!await directory.exists()) return 0;
    // Do not follow a replaced cache directory or links into account/media data.
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Cache directory is a symbolic link');
    }
    final now = DateTime.now();
    var bytes = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !_cacheName.hasMatch(entity.uri.pathSegments.last)) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (clear) {
          if (now.difference(stat.modified) < const Duration(minutes: 1)) {
            continue;
          }
          await entity.delete();
        }
        bytes += stat.size;
      } on FileSystemException {
        // A download or Android can replace a cache file while enumerating it.
      }
    }
    return bytes;
  }

  static Future<void> checkAndAutoClear(int thresholdMb) async {
    if (thresholdMb <= 0) return;
    try {
      if (await getDiskCacheSize() >= thresholdMb * 1024 * 1024) {
        await clearDiskCache();
      }
    } catch (_) {
      // Cache maintenance must not interrupt startup or media navigation.
    }
  }
}
