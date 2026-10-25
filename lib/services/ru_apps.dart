import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Российские приложения, которые в «Умном режиме» на Android работают
/// мимо VPN: они не видят туннель и ходят в интернет напрямую.
/// Если приложение не установлено, система просто пропускает его.
///
/// Источники: жалобы пользователей и проверки (Rozetked, iGuides, Mail.ru,
/// Android Insider, апрель–октябрь 2026), анализ RKS Global «VPN-детекция
/// в 30 российских приложениях», списки ZorroJan/vpn-blocked-apps-tracker-ru
/// и zuboleo/split-tunnel-apps. Последний дополнительно подгружается
/// при запуске, поэтому список пополняется без обновления Nexus.
const ruBypassApps = <String, String>{
  // ── Госсервисы ──
  'ru.rostel': 'Госуслуги',
  'ru.gosuslugi.goskey': 'Госключ',
  'ru.gosuslugi.culture': 'Госуслуги Культура',
  'ru.gosuslugi.school': 'Госуслуги Моя школа',
  'ru.fns.lkfl': 'Налоги ФЛ',
  'com.gnivts.selfemployed': 'Мой налог',
  'com.octopod.russianpost.client.android': 'Почта России',
  'ru.mosgorpass': 'Мосметро / Тройка',

  // ── Банки и платежи ──
  'ru.sberbankmobile': 'СберБанк Онлайн',
  'com.idamob.tinkoff.android': 'Т-Банк',
  'ru.tinkoff.mb': 'Т-Банк (новая версия)',
  'ru.vtb24.mobilebanking.android': 'ВТБ Онлайн',
  'ru.alfabank.mobile.android': 'Альфа-Банк',
  'ru.raiffeisennews': 'Райффайзенбанк',
  'ru.gazprombank.android.mobilebank.app': 'Газпромбанк',
  'ru.letobank.Prometheus': 'Почта Банк',
  'ru.sovcomcard.halva.v1': 'Халва — Совкомбанк',
  'ru.otpbank.mobile': 'ОТП Банк',
  'ru.rshb.dbo': 'Россельхозбанк',
  'ru.ozon.fintech.finance': 'Ozon Банк',
  'ru.wildberries.bank': 'WB Банк',
  'com.yandex.bank': 'Яндекс Пэй',
  'ru.nspk.mirpay': 'Mir Pay',
  'ru.nspk.sbpay': 'СБПэй',
  'ru.yoo.money': 'ЮMoney',

  // ── VK и Mail ──
  'com.vkontakte.android': 'ВКонтакте',
  'com.vk.im': 'VK Мессенджер',
  'com.vk.vkvideo': 'VK Видео',
  'com.uma.musicvk': 'VK Музыка',
  'ru.ok.android': 'Одноклассники',
  'ru.oneme.app': 'MAX',
  'ru.vk.store': 'RuStore',
  'ru.mail.mailapp': 'Почта Mail',
  'ru.mail.cloud': 'Облако Mail',
  'ru.zen.android': 'Дзен',

  // ── Яндекс ──
  'ru.yandex.searchplugin': 'Яндекс с Алисой',
  'com.yandex.browser': 'Яндекс Браузер',
  'ru.yandex.taxi': 'Яндекс Go',
  'ru.yandex.yandexmaps': 'Яндекс Карты',
  'ru.yandex.yandexnavi': 'Яндекс Навигатор',
  'ru.yandex.weatherplugin': 'Яндекс Погода',
  'ru.yandex.music': 'Яндекс Музыка',
  'ru.kinopoisk': 'Кинопоиск',
  'ru.kinopoisk.tv': 'Кинопоиск (ТВ)',
  'ru.beru.android': 'Яндекс Маркет',
  'ru.yandex.mail': 'Яндекс Почта',
  'ru.yandex.disk': 'Яндекс Диск',
  'ru.foodfox.client': 'Яндекс Еда',

  // ── Маркетплейсы и магазины ──
  'ru.ozon.app.android': 'Ozon',
  'com.wildberries.ru': 'Wildberries',
  'com.avito.android': 'Авито',
  'ru.avito': 'Авито (новая версия)',
  'ru.megamarket.marketplace': 'МегаМаркет',
  'com.kazanexpress.ke_app': 'Магнит Маркет',
  'ru.aliexpress.buyer': 'AliExpress',
  'com.lamoda.lite': 'Lamoda',
  'ru.cian.main': 'Циан',
  'ru.sbcs.store': 'Самокат',
  'ru.vkusvill': 'ВкусВилл',
  'ru.instamart': 'Купер',
  'ru.detmir.dmbonus': 'Детский мир',
  'ru.tander.magnit': 'Магнит',
  'ru.pyaterochka.app.browser': 'Пятёрочка',
  'ru.perekrestok.app': 'Перекрёсток',
  'ru.myauchan.droid': 'Ашан',
  'ru.dns.shop.android': 'DNS',
  'ru.sportmaster.app': 'Спортмастер',
  'ru.ostin.android.app': "O'STIN",
  'ru.usmall.app': 'USmall',
  'com.apteka.sklad': 'Аптека Склад',
  'ru.kfc.kfc_delivery': 'Rostic’s',
  'ru.dodopizza.app': 'Додо Пицца',

  // ── Кино, музыка, книги ──
  'ru.rutube.app': 'RUTUBE',
  'ru.ivi.client': 'Иви',
  'ru.more.play': 'Okko',
  'ru.rt.video.app.mobile': 'Wink',
  'tv.lfstrm.smotreshka': 'Смотрёшка',
  'ru.litres.android': 'Литрес',

  // ── Транспорт и путешествия ──
  'ru.rzd.pass': 'РЖД Пассажирам',
  'ru.aviasales': 'Aviasales',
  'ru.tutu.avia': 'Туту',
  'ru.s7tl.app': 'S7 Airlines',
  'ru.dublgis.dgismobile': '2ГИС',

  // ── Работа, сервисы ──
  'ru.hh.android': 'hh.ru',
  'ru.briscloud': 'Брис (ЖКХ)',
  'com.myhousereactnativemigration': 'Мой дом',
  'io.itforces.android.timetable': 'Расписание',
  'ru.desport.android': 'Д-Спорт',

  // ── Операторы связи ──
  'ru.mts.mymts': 'Мой МТС',
  'ru.megafon.mlk': 'МегаФон',
  'ru.beeline.services': 'Билайн',
  'ru.tele2.mytele2': 't2',
  'ru.yota.android': 'Yota',
  'ru.rt.smarthome': 'Ростелеком',
};

/// Автообновляемый список (zuboleo/split-tunnel-apps): приложения, для которых
/// подтверждён конфликт с включённым VPN.
class RuAppsUpdater {
  static const _url =
      'https://raw.githubusercontent.com/zuboleo/split-tunnel-apps/main/public/direct_apps.txt';
  static const _key = 'ruAppsRemote';
  static const _keyAt = 'ruAppsRemoteAt';

  /// Корректное имя пакета Android.
  static final _pkg = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+){1,8}$');

  static List<String> _cached = const [];

  /// Пакеты из встроенного списка + подгруженные.
  static Set<String> get all => {...ruBypassApps.keys, ..._cached};

  static bool isRemoteOnly(String pkg) =>
      !ruBypassApps.containsKey(pkg) && _cached.contains(pkg);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _cached = p.getStringList(_key) ?? const [];
  }

  /// Обновляет список не чаще раза в сутки. Ошибки сети не мешают работе.
  static Future<void> refresh() async {
    final p = await SharedPreferences.getInstance();
    final at = p.getInt(_keyAt) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at <
        const Duration(hours: 20).inMilliseconds) {
      return;
    }
    try {
      final res = await http
          .get(Uri.parse(_url), headers: {'User-Agent': 'Nexus'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200 || res.bodyBytes.length > 64 * 1024) return;
      final list = utf8
          .decode(res.bodyBytes, allowMalformed: true)
          .split(RegExp(r'[\s,]+'))
          .map((e) => e.trim())
          .where(_pkg.hasMatch)
          .toSet()
          .take(500)
          .toList();
      if (list.isEmpty) return;
      _cached = list;
      await p.setStringList(_key, list);
      await p.setInt(_keyAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }
}
