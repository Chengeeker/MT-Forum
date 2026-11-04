import 'package:flutter/material.dart';

void showAccountStatus(ScaffoldMessengerState messenger, String message) {
  if (!messenger.mounted) return;
  messenger
    ..clearSnackBars()
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
}
