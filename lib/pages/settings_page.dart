import 'package:flutter/material.dart';

import '../core/design_system/components/review_choice_tile.dart';
import '../core/design_system/components/review_frosted_app_bar.dart';
import '../core/design_system/components/review_preference_tile.dart';
import '../core/design_system/components/review_switch_tile.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_section_card.dart';
import '../data/preferences.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.preferences});
  final Preferences preferences;

  String fontWeightName(int value) => switch (value) {
    -100 => '偏细',
    100 => '中等',
    200 => '偏粗',
    300 => '加粗',
    _ => '默认',
  };

  void showFontWeightDialog(BuildContext context) {
    const options = [
      (-100, '偏细', '轻盈精炼视觉'),
      (0, '默认', '标准字重'),
      (100, '中等', '适度加深笔触'),
      (200, '偏粗', '增强文字层级'),
      (300, '加粗', '加重文字笔画'),
    ];
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择字体粗细'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in options)
                ReviewChoiceTile<int>(
                  title: item.$2,
                  summary: item.$3,
                  value: item.$1,
                  groupValue: preferences.fontWeightAdjustment,
                  onSelected: () {
                    preferences.fontWeightAdjustment = item.$1;
                    preferences.save();
                    Navigator.pop(dialogContext);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Scaffold(
      appBar: const ReviewFrostedAppBar(title: Text('个性化')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text('外观'),
          ),
          AppSectionCard(
            child: Column(
              children: [
                for (final item in [
                  (ThemeMode.system, '跟随系统'),
                  (ThemeMode.light, '浅色'),
                  (ThemeMode.dark, '深色'),
                ])
                  ReviewChoiceTile<ThemeMode>(
                    title: item.$2,
                    value: item.$1,
                    groupValue: preferences.mode,
                    onSelected: () {
                      preferences.mode = item.$1;
                      preferences.save();
                    },
                  ),
                const Divider(height: 1),
                ReviewSwitchTile(
                  title: '纯黑模式',
                  summary: '深色主题使用纯黑背景',
                  value: preferences.pureBlack,
                  onChanged: (value) {
                    preferences.pureBlack = value;
                    preferences.save();
                  },
                ),
                ReviewSwitchTile(
                  title: '动态取色',
                  summary: '使用系统提供的壁纸配色',
                  value: preferences.dynamicColor,
                  onChanged: (value) {
                    preferences.dynamicColor = value;
                    preferences.save();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text('字体'),
          ),
          AppSectionCard(
            child: Column(
              children: [
                ReviewPreferenceTile(
                  title: '应用字体粗细',
                  subtitle:
                      '当前：${fontWeightName(preferences.fontWeightAdjustment)}',
                  leading: const Icon(Icons.format_bold_rounded),
                  onTap: () => showFontWeightDialog(context),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.format_size_rounded),
                  title: const Text('应用字体大小'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${(preferences.textScale * 100).round()}%'),
                      Slider(
                        value: preferences.textScale,
                        min: 0.8,
                        max: 1.4,
                        divisions: 12,
                        label: '${(preferences.textScale * 100).round()}%',
                        onChanged: preferences.previewTextScale,
                        onChangeEnd: (_) => preferences.save(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text('底部导航'),
          ),
          AppSectionCard(
            child: ReviewSwitchTile(
              leading: const Icon(Icons.dock_rounded),
              title: '使用悬浮底栏',
              summary: '居中显示悬浮式导航栏',
              value: preferences.floatingNavigation,
              onChanged: (value) {
                preferences.floatingNavigation = value;
                preferences.save();
              },
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text('显示效果'),
          ),
          AppSectionCard(
            child: ReviewSwitchTile(
              leading: Icon(
                Icons.blur_on_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: '使用液态玻璃效果',
              summary: '控制液态玻璃控件；当前应用于悬浮底栏',
              value: preferences.liquidGlass,
              onChanged: (value) {
                preferences.liquidGlass = value;
                preferences.save();
              },
            ),
          ),
          const SizedBox(height: 24),
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 12),
            child: Text('主题颜色'),
          ),
          AppSectionCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < AppTheme.themeColors.length; i++)
                    ChoiceChip(
                      label: Text(AppTheme.themeColors[i]['name'] as String),
                      selected: preferences.color == i,
                      avatar: CircleAvatar(
                        backgroundColor: AppTheme.getSeedColor(i),
                        radius: 8,
                      ),
                      onSelected: preferences.dynamicColor
                          ? null
                          : (_) {
                              preferences.color = i;
                              preferences.save();
                            },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          AppSectionCard(
            child: Column(
              children: [
                ReviewSwitchTile(
                  title: '触感反馈',
                  value: preferences.haptics,
                  onChanged: (value) {
                    preferences.haptics = value;
                    preferences.save();
                  },
                ),
                ReviewPreferenceTile(
                  title: '关于 MT论坛',
                  subtitle: '1.0.0 · Material 3',
                  leading: const Icon(Icons.info_outline),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'MT论坛',
                    applicationVersion: '1.0.0',
                    children: [
                      const Text(
                        '第三方论坛客户端。论坛账号与内容由 bbs.binmt.cc 提供。界面组件复用 Review（MIT，© 2026 Chengeeker）。',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
