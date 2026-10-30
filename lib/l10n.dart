import 'l10n_en.dart';

/// Язык интерфейса: русский (исходные строки) или английский.
class L10n {
  /// 'ru' или 'en' — уже выбранный (с учётом «как в системе»).
  static String lang = 'ru';
  static bool get en => lang == 'en';

  /// [setting] — 'system', 'ru' или 'en'; [system] — код языка системы.
  static void apply(String setting, String system) {
    lang = switch (setting) {
      'ru' => 'ru',
      'en' => 'en',
      // Русскоязычным и соседям — русский, остальным — английский.
      _ => const ['ru', 'uk', 'be', 'kk', 'ky', 'uz', 'tg']
              .contains(system)
          ? 'ru'
          : 'en',
    };
  }
}

/// Перевод строки интерфейса. Ключ — русский текст; {0}, {1}… — места
/// для [args]. Нет перевода — показываем русский.
String tr(String ru, [List<Object?> args = const []]) {
  var s = L10n.en ? (kEn[ru] ?? ru) : ru;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
