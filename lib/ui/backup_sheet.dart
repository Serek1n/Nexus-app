import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'share_sheet.dart';
import 'theme.dart';
import '../l10n.dart';

/// Создание резервной копии: пароль дважды → строка для копирования.
Future<void> showBackupExport(BuildContext context) async {
  final pw = await _askPassword(context, confirm: true);
  if (pw == null || !context.mounted) return;
  final app = AppScope.read(context);
  try {
    final text = await _busy(context, app.exportBackup(pw));
    if (!context.mounted) return;
    await showShareSheet(
      context,
      title: tr('Резервная копия'),
      text: text,
      warning: tr('Сохраните строку в заметках или отправьте себе. Чтобы восстановить: «Добавить» → вставить её → ввести пароль. Без пароля копию не открыть — его нельзя восстановить.'),
    );
  } catch (e) {
    if (context.mounted) toast(context, _msg(e), error: true);
  }
}

/// Восстановление из строки резервной копии. Возвращает текст результата
/// или null, если пользователь передумал.
Future<String?> restoreBackup(BuildContext context, String text) async {
  final pw = await _askPassword(context, confirm: false);
  if (pw == null || !context.mounted) return null;
  return _busy(context, AppScope.read(context).importBackup(text, pw));
}

String _msg(Object e) {
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// Ожидание с индикатором (шифрование занимает секунду-другую).
Future<T> _busy<T>(BuildContext context, Future<T> f) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    return await f;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

Future<String?> _askPassword(BuildContext context, {required bool confirm}) {
  final a = TextEditingController(), b = TextEditingController();
  String? err;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(confirm ? tr('Пароль для копии') : tr('Пароль от копии')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (confirm)
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                    tr('В копии — ваши подписки и ключи серверов. Придумайте пароль не короче 6 символов.'),
                    style: TextStyle(color: NX.text2, fontSize: 13)),
              ),
            TextField(
              controller: a,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(hintText: tr('Пароль')),
            ),
            if (confirm) ...[
              const SizedBox(height: 10),
              TextField(
                controller: b,
                obscureText: true,
                decoration: InputDecoration(hintText: tr('Ещё раз')),
              ),
            ],
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(err!,
                    style: const TextStyle(color: NX.red, fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Отмена'))),
          TextButton(
            onPressed: () {
              if (a.text.length < 6) {
                set(() => err = tr('Не короче 6 символов'));
                return;
              }
              if (confirm && a.text != b.text) {
                set(() => err = tr('Пароли не совпадают'));
                return;
              }
              Navigator.pop(ctx, a.text);
            },
            child: Text(confirm ? tr('Создать') : tr('Восстановить')),
          ),
        ],
      ),
    ),
  );
}
