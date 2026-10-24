import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Доступ к AppState из любого виджета с автоматической перерисовкой.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

void toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              size: 18,
              color: error ? const Color(0xFFFF4D6D) : const Color(0xFF2EF2B5)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
      duration: Duration(seconds: error ? 5 : 3),
    ));
}
