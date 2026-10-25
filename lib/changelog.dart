import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/theme.dart';

/// Текущая версия приложения (передаётся сборкой).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.8.3');

/// Список изменений. Новая версия — сверху, пункты — коротко.
/// Отсюда же CI берёт текст для описания релиза на GitHub.
const changelog = <(String, List<String>)>[
  ('1.8.3', [
    'Список изменений в приложении',
    'Что нового — перед установкой обновления',
  ]),
  ('1.8.2', [
    'Автопереподключение при обрыве',
    'Проверка канала каждые 45 с',
    'Keep-alive и IPv4 до сервера',
    'Настройка «Держать соединение»',
  ]),
  ('1.8.1', [
    'Честный пинг для Hysteria2 и UDP',
    'Убрана версия Xray из обновлений',
  ]),
  ('1.8.0', [
    'Избранные серверы',
    'Автовыбор сервера при сбое',
    'Подписанные обновления',
    'Исправления безопасности',
  ]),
  ('1.7.0', [
    'Российские приложения мимо VPN',
    'Автообновление приложения',
    'Kill switch на Windows',
  ]),
  ('1.6.0', [
    'Работа в трее и автозапуск',
    'Шифрование ключей на устройстве',
    'Автообновление Xray',
  ]),
];

/// Пункты для указанной версии (пусто, если версии нет в списке).
List<String> notesFor(String version) =>
    changelog.where((e) => e.$1 == version).firstOrNull?.$2 ?? const [];

/// Показывает «Что нового» один раз после обновления.
Future<void> showWhatsNewIfUpdated(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getString('seenVersion');
  await prefs.setString('seenVersion', appVersion);
  // Первая установка — не показываем; обновление — показываем.
  if (seen == null || seen == appVersion || notesFor(appVersion).isEmpty) {
    return;
  }
  if (context.mounted) showChangelog(context, onlyCurrent: true);
}

/// Окно со списком изменений.
void showChangelog(BuildContext context, {bool onlyCurrent = false}) {
  final items = onlyCurrent
      ? changelog.where((e) => e.$1 == appVersion).toList()
      : changelog;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
      child: Container(
        decoration: const BoxDecoration(
          color: NX.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: NX.strokeStrong)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      onlyCurrent ? 'Обновлено до $appVersion' : 'Что нового',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: NX.text2),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  children: [
                    for (final (ver, notes) in items) ...[
                      if (!onlyCurrent)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 6),
                          child: Row(children: [
                            Text(ver,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5)),
                            if (ver == appVersion) ...[
                              const SizedBox(width: 8),
                              const Text('· текущая',
                                  style: TextStyle(
                                      color: NX.mint,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ]),
                        ),
                      ChangeList(notes),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Пункты изменений маркированным списком.
class ChangeList extends StatelessWidget {
  const ChangeList(this.notes, {super.key});
  final List<String> notes;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7, right: 10),
                    child: CircleAvatar(radius: 2.5, backgroundColor: NX.violet),
                  ),
                  Expanded(
                    child: Text(n,
                        style: const TextStyle(
                            color: NX.text2, fontSize: 13.5, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      );
}
