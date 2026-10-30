// Перевод интерфейса: в английских строках те же места {0}, {1}…, что и в русских.
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/l10n.dart';
import 'package:nexus/l10n_en.dart';

void main() {
  test('места для значений совпадают', () {
    final re = RegExp(r'\{\d+\}');
    for (final e in kEn.entries) {
      final a = re.allMatches(e.key).map((m) => m[0]).toSet();
      final b = re.allMatches(e.value).map((m) => m[0]).toSet();
      expect(b, a, reason: e.key);
    }
  });

  test('переключение языка и подстановка', () {
    L10n.apply('en', 'ru');
    expect(tr('Подключить'), 'Connect');
    expect(tr('Выбран: {0}', ['X']), 'Selected: X');
    expect(tr('строка без перевода'), 'строка без перевода');
    L10n.apply('ru', 'en');
    expect(tr('Выбран: {0}', ['X']), 'Выбран: X');
    L10n.apply('system', 'de');
    expect(L10n.en, isTrue);
    L10n.apply('system', 'uk');
    expect(L10n.en, isFalse);
  });
}
