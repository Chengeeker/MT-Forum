import 'package:flutter/material.dart';

import '../core/utils/app_dialog.dart';
import '../core/utils/haptic_feedback_util.dart';
import 'web_page.dart';

const forumAppVersion = '1.5.0';

Future<void> showForumAboutDialog(BuildContext context) {
  HapticFeedbackUtil.light();
  final scheme = Theme.of(context).colorScheme;
  return showAppDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/app-icon.png',
                width: 72,
                height: 72,
                cacheWidth: (72 * MediaQuery.devicePixelRatioOf(context))
                    .ceil(),
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Text(
                'MT论坛',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'v$forumAppVersion',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Material 3 论坛客户端',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 30),
          _feature(Icons.palette_outlined, 'Material 3 动态配色与个性化主题', scheme),
          const SizedBox(height: 8),
          _feature(Icons.forum_outlined, '论坛浏览、搜索、消息与后台签到', scheme),
          const SizedBox(height: 8),
          _feature(
            Icons.photo_library_outlined,
            '图片画廊、视频播放与 WebDAV 备份',
            scheme,
          ),
          const SizedBox(height: 26),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => openExternal(
              dialogContext,
              Uri.parse('https://github.com/Chengeeker/MT-Forum'),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'GitHub 开源地址',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'github.com/Chengeeker/MT-Forum',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: dialogContext,
            applicationName: 'MT论坛',
            applicationVersion: forumAppVersion,
            applicationLegalese: '第三方论坛客户端。论坛内容与图标归各自权利人所有。界面复用 Review 组件（MIT，© 2026 Chengeeker）。',
          ),
          child: const Text('开源许可'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}

Widget _feature(IconData icon, String text, ColorScheme scheme) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Icon(icon, size: 16, color: scheme.primary),
    const SizedBox(width: 8),
    Expanded(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          color: scheme.onSurfaceVariant,
          height: 1.35,
        ),
      ),
    ),
  ],
);
