import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/design_system/components/review_frosted_app_bar.dart';
import '../data/forum.dart';

Future<void> openExternal(BuildContext context, Uri uri) async {
  if (!['https', 'http', 'mailto'].contains(uri.scheme)) return;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('打开外部链接'),
      content: SelectableText(uri.toString()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('打开'),
        ),
      ],
    ),
  );
  if (accepted == true) {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没有可打开此链接的应用')));
    }
  }
}

final sessionRevision = ValueNotifier<int>(0);
final forumAuthenticated = ValueNotifier<bool>(false);

Future<String> forumAuthCookie() async {
  try {
    final cookie = await ForumClient.platform
        .invokeMethod<String>('cookies', '$forumOrigin/')
        .timeout(const Duration(seconds: 3), onTimeout: () => null);
    final auth = (cookie ?? '')
        .split(';')
        .where((part) {
          final separator = part.indexOf('=');
          return separator > 0 &&
              part.substring(0, separator).trim().endsWith('_auth') &&
              part.substring(separator + 1).trim().isNotEmpty;
        })
        .join(';');
    forumAuthenticated.value = auth.isNotEmpty;
    return auth;
  } on MissingPluginException {
    return '';
  } on PlatformException {
    return '';
  }
}

class ForumWebPage extends StatefulWidget {
  const ForumWebPage({
    super.key,
    required this.title,
    required this.url,
    this.search,
    this.onLogin,
    required this.qqLogin,
  });
  final String title, url;
  final String? search;
  final Future<bool> Function(BuildContext)? onLogin;
  final bool qqLogin;
  @override
  State<ForumWebPage> createState() => _ForumWebPageState();
}

class _ForumWebPageState extends State<ForumWebPage> {
  late final WebViewController controller;
  int progress = 0;
  String? error;
  bool canBack = false, leaving = false;
  bool submittedSearch = false;
  bool authenticating = false;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(forumUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!request.isMainFrame) return NavigationDecision.navigate;
            final uri = Uri.tryParse(request.url);
            if (uri != null && isForumUri(uri)) {
              if (isForumLoginUri(uri) && widget.onLogin != null) {
                unawaited(loginAndResume());
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            }
            if (widget.qqLogin && uri != null && isQQLoginUri(uri)) {
              return NavigationDecision.navigate;
            }
            if (request.isMainFrame && uri != null) {
              unawaited(openExternal(context, uri));
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                error = null;
                progress = 0;
              });
            }
          },
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            final uri = Uri.tryParse(url);
            if (widget.qqLogin && uri != null) {
              if (isForumUri(uri) && (await forumAuthCookie()).isNotEmpty) {
                if (!mounted) return;
                setState(() => leaving = true);
                Navigator.pop(context, true);
                return;
              }
              final back = await controller.canGoBack();
              if (!mounted) return;
              setState(() => canBack = back);
              if (!isForumUri(uri)) return;
            }
            if (widget.onLogin != null && uri != null && isForumUri(uri)) {
              var loginForm = false;
              try {
                final result = await controller.runJavaScriptReturningResult(
                  '!!document.querySelector(\'form[id^="loginform_"]\')',
                );
                loginForm = result == true || result.toString() == 'true';
              } catch (_) {
                // Navigation may replace the document before inspection finishes.
              }
              if (!mounted) return;
              if (loginForm) {
                await loginAndResume();
                return;
              }
            }
            if (!mounted) return;
            await _style();
            if (widget.search != null && !submittedSearch) {
              submittedSearch = true;
              await controller.runJavaScript(
                '''(() => { const input=document.querySelector('input[name="srchtxt"]');if(input && input.form){input.value=${jsonEncode(widget.search)};input.form.requestSubmit();} })();''',
              );
            }
            final back = await controller.canGoBack();
            if (mounted) setState(() => canBack = back);
          },
          onWebResourceError: (event) {
            if (event.isForMainFrame == true && mounted) {
              setState(() => error = '页面连接失败，请检查网络后重试。');
            }
          },
          onHttpError: (event) {
            if (event.request?.uri.toString() == widget.url && mounted) {
              setState(() => error = '网站返回 HTTP ${event.response?.statusCode}');
            }
          },
        ),
      );
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController).setOnShowFileSelector((
        params,
      ) async {
        final url = Uri.tryParse(await controller.currentUrl() ?? '');
        if (url == null || !isForumUri(url)) return [];
        return await ForumClient.platform.invokeListMethod<String>(
              'pickFiles',
              params.mode == FileSelectorMode.openMultiple,
            ) ??
            [];
      });
    }
    unawaited(loadInitialPage());
  }

  Future<void> loadInitialPage() async {
    try {
      if (widget.qqLogin && controller.platform is AndroidWebViewController) {
        final manager = WebViewCookieManager().platform;
        if (manager is AndroidWebViewCookieManager) {
          await manager
              .setAcceptThirdPartyCookies(
                controller.platform as AndroidWebViewController,
                true,
              )
              .timeout(const Duration(seconds: 5));
        }
      }
      if (mounted) await controller.loadRequest(Uri.parse(widget.url));
    } catch (_) {
      if (mounted) setState(() => error = '页面初始化失败，请重试。');
    }
  }

  Future<void> loginAndResume() async {
    if (!mounted || authenticating || widget.onLogin == null) return;
    setState(() => authenticating = true);
    try {
      final loggedIn = await widget.onLogin!(context);
      if (!mounted) return;
      if (!loggedIn) {
        setState(() => leaving = true);
        Navigator.pop(context);
        return;
      }
      await controller.loadRequest(Uri.parse(widget.url));
    } catch (_) {
      if (mounted) setState(() => error = '登录后页面加载失败，请重试。');
    } finally {
      if (mounted) setState(() => authenticating = false);
    }
  }

  Future<void> _style() async {
    final scheme = Theme.of(context).colorScheme;
    String cssColor(Color c) =>
        '#${c.toARGB32().toRadixString(16).substring(2)}';
    // Keep the site's forms, CAPTCHA, hidden inputs and handlers intact.
    final css =
        '''
      :root { color-scheme: ${scheme.brightness == Brightness.dark ? 'dark' : 'light'}; }
      html, body { background:${cssColor(Theme.of(context).scaffoldBackgroundColor)}!important;color:${cssColor(scheme.onSurface)}!important;font:16px/1.6 system-ui!important;min-width:0!important; }
      #hd,#nv,#ft,#frt,#toptb,.comiis_footer,.comiis_topnav { display:none!important; }
      .wp,#wp,#ct,.mn,.bm,.bm_c,.comiis_width,.comiis_login { width:auto!important;min-width:0!important;max-width:100%!important;float:none!important;box-sizing:border-box!important; }
      #ct { margin:0!important;padding:16px!important; } .sd,.appl { display:none!important; }
      .bm,.bm_h,.bm_c,.p_pop,.fwin,.m_c,td,th { background:${cssColor(scheme.surfaceContainerLow)}!important;color:${cssColor(scheme.onSurface)}!important;border-color:${cssColor(scheme.outlineVariant)}!important; }
      .bm { border-radius:24px!important;overflow:hidden; } a { color:${cssColor(scheme.primary)}!important; }
      input:not([type=hidden]):not([type=checkbox]):not([type=radio]),textarea,select { background:${cssColor(scheme.surfaceContainerHigh)}!important;color:${cssColor(scheme.onSurface)}!important;border:1px solid ${cssColor(scheme.outline)}!important;border-radius:12px!important;min-height:48px!important;padding:8px 12px!important;box-sizing:border-box;max-width:100%!important;font-size:16px!important; }
      button,.pn,input[type=submit] { background:${cssColor(scheme.primary)}!important;color:${cssColor(scheme.onPrimary)}!important;border:0!important;border-radius:24px!important;min-height:48px!important;padding:8px 24px!important; }
      .pn span,.pn strong { background:none!important;color:inherit!important; } img { max-width:100%;height:auto; } table { max-width:100%; } .rfm { width:auto!important;margin:8px 0!important; } .rfm th { width:90px!important; } .rfm .px { width:100%!important; }
    ''';
    try {
      await controller.runJavaScript(
        '''(() => { let v=document.querySelector('meta[name="viewport"]');if(!v){v=document.createElement('meta');v.name='viewport';document.head.appendChild(v)}v.content='width=device-width, initial-scale=1';let s=document.getElementById('mt-m3');if(!s){s=document.createElement('style');s.id='mt-m3';document.head.appendChild(s)}s.textContent=${jsonEncode(css)}; })();''',
      );
    } catch (_) {
      /* Navigation may replace the document before styling finishes. */
    }
  }

  Future<void> back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    } else if (mounted) {
      setState(() => leaving = true);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || !canBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(back());
    },
    child: Scaffold(
      appBar: ReviewFrostedAppBar(
        title: Text(widget.title),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: back,
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: controller.reload,
            icon: const Icon(Icons.refresh),
          ),
          if (!widget.qqLogin)
            IconButton(
              tooltip: '浏览器打开',
              onPressed: () => openExternal(context, Uri.parse(widget.url)),
              icon: const Icon(Icons.open_in_browser),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (progress < 100) LinearProgressIndicator(value: progress / 100),
            if (error != null)
              MaterialBanner(
                content: Text(error!),
                actions: [
                  TextButton(
                    onPressed: controller.reload,
                    child: const Text('重试'),
                  ),
                ],
              ),
            Expanded(
              child: Offstage(
                offstage: authenticating,
                child: WebViewWidget(controller: controller),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// One on-demand WebView lets the website run its normal browser verification.
/// The bridge returns HTML only for our exact origin, never for external pages.
class BrowserReader {
  late final WebViewController controller;
  Completer<String>? _pending;
  Completer<String>? _loginPending;
  Future<void> _tail = Future.value();
  int _readRevision = 0, _loginAttempt = 0;
  bool _loginRequested = false;
  BrowserReader() {
    controller = WebViewController()
      ..setUserAgent(forumUserAgent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ForumLoginBridge',
        onMessageReceived: _receiveLoginMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              !r.isMainFrame ||
                  r.url == 'about:blank' ||
                  isForumUri(Uri.parse(r.url))
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onPageFinished: (url) async {
            if (!isForumUri(Uri.parse(url))) return;
            final login = _loginPending;
            if (login != null && !login.isCompleted) {
              await _finishLoginNavigation(login);
            }
            final pending = _pending;
            if (pending == null || pending.isCompleted) return;
            try {
              final result = await controller.runJavaScriptReturningResult(
                'document.documentElement.outerHTML',
              );
              final source = result is String && result.startsWith('"')
                  ? jsonDecode(result) as String
                  : result.toString();
              if (source.contains("var arg1=") &&
                  !source.contains('postmessage_')) {
                return;
              }
              if (identical(pending, _pending) && !pending.isCompleted) {
                pending.complete(source);
              }
            } catch (_) {
              if (!pending.isCompleted) {
                pending.completeError(const ForumFailure('网页验证未完成，请打开官网重试。'));
              }
            }
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && _pending?.isCompleted == false) {
              _pending!.completeError(const ForumFailure('官网连接失败，请检查网络。'));
            }
            final login = _loginPending;
            if (e.isForMainFrame == true &&
                login != null &&
                !login.isCompleted) {
              login.completeError(const ForumFailure('官网连接失败，请检查网络后重试。'));
            }
          },
        ),
      );
  }

  void _receiveLoginMessage(JavaScriptMessage message) {
    final pending = _loginPending;
    if (pending == null || pending.isCompleted) return;
    try {
      final payload = Map<String, dynamic>.from(
        jsonDecode(message.message) as Map,
      );
      if (payload['attempt'] != _loginAttempt) return;
      final text = (payload['message'] as String? ?? '').trim();
      if (payload['success'] == true) {
        pending.complete(text.isEmpty ? '登录成功' : text);
      } else {
        pending.completeError(
          ForumFailure(text.isEmpty ? '登录未成功，请核对账号信息后重试。' : text),
        );
      }
    } catch (_) {
      pending.completeError(const ForumFailure('登录响应无法识别，请重试。'));
    }
  }

  Future<void> _finishLoginNavigation(Completer<String> pending) async {
    try {
      final raw = await controller.runJavaScriptReturningResult('''(() => {
        const node=document.querySelector('#messagetext,[id^="returnmessage_"]');
        return (node?.innerText || '').trim();
      })()''');
      final value = raw is String && raw.startsWith('"')
          ? jsonDecode(raw) as String
          : raw.toString();
      if (value.isNotEmpty) {
        if (RegExp(r'欢迎您回来|登录成功|已登录').hasMatch(value)) {
          pending.complete(value);
        } else if (!value.contains('正在提交') && !value.contains('请稍候')) {
          pending.completeError(ForumFailure(value));
        }
      }
    } catch (_) {
      /* A navigation may replace the login document before its message is readable. */
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final job = _tail.then((_) => action());
    _tail = job.then<void>((_) {}, onError: (Object _) {});
    return job;
  }

  Future<String> read(Uri uri) {
    final revision = _readRevision;
    return _enqueue(() {
      if (revision != _readRevision) {
        throw const ForumFailure('正在登录，页面读取已取消，请稍后刷新。');
      }
      return _read(uri);
    });
  }

  Future<String> _read(
    Uri uri, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final pending = _pending = Completer<String>();
    try {
      final result =
          await Future.wait<Object?>([
            controller.loadRequest(uri),
            pending.future,
          ], eagerError: true).timeout(
            timeout,
            onTimeout: () => throw const ForumFailure('网站验证超时，请打开官网完成验证后重试。'),
          );
      return result[1] as String;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<String> login({
    required String loginField,
    required String username,
    required String password,
    required int questionId,
    required String answer,
    required bool remember,
  }) {
    if (_loginRequested) {
      return Future.error(const ForumFailure('已有登录请求正在处理，请稍候或取消。'));
    }
    _loginRequested = true;
    final attempt = ++_loginAttempt;
    _readRevision++;
    final reading = _pending;
    if (reading != null && !reading.isCompleted) {
      reading.completeError(const ForumFailure('正在登录，页面读取已取消，请稍后刷新。'));
    }
    return _enqueue(() async {
      if (attempt != _loginAttempt) throw const ForumFailure('登录已取消。');
      try {
        return await _submitLogin(
          attempt: attempt,
          loginField: loginField,
          username: username,
          password: password,
          questionId: questionId,
          answer: answer,
          remember: remember,
        ).timeout(
          const Duration(seconds: 35),
          onTimeout: () => throw const ForumFailure('登录响应超时，请检查网络后重试。'),
        );
      } finally {
        if (attempt == _loginAttempt) await cancelLogin();
      }
    });
  }

  Future<String> _submitLogin({
    required int attempt,
    required String loginField,
    required String username,
    required String password,
    required int questionId,
    required String answer,
    required bool remember,
  }) async {
    await controller
        .runJavaScript('window.stop();')
        .timeout(const Duration(seconds: 3));
    final page = await _read(
      forumUri('member.php?mod=logging&action=login'),
      timeout: const Duration(seconds: 15),
    );
    if (attempt != _loginAttempt) throw const ForumFailure('登录已取消。');
    if (!page.contains('loginform_') || !page.contains('name="password"')) {
      if (page.contains('欢迎您回来')) return '当前账号已登录';
      throw const ForumFailure('论坛没有返回可用的登录表单，请检查网络或网站验证状态。');
    }
    final script = await rootBundle.loadString('assets/forum-login.js');
    if (attempt != _loginAttempt) throw const ForumFailure('登录已取消。');
    final pending = _loginPending = Completer<String>();
    pending.future.ignore();
    final payload = jsonEncode({
      'attempt': attempt,
      'loginField': loginField,
      'username': username,
      'password': password,
      'questionId': questionId,
      'answer': answer,
      'remember': remember,
    });
    await controller
        .runJavaScript('$script($payload);')
        .timeout(const Duration(seconds: 5));
    return pending.future;
  }

  Future<void> cancelLogin() async {
    if (!_loginRequested) return;
    _loginAttempt++;
    final reading = _pending;
    if (reading != null && !reading.isCompleted) {
      reading.completeError(const ForumFailure('登录已取消。'));
    }
    final login = _loginPending;
    if (login != null && !login.isCompleted) {
      login.completeError(const ForumFailure('登录已取消。'));
    }
    _loginPending = null;
    try {
      await controller
          .runJavaScript('window.__mtForumLoginCleanup?.();')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // The document may already have navigated away.
    }
    try {
      await controller
          .runJavaScript('window.stop();')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // A renderer failure must not leave the native form spinning.
    }
    _loginRequested = false;
  }

  Future<void> resetSession() async {
    await cancelLogin();
    _readRevision++;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const ForumFailure('账号已退出。'));
    }
    await controller
        .runJavaScript('window.stop();')
        .timeout(const Duration(seconds: 2));
    await controller
        .loadHtmlString('<html><body></body></html>')
        .timeout(const Duration(seconds: 2));
  }
}
