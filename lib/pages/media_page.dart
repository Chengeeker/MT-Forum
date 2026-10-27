import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../data/forum.dart';

class ForumImageGalleryPage extends StatefulWidget {
  const ForumImageGalleryPage({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.heroTagPrefix,
  });

  final List<String> images;
  final int initialIndex;
  final String heroTagPrefix;

  @override
  State<ForumImageGalleryPage> createState() => _ForumImageGalleryPageState();
}

class _ForumImageGalleryPageState extends State<ForumImageGalleryPage> {
  late final ExtendedPageController controller;
  late int currentIndex;

  String heroTag(int index) => '${widget.heroTagPrefix}:$index';

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    controller = ExtendedPageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: ReviewFrostedAppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Text('${currentIndex + 1} / ${widget.images.length}'),
      actions: [
        IconButton(
          tooltip: '复制图片链接',
          icon: const Icon(Icons.link),
          onPressed: () async => Clipboard.setData(
            ClipboardData(text: widget.images[currentIndex]),
          ),
        ),
      ],
    ),
    body: ExtendedImageGesturePageView.builder(
      controller: controller,
      itemCount: widget.images.length,
      onPageChanged: (index) => setState(() => currentIndex = index),
      itemBuilder: (context, index) {
        final url = widget.images[index];
        return Hero(
          tag: heroTag(index),
          child: ExtendedImage.network(
            url,
            headers: forumMediaHeaders(Uri.parse(url)),
            fit: BoxFit.contain,
            mode: ExtendedImageMode.gesture,
            enableSlideOutPage: false,
            initGestureConfigHandler: (_) => GestureConfig(
              minScale: 1,
              maxScale: 5,
              initialScale: 1,
              inPageView: true,
            ),
            loadStateChanged: (state) {
              if (state.extendedImageLoadState == LoadState.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.extendedImageLoadState == LoadState.failed) {
                return const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 44,
                  ),
                );
              }
              return null;
            },
          ),
        );
      },
    ),
  );
}

class ForumVideoPage extends StatefulWidget {
  const ForumVideoPage({super.key, required this.url, required this.title});

  final Uri url;
  final String title;

  @override
  State<ForumVideoPage> createState() => _ForumVideoPageState();
}

class _ForumVideoPageState extends State<ForumVideoPage> {
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  VideoPlayerController? controller;
  bool failed = false;
  double speed = 1;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    unawaited(controller?.dispose());
    super.dispose();
  }

  Future<void> load() async {
    if (!isDirectVideoUri(widget.url)) {
      setState(() => failed = true);
      return;
    }
    final old = controller;
    controller = null;
    await old?.dispose();
    if (!mounted) return;
    final next = VideoPlayerController.networkUrl(
      widget.url,
      httpHeaders: forumMediaHeaders(widget.url),
    );
    controller = next;
    setState(() => failed = false);
    try {
      await next.initialize();
      if (!mounted || controller != next) return;
      await next.setLooping(false);
      await next.play();
    } catch (_) {
      if (mounted && controller == next) setState(() => failed = true);
    }
  }

  String time(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: ReviewFrostedAppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: Stack(
      children: [
        Center(
          child: failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '视频加载失败或格式不受支持',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: load,
                      child: const Text('重试'),
                    ),
                  ],
                )
              : controller == null || !controller!.value.isInitialized
              ? const CircularProgressIndicator()
              : AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
        ),
        if (controller case final player?)
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: player,
            builder: (context, value, _) => Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: value.isPlaying ? '暂停' : '播放',
                        color: Colors.white,
                        onPressed: !value.isInitialized
                            ? null
                            : () => value.isPlaying
                                  ? player.pause()
                                  : player.play(),
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      Text(
                        time(value.position),
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: VideoProgressIndicator(
                          player,
                          allowScrubbing: value.isInitialized,
                          colors: VideoProgressColors(
                            playedColor: Theme.of(context).colorScheme.primary,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time(value.duration),
                        style: const TextStyle(color: Colors.white),
                      ),
                      PopupMenuButton<double>(
                        initialValue: speed,
                        tooltip: '播放速度',
                        enabled: value.isInitialized,
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        onSelected: (value) async {
                          setState(() => speed = value);
                          await player.setPlaybackSpeed(value);
                        },
                        itemBuilder: (context) => [
                          for (final item in speeds)
                            PopupMenuItem(value: item, child: Text('$item×')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '$speed×',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
