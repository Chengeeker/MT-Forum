import 'package:flutter/material.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/design_system/components/review_preference_tile.dart';
import '../core/utils/app_dialog.dart';
import '../core/widgets/app_section_card.dart';
import '../data/image_cache_maintenance.dart';
import '../data/preferences.dart';

String _path(int type, bool video) =>
    '${video ? 'Movies' : 'Pictures'}/MT论坛/${switch (type) {
      1 => '本人昵称/',
      2 => '帖子作者昵称/',
      _ => '',
    }}';

class StorageSettingsPage extends StatelessWidget {
  const StorageSettingsPage({super.key, required this.preferences});
  final Preferences preferences;
  Future<void> select(BuildContext context, bool video) async {
    final selected = video
        ? preferences.videoSavePathType
        : preferences.imageSavePathType;
    final choice = await showAppDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(video ? '视频存储路径' : '图片存储路径'),
        content: SingleChildScrollView(
          child: RadioGroup<int>(
            groupValue: selected,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (value, title) in [
                  (0, '默认路径'),
                  (1, '按本人昵称归类'),
                  (2, '按帖子作者昵称归类'),
                ])
                  RadioListTile<int>(
                    value: value,
                    title: Text(title),
                    subtitle: Text(_path(value, video)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    if (video) {
      preferences.videoSavePathType = choice;
    } else {
      preferences.imageSavePathType = choice;
    }
    try {
      await preferences.save();
    } catch (_) {
      preferences.reload();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('存储设置保存失败，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('存储设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionCard(
            child: Column(
              children: [
                ReviewPreferenceTile(
                  title: '图片存储路径',
                  subtitle: _path(preferences.imageSavePathType, false),
                  leading: const Icon(Icons.image_outlined),
                  onTap: () => select(context, false),
                ),
                ReviewPreferenceTile(
                  title: '视频存储路径',
                  subtitle: _path(preferences.videoSavePathType, true),
                  leading: const Icon(Icons.video_library_outlined),
                  onTap: () => select(context, true),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('更改只影响之后保存的媒体，已保存文件不会移动。按本人昵称归类需要有效登录会话。'),
          ),
        ],
      ),
    ),
  );
}

class CacheManagementPage extends StatefulWidget {
  const CacheManagementPage({super.key, required this.preferences});
  final Preferences preferences;
  @override
  State<CacheManagementPage> createState() => _CacheManagementPageState();
}

class _CacheManagementPageState extends State<CacheManagementPage> {
  int bytes = 0;
  bool loading = true, clearing = false;
  int revision = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final current = ++revision;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final size = await ImageCacheMaintenance.getDiskCacheSize();
      if (mounted && current == revision) setState(() => bytes = size);
    } catch (_) {
      if (mounted && current == revision) setState(() => error = '暂时无法读取图片缓存');
    } finally {
      if (mounted && current == revision) setState(() => loading = false);
    }
  }

  Future<void> clear() async {
    if (loading || clearing) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理图片缓存？'),
        content: Text(
          '将清理 ${ImageCacheMaintenance.formatBytes(bytes)} 中可再生成的图片缓存。最近写入的文件会保留；相册、浏览历史和账号数据不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => clearing = true);
    try {
      final freed = await ImageCacheMaintenance.clearDiskCache();
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              freed == 0
                  ? '最近写入的文件已保留，当前没有可清理缓存'
                  : '已清理 ${ImageCacheMaintenance.formatBytes(freed)} 图片缓存',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('清理失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  String threshold(int value) => value == 0
      ? '不限制（关闭自动清理）'
      : value >= 1024
      ? '${value ~/ 1024} GB'
      : '$value MB';
  Future<void> chooseThreshold() async {
    final value = await showAppDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自动清理阈值'),
        content: SingleChildScrollView(
          child: RadioGroup<int>(
            groupValue: widget.preferences.imageCacheThresholdMb,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in Preferences.cacheThresholds)
                  RadioListTile<int>(
                    value: value,
                    title: Text(threshold(value)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (value == null) return;
    if (!mounted) return;
    setState(() => clearing = true);
    try {
      widget.preferences.imageCacheThresholdMb = value;
      await widget.preferences.save();
      await ImageCacheMaintenance.checkAndAutoClear(value);
      if (mounted) await load();
    } catch (_) {
      widget.preferences.reload();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('自动清理规则保存失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) => Scaffold(
      appBar: ReviewFrostedAppBar(
        title: const Text('缓存管理'),
        actions: [
          IconButton(
            tooltip: '重新统计',
            onPressed: loading || clearing ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer,
                    child: const Icon(
                      Icons.cleaning_services_rounded,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (loading)
                    const CircularProgressIndicator()
                  else
                    Text(
                      error ?? ImageCacheMaintenance.formatBytes(bytes),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  const SizedBox(height: 8),
                  const Text('可管理的图片磁盘缓存'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: loading || clearing || error != null || bytes == 0
                    ? null
                    : clear,
                icon: const Icon(Icons.delete_sweep_rounded),
                label: Text(clearing ? '正在清理…' : '清理图片缓存'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 16,
              top: 24,
              bottom: 12,
            ),
            child: Text(
              '自动清理规则',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          AppSectionCard(
            child: ReviewPreferenceTile(
              title: '自动清理阈值',
              subtitle: threshold(widget.preferences.imageCacheThresholdMb),
              leading: const Icon(Icons.auto_delete_outlined),
              onTap: loading || clearing ? null : chooseThreshold,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '启动应用和关闭图片浏览时检查阈值。仅清理图片磁盘缓存，保留最近一分钟写入的文件；不会删除相册文件、浏览历史或登录会话。',
            ),
          ),
        ],
      ),
    ),
  );
}
