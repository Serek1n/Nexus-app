/// Убирает из текста всё, что даёт доступ к серверам: ключи-ссылки,
/// UUID, пароли и пути ссылок подписок (в них токен). Адреса серверов
/// остаются — по ним поддержка поймёт, с каким сервером беда.
String redactSecrets(String text) {
  var t = text;
  t = t.replaceAll(
      RegExp(r'\b(vless|vmess|trojan|ss|socks|hysteria2?|hy2?)://\S+',
          caseSensitive: false),
      '<ключ скрыт>');
  t = t.replaceAllMapped(RegExp(r'\bhttps?://([^/\s:]+)(:\d+)?\S*'),
      (m) => 'https://${m[1]}${m[2] ?? ''}/…');
  t = t.replaceAll(
      RegExp(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'),
      '<uuid>');
  t = t.replaceAllMapped(
      RegExp(r'\b(password|pass|auth|pbk|sid|obfs-password|token)=([^&\s;,]+)',
          caseSensitive: false),
      (m) => '${m[1]}=<скрыто>');
  return t;
}
