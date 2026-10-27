import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_text_scaler.dart';
import 'data/forum.dart';
import 'data/preferences.dart';
import 'pages/home_page.dart';
import 'pages/web_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Review UI components',
    ], await rootBundle.loadString('assets/review-license.txt'));
    yield LicenseEntryWithLineBreaks([
      'Liquid Glass Widgets',
    ], await rootBundle.loadString('assets/liquid-glass-license.txt'));
    yield LicenseEntryWithLineBreaks(
      ['Liquid Glass Widgets third party notices'],
      await rootBundle.loadString(
        'assets/liquid-glass-third-party-notices.txt',
      ),
    );
  });
  final preferences = Preferences(await SharedPreferences.getInstance());
  runApp(MtForumApp(preferences: preferences));
}

class MtForumApp extends StatefulWidget {
  const MtForumApp({
    super.key,
    required this.preferences,
    this.client,
    this.useBrowserReader = true,
  });
  final Preferences preferences;
  final ForumClient? client;
  final bool useBrowserReader;
  @override
  State<MtForumApp> createState() => _MtForumAppState();
}

class _MtForumAppState extends State<MtForumApp> {
  late final client = widget.client ?? ForumClient();
  BrowserReader? reader;
  @override
  void initState() {
    super.initState();
    if (widget.useBrowserReader) {
      reader = BrowserReader();
      client.browserRead = reader!.read;
      client.browserLogin = reader!.login;
      client.browserCancelLogin = reader!.cancelLogin;
      client.browserResetSession = reader!.resetSession;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.preferences,
    builder: (context, _) => LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: DynamicColorBuilder(
        builder: (light, dark) {
          final prefs = widget.preferences;
          return MaterialApp(
            title: 'MT论坛',
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            themeMode: prefs.mode,
            theme: AppTheme.lightTheme(
              colorIndex: prefs.color,
              dynamicColorScheme: prefs.dynamicColor ? light : null,
              fontWeightAdjustment: prefs.fontWeightAdjustment,
            ),
            darkTheme: AppTheme.darkTheme(
              colorIndex: prefs.color,
              isPureBlack: prefs.pureBlack,
              dynamicColorScheme: prefs.dynamicColor ? dark : null,
              fontWeightAdjustment: prefs.fontWeightAdjustment,
            ),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  textScaler: AppTextScaler(media.textScaler, prefs.textScale),
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: Stack(
              children: [
                if (reader != null)
                  Offstage(
                    offstage: true,
                    child: SizedBox(
                      width: 390,
                      height: 800,
                      child: WebViewWidget(controller: reader!.controller),
                    ),
                  ),
                HomePage(client: client, preferences: prefs),
              ],
            ),
          );
        },
      ),
    ),
  );
}
