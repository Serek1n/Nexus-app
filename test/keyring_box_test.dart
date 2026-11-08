import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/platform/keyring_box.dart';

void main() {
  test('шифрование подписок ключом из связки ключей', () async {
    KeyringBox.debugKey = List<int>.generate(32, (i) => i * 5 % 256);
    const plain = '[{"url":"https://sub.example.com/s/Abc","title":"Тест"}]';
    final enc = await KeyringBox.protect(plain);
    expect(KeyringBox.isProtected(enc), isTrue);
    expect(enc.contains('sub.example.com'), isFalse);
    expect(await KeyringBox.unprotect(enc), plain);
    // Каждый раз новый nonce — одинаковый текст шифруется по-разному.
    expect(await KeyringBox.protect(plain), isNot(enc));
    // Старые незашифрованные данные читаются как есть.
    expect(await KeyringBox.unprotect(plain), plain);
    // Повреждённые данные — null (ничего не перезаписываем).
    expect(await KeyringBox.unprotect('${enc.substring(0, enc.length - 4)}AAAA'), isNull);
    KeyringBox.debugKey = List<int>.filled(32, 7);
    expect(await KeyringBox.unprotect(enc), isNull);
    KeyringBox.debugKey = null;
  });
}
