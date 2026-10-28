import 'dart:async';

import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:video_player/video_player.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/utils/haptic_feedback_util.dart';
import '../data/forum.dart';

class ForumImageGalleryPage extends StatefulWidget {
  const ForumImageGalleryPage({
    super.key,
    required this.images,
    this.previews = const [],
    required this.initialIndex,
    required this.heroTagPrefix,
    this.useLiquidGlass = false,
  });

  final List<String> images;
  final List<String> previews;
  final int initialIndex;
  final String heroTagPrefix;
  final bool useLiquidGlass;

  @override
  State<ForumImageGalleryPage> createState() => _ForumImageGalleryPageState();
}

class _ForumImageGalleryPageState extends State<ForumImageGalleryPage> {
  late final ExtendedPageController controller;
  late int currentIndex;
  bool saving = false;
  bool isReturning = false;
  Animation<double>? routeAnimation;

  String heroTag(int index) => '${widget.heroTagPrefix}:$index';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (identical(animation, routeAnimation)) return;
    routeAnimation?.removeStatusListener(onRouteAnimationStatus);
    routeAnimation = animation;
    animation?.addStatusListener(onRouteAnimationStatus);
  }

  void onRouteAnimationStatus(AnimationStatus status) {
    final returning = status == AnimationStatus.reverse;
    if (!mounted || returning == isReturning) return;
    setState(() => isReturning = returning);
  }

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex.clamp(0, widget.images.length - 1);
    controller = ExtendedPageController(initialPage: currentIndex);
  }

  @override
  void dispose() {
    routeAnimation?.removeStatusListener(onRouteAnimationStatus);
    controller.dispose();
    super.dispose();
  }

  Future<void> saveCurrentImage() async {
    if (saving) return;
    final uri = Uri.tryParse(widget.images[currentIndex]);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    HapticFeedbackUtil.light();
    setState(() => saving = true);
    try {
      final response =
          await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ).get<List<int>>(
            uri.toString(),
            options: Options(
              responseType: ResponseType.bytes,
              headers: forumMediaHeaders(uri),
            ),
          );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty || bytes.length > 64 * 1024 * 1024) {
        throw const FormatException('图片为空或超过 64 MB');
      }
      final type = response.headers
          .value(Headers.contentTypeHeader)
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      final mime =
          const {
            'image/jpeg',
            'image/png',
            'image/gif',
            'image/webp',
            'image/bmp',
          }.contains(type)
          ? type!
          : 'image/jpeg';
      final extension = switch (mime) {
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        'image/bmp' => 'bmp',
        _ => 'jpg',
      };
      await ForumClient.platform.invokeMethod<String>('saveMediaToGallery', {
        'bytes': Uint8List.fromList(bytes),
        'fileName':
            'mt_forum_${DateTime.now().millisecondsSinceEpoch}.$extension',
        'mimeType': mime,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存到图片相册')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败，请检查网络或存储权限')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ExtendedImageGesturePageView.builder(
            controller: controller,
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => currentIndex = index),
            itemBuilder: (context, index) {
              final url = widget.images[index];
              final previewUrl = index < widget.previews.length
                  ? widget.previews[index]
                  : url;
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
                      return Image.network(
                        previewUrl,
                        key: ValueKey('gallery-loading-preview-$index'),
                        headers: forumMediaHeaders(Uri.parse(previewUrl)),
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) => progress == null
                            ? child
                            : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 44,
                          ),
                        ),
                      );
                    }
                    if (state.extendedImageLoadState == LoadState.failed) {
                      if (previewUrl != url) {
                        return Image.network(
                          previewUrl,
                          key: ValueKey('gallery-loading-preview-$index'),
                          headers: forumMediaHeaders(Uri.parse(previewUrl)),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 44,
                            ),
                          ),
                        );
                      }
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
          if (!widget.useLiquidGlass || !isReturning)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _ForumGalleryActionButton(
                        tooltip: '返回',
                        icon: Icons.arrow_back_rounded,
                        useLiquidGlass: widget.useLiquidGlass,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: Text(
                            '${currentIndex + 1} / ${widget.images.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      _ForumGalleryActionButton(
                        tooltip: saving ? '正在保存' : '保存到相册',
                        icon: saving ? null : Icons.download_rounded,
                        useLiquidGlass: widget.useLiquidGlass,
                        onPressed: saving ? null : saveCurrentImage,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ForumGalleryActionButton extends StatelessWidget {
  const _ForumGalleryActionButton({
    required this.tooltip,
    required this.icon,
    required this.useLiquidGlass,
    required this.onPressed,
  });

  final String tooltip;
  final IconData? icon;
  final bool useLiquidGlass;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final glyph = icon == null
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(icon, color: Colors.white);
    if (useLiquidGlass) {
      return GlassButton(
        label: tooltip,
        width: 48,
        height: 48,
        icon: glyph,
        iconSize: 22,
        iconColor: Colors.white,
        onTap: onPressed ?? () {},
        enabled: onPressed != null,
        useOwnLayer: true,
        stretch: 0.8,
        anchorStretchSettings: const AnchorStretchSettings(
          intensity: 0.8,
          squashFactor: 0.3,
          translationDamping: 0.15,
          bounciness: 0.2,
        ),
        glowColor: const Color(0x20FFFFFF),
        glowOpacity: 1,
        quality: GlassQuality.premium,
        settings: const LiquidGlassSettings(
          glassColor: Color(0x66000000),
          bodyMode: GlassBodyMode.clear,
          thickness: 32,
          blur: 2,
          lightIntensity: 0.25,
          ambientStrength: 0,
          refractiveIndex: 1.24,
          chromaticAberration: 0.025,
          shadowElevation: 0,
        ),
      );
    }
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 7,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.08),
                  blurRadius: 5,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.grey.shade200.withValues(alpha: 0.3),
                        Colors.grey.shade500.withValues(alpha: 0.2),
                        Colors.grey.shade800.withValues(alpha: 0.36),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.34),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: tooltip,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            padding: EdgeInsets.zero,
            color: Colors.white,
            onPressed: onPressed,
            icon: glyph,
          ),
        ],
      ),
    );
  }
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
