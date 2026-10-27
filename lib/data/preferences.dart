import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/haptic_feedback_util.dart';
import 'forum.dart';

class Preferences extends ChangeNotifier {
  Preferences(this.store) {
    mode = ThemeMode.values[(store.getInt('themeMode') ?? 0).clamp(0, 2)];
    color = (store.getInt('color') ?? 2).clamp(0, 7);
    pureBlack = store.getBool('pureBlack') ?? false;
    dynamicColor = store.getBool('dynamicColor') ?? false;
    floatingNavigation = store.getBool('floatingNavigation') ?? true;
    liquidGlass = store.getBool('liquidGlass') ?? false;
    textScale = (store.getDouble('textScale') ?? 1).clamp(0.8, 1.4).toDouble();
    final savedWeight = store.getInt('fontWeightAdjustment') ?? 0;
    fontWeightAdjustment = fontWeightAdjustments.contains(savedWeight)
        ? savedWeight
        : 0;
    haptics = store.getBool('haptics') ?? true;
    HapticFeedbackUtil.isEnabled = haptics;
    try {
      history = (jsonDecode(store.getString('history') ?? '[]') as List)
          .map((e) => ForumLink.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((e) => isForumUri(Uri.parse(e.url)))
          .take(100)
          .toList();
    } catch (_) {
      history = [];
    }
  }
  final SharedPreferences store;
  ThemeMode mode = ThemeMode.system;
  int color = 2;
  bool pureBlack = false,
      dynamicColor = false,
      floatingNavigation = true,
      liquidGlass = false,
      haptics = true;
  double textScale = 1;
  int fontWeightAdjustment = 0;
  static const fontWeightAdjustments = [-100, 0, 100, 200, 300];
  List<ForumLink> history = [];
  Future<void> save() async {
    HapticFeedbackUtil.isEnabled = haptics;
    notifyListeners();
    await Future.wait([
      store.setInt('themeMode', mode.index),
      store.setInt('color', color),
      store.setBool('pureBlack', pureBlack),
      store.setBool('dynamicColor', dynamicColor),
      store.setBool('floatingNavigation', floatingNavigation),
      store.setBool('liquidGlass', liquidGlass),
      store.setDouble('textScale', textScale),
      store.setInt('fontWeightAdjustment', fontWeightAdjustment),
      store.setBool('haptics', haptics),
    ]);
  }

  void previewTextScale(double value) {
    textScale = value.clamp(0.8, 1.4).toDouble();
    notifyListeners();
  }

  Future<void> visited(ForumLink link) async {
    history = [
      link,
      ...history.where((e) => e.url != link.url),
    ].take(100).toList();
    notifyListeners();
    await store.setString(
      'history',
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    history = [];
    notifyListeners();
    await store.remove('history');
  }
}
