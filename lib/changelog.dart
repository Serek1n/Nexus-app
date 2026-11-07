import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'ui/theme.dart';

/// Текущая версия приложения (передаётся сборкой).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '2.4.0');

/// Сборка из ветки beta (передаётся сборкой).
const isBetaBuild = String.fromEnvironment('APP_CHANNEL') == 'beta';

/// Версия для показа: «2.2.0» у релиза, «2.2.0 beta 133» у беты.
const appVersionLabel = isBetaBuild
    ? '$appVersion beta ${const int.fromEnvironment('APP_BUILD')}'
    : appVersion;

/// Список изменений. Новая версия — сверху, пункты — коротко.
/// Отсюда же CI берёт текст для описания релиза на GitHub.
const changelog = <(String, List<String>)>[
  ('2.4.0', [
    'Режим «Только заблокированное»: через VPN — YouTube, Instagram, Discord, Telegram, ИИ-сервисы; остальное напрямую',
    'Вход по PIN-коду: без него никто не увидит ключи и подписки',
    'Светлая тема (или как в системе)',
    'Карта на главной: где ваш сервер',
    'Маскировка соединения: «Надёжная» или «Быстрая» (в 4 раза быстрее открывает соединения)',
    'Ссылки «Открыть в Happ / Hiddify / v2rayNG / Clash» теперь добавляются и в Nexus',
    'Запасные адреса подписки — если основной заблокируют',
    'Одна подписка больше не добавляется дважды (ссылки с «хвостом» Happ)',
    'Android: ярлыки на значке (долгое нажатие) — «Подключить», «Режим Авто», «Проверка связи»',
    'Android TV: Nexus в меню телевизора, управление пультом',
    'Android: на экранах с ключами и QR-кодами запрещены скриншоты',
    'Windows: Ctrl+Alt+N — подключить/отключить из любой программы',
    'Windows: проверка скорости всех серверов',
    'Windows (TUN): с правами администратора запускается только проверенное ядро из защищённой папки',
    'Задержки после запуска меряются, когда подключение уже завершилось — без завышенных цифр',
    'Карта приближена к серверу, плавно переезжает при смене сервера и почти не тратит батарею',
    'PIN: пауза после ошибок сохраняется и после перезапуска Nexus; PIN не попадает в резервную копию',
    'Запасные адреса из ссылки показываются в окне подтверждения',
    'Windows: проверку скорости всех серверов можно остановить',
  ]),
  ('2.3.1', [
    'Убрано «Включать VPN в чужих Wi-Fi» — Nexus больше не просит доступ к геолокации',
  ]),
  ('2.3.0', [
    'Задержки серверов меряются сами после запуска — без «— мс» в списке',
    'Смена сети (Wi-Fi ↔ мобильная): связь возвращается примерно на 10 секунд быстрее',
    'Нет сети — Nexus ждёт её и подключается сразу, как только интернет появится',
    'Скопированные ключи и подписки через 2 минуты пропадают из буфера, Android не показывает их в подсказках клавиатуры',
    'Пароль новой резервной копии — от 8 символов',
    'В фоне Nexus реже проверяет Wi-Fi — меньше расход батареи',
    'Дизайн: единый стиль переключателей и кнопок выбора, ровные отступы в настройках',
    'Избранные серверы на главной больше не обрезаются, у безлимитной подписки — своя полоса',
    'Красная кнопка «Сбросить всё», знак Nexus на первом экране, на ПК выровнены заголовки списка серверов',
    '«Обход блокировок» теперь называется «Маскировка соединения»',
  ]),
  ('2.2.0', [
    'Android: «Постоянная VPN» больше не оставляет без интернета',
    'Проверка связи: найдёт, что именно не работает',
    'Выбор DNS: Cloudflare, Google, Quad9 или AdGuard без рекламы',
    'Избранные серверы на главной — переключение одним касанием',
    'Подписка, которая не обновляется, отмечена — с причиной в подсказке',
    'Ядро Xray 26.10.31 на Android и Windows',
    'Повторные нажатия «Подключить» больше не запускают ядро дважды',
    'В фоне Nexus реже будит телефон — меньше расход батареи',
    'Обновление приложения не зависает при обрыве загрузки',
    'Защита ссылок nexus://: видно адрес сервера, предупреждение о ссылках без шифрования',
  ]),
  ('2.1.0', [
    'Первый запуск: подсказки по шагам',
    'VPN сам включается в чужих сетях Wi-Fi',
    'Кнопка «Продлить» — сразу в бота или кабинет',
    'Серверы можно исключить из режима «Авто»',
    'Android: видно, какой сервер выбрал «Авто»',
    'WireGuard и подписки в форматах sing-box и Clash',
    'Windows: программы через VPN или напрямую',
    'SOCKS-прокси с паролем (Windows и Android в режиме прокси)',
    'Бета-версии для желающих',
    'Статистика ядра закрыта паролем',
    'Трафик больше не считается дважды',
  ]),
  ('2.0.0', [
    'Режим «Авто»: всегда самый быстрый сервер, без обрывов',
    'Обход блокировок: Nexus сложнее распознать',
    'DNS только зашифрованный (DNS-over-HTTPS)',
    'Статистика трафика по дням и месяцам',
    'Резервная копия подписок и настроек под паролем',
    'Английский язык интерфейса',
    'Android: плитка и виджет подключают без открытия Nexus',
    'Android: напоминание за 3 дня и за день до конца подписки',
    'Windows: «Авто» в меню трея и текущий сервер на главной',
  ]),
  ('1.9.9', [
    'Предупреждение, если трафик идёт мимо VPN',
    'Тест скорости через текущий сервер — на главной',
    'Блокировка рекламы и трекеров',
    'Android: плитка Nexus в шторке уведомлений',
    'Android: подписки грузятся через VPN, если сайт заблокирован',
    'Подписки по http загружаются через VPN',
    'Android 12+: данные не переносятся на другой телефон',
  ]),
  ('1.9.8', [
    'Свои правила: сайты через VPN или напрямую',
    'Windows: автозапуск с режимом TUN',
    'Задержка: зелёный до 350 мс, жёлтый до 700',
    'Исправлен QR-код при «Поделиться»',
    'Windows: исправлена ошибка «StreamSink is bound to a stream»',
  ]),
  ('1.9.7', [
    'Windows: режим TUN — все программы через Nexus',
    'Telegram подключается одной кнопкой',
    'В журнале видно, идёт ли трафик через сервер',
    'Подписки с лимитом устройств загружаются',
    'Умный режим: YouTube, TikTok, Instagram всегда через VPN',
    'Android: VPN корректно отключается, интернет не пропадает',
    'Поделиться подпиской или сервером через QR-код',
  ]),
  ('1.9.6', [
    'Android 8–12: статус VPN нельзя подделать',
    'Не спорит с другим VPN за подключение',
    'Подсказки на главной без жёлтой заливки',
    'Честная задержка: зелёный до 350 мс, жёлтый до 700, красный дальше',
  ]),
  ('1.9.5', [
    'Android: Hysteria2 подключается',
    'Нет бесконечных попыток: другой сервер или ошибка',
  ]),
  ('1.9.4', [
    'Постоянная подпись APK — обновления ставятся поверх',
    'Понятная ошибка, если ключ подписи сменился',
    'Обновление скачивается только по кнопке «Установить»',
  ]),
  ('1.9.3', [
    'Исправлено бесконечное «Подключение…»',
    'Нет лишних переподключений после обновления подписки',
    'Режим маршрутизации — только в настройках',
    'Подсказка про батарею — уведомлением',
    'Разделители в настройках стали тёмными',
  ]),
  ('1.9.2', [
    'Windows: проверка сотен серверов в разы быстрее',
    'Прогресс проверки и счётчик неотвечающих',
    'Фильтр «Только рабочие»',
    'Проверка задержки отдельной подписки',
    'Свои названия серверов',
    'Задержки не сбрасываются при обновлении подписки',
  ]),
  ('1.9.1', [
    'Подписки обновляются при подключении VPN',
    'Новый ключ сервера — автопереподключение',
  ]),
  ('1.9.0', [
    'Флаг страны по названию сервера',
    'Транспорт и адрес в списке серверов',
    'Название подписки по её адресу',
    'Быстрый список на сотни серверов',
    'Windows: запасные порты, если 10808 занят',
    'Подписка грузится через VPN, если сайт заблокирован',
    'Журнал не хранит посещённые сайты',
    'Откат на прошлую версию',
  ]),
  ('1.8.9', [
    'Проверка канала после сна устройства',
    'Подключение не зависает дольше 30 с',
    'Android: подсказка про экономию батареи',
    'Итог прошлой сессии на главной',
    'Защита загрузки подписок от переполнения',
    'Исправлено «нет связи» у VLESS Reality с pqv',
    'Серверы: фильтр по подпискам и сворачиваемые группы',
  ]),
  ('1.8.8', [
    'Android: добавление по QR-коду',
    'Поддержка ech, fm и XHTTP-параметров из 3x-ui',
  ]),
  ('1.8.7', [
    'Флаги стран вместо букв',
  ]),
  ('1.8.6', [
    'Быстрая реакция на смену сети',
    'Проверка канала: повтор через 10 с',
    'Windows: возврат вашего прежнего прокси',
    'Трей: выбор сервера и умный режим',
    'Задержка в виде индикатора сигнала',
    'Цветные метки стран на Windows',
    'Защита проверочного прокси паролем',
  ]),
  ('1.8.5', [
    'Hysteria2: obfs, alpn и смена портов из 3x-ui',
    'Причина «нет связи» видна в журнале',
    'Новая иконка на панели задач',
  ]),
  ('1.8.4', [
    'Новый логотип и иконка',
    'Новый значок в трее',
    'Обновление показывает, до какой версии',
    'Исправлено «нет связи» у серверов с доменом',
  ]),
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

/// Английский текст изменений последних версий (у старых — русский).
const changelogEn = <String, List<String>>{
  '2.4.0': [
    '"Blocked only" mode: YouTube, Instagram, Discord, Telegram and AI services via VPN; everything else directly',
    'PIN lock: nobody sees your keys and subscriptions without it',
    'Light theme (or follow the system)',
    'Map on the home screen: where your server is',
    'Connection masking: "Reliable" or "Fast" (opens connections 4× faster)',
    '"Open in Happ / Hiddify / v2rayNG / Clash" links now work in Nexus too',
    'Backup subscription addresses — in case the main one gets blocked',
    'The same subscription is no longer added twice (links with a Happ "tail")',
    'Android: app shortcuts (long press) — "Connect", "Auto mode", "Connection check"',
    'Android TV: Nexus in the TV menu, remote control navigation',
    'Android: screenshots are blocked on screens with keys and QR codes',
    'Windows: Ctrl+Alt+N — connect/disconnect from any program',
    'Windows: speed test of all servers',
    'Windows (TUN): with administrator rights only the verified core runs, from a protected folder',
    'Latencies after launch are measured once the connection has finished — no inflated numbers',
    'The map zooms in on the server, glides when you switch servers and barely uses battery',
    'PIN: the pause after wrong attempts survives restarting Nexus; the PIN is not included in backups',
    'Backup addresses from a link are shown in the confirmation window',
    'Windows: the speed test of all servers can be stopped',
  ],
  '2.3.1': [
    'Removed "Turn on VPN in unknown Wi-Fi" — Nexus no longer asks for location access',
  ],
  '2.3.0': [
    'Server latencies are measured automatically after launch — no more "— ms" in the list',
    'Network change (Wi-Fi ↔ mobile): connection comes back about 10 seconds faster',
    'No network — Nexus waits and connects as soon as the internet is back',
    'Copied keys and subscriptions disappear from the clipboard after 2 minutes; Android hides them from keyboard suggestions',
    'New backups need a password of at least 8 characters',
    'In the background Nexus checks Wi-Fi less often — better battery life',
    'Design: one style for switches and choice buttons, even spacing in settings',
    'Favorite servers on the home screen are no longer cut off; unlimited subscriptions get their own bar',
    'Red "Reset everything" button, Nexus mark on the first screen, aligned server list headers on PC',
    '"Bypass blocking" is now called "Connection masking"',
  ],
  '2.2.0': [
    'Android: "Always-on VPN" no longer leaves you without internet',
    "Connection check: finds exactly what's broken",
    'DNS choice: Cloudflare, Google, Quad9 or ad-free AdGuard',
    'Favorite servers on the home screen — switch with one tap',
    'A subscription that fails to update is marked, with the reason in a tooltip',
    'Xray core 26.10.31 on Android and Windows',
    'Repeated "Connect" taps no longer start the core twice',
    'Nexus wakes the phone less often in the background — better battery life',
    'App updates no longer hang when a download stalls',
    'Safer nexus:// links: server address shown, warning for unencrypted links',
  ],
  '2.1.0': [
    'First launch: step-by-step tips',
    'VPN turns on by itself in unknown Wi-Fi networks',
    '“Renew” button — straight to the bot or your account',
    'Servers can be excluded from Auto mode',
    'Android: see which server Auto picked',
    'WireGuard and sing-box / Clash subscriptions',
    'Windows: choose programs that go via VPN or direct',
    'Password-protected SOCKS proxy (Windows, Android proxy mode)',
    'Beta versions for those who want them',
    'Core statistics are password-protected',
    'Traffic is no longer counted twice',
  ],
  '2.0.0': [
    'Auto mode: always the fastest server, no drops',
    'Bypass blocking: Nexus is harder to detect',
    'Encrypted DNS only (DNS-over-HTTPS)',
    'Traffic statistics by day and month',
    'Password-protected backup of subscriptions and settings',
    'English interface',
    'Android: tile and widget connect without opening Nexus',
    'Android: reminder 3 days and 1 day before the subscription ends',
    'Windows: Auto in the tray menu and current server on Home',
  ],
};

/// Пункты для указанной версии на языке интерфейса (пусто — нет версии).
List<String> notesFor(String version) {
  final ru = changelog.where((e) => e.$1 == version).firstOrNull?.$2 ?? const [];
  return L10n.en ? (changelogEn[version] ?? ru) : ru;
}

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
        decoration: BoxDecoration(
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
                      onlyCurrent
                          ? tr('Обновлено до {0}', [appVersion])
                          : tr('Что нового'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: NX.text2),
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
                              Text(tr('· текущая'),
                                  style: const TextStyle(
                                      color: NX.mint,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ]),
                        ),
                      ChangeList(L10n.en ? (changelogEn[ver] ?? notes) : notes),
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
                        style: TextStyle(
                            color: NX.text2, fontSize: 13.5, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      );
}
