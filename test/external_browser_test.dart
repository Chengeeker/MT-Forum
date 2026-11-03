import 'package:flutter_test/flutter_test.dart';
import 'package:mt_forum/pages/web_page.dart';

void main() {
  test('only credential-free HTTP(S) destinations use the in-app browser', () {
    expect(supportsInAppBrowserUri(Uri.parse('https://mt.cc/guide/')), isTrue);
    expect(supportsInAppBrowserUri(Uri.parse('http://example.com')), isTrue);
    expect(
      supportsInAppBrowserUri(Uri.parse('mailto:test@example.com')),
      isFalse,
    );
    expect(supportsInAppBrowserUri(Uri.parse('javascript:alert(1)')), isFalse);
    expect(
      supportsInAppBrowserUri(Uri.parse('https://user:pass@example.com')),
      isFalse,
    );
    expect(supportsInAppBrowserUri(Uri.parse('https:///path')), isFalse);
  });
}
