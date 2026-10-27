import 'package:flutter/material.dart';

import '../../data/forum.dart';

class ForumAvatar extends StatelessWidget {
  const ForumAvatar({super.key, this.url, this.radius = 18});
  final String? url;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(url ?? '');
    Widget fallback() => Image.asset(
      'assets/forum-default-avatar.gif',
      width: radius * 2,
      height: radius * 2,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child:
            uri == null ||
                uri.scheme != 'https' ||
                uri.userInfo.isNotEmpty ||
                RegExp(r'/noavatar_(small|middle|big)\.gif$').hasMatch(uri.path)
            ? fallback()
            : Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                headers: forumMediaHeaders(uri),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}
