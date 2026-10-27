import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/theme.dart';

/// Текущая версия приложения (передаётся сборкой).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.9.8');

/// Список изменений. Новая версия — сверху, пункты — коротко.
/// Отсюда же CI берёт текст для описания релиза на GitHub.
const changelog = <(String, List<String>)>[
  ('1.9.8', [
    'Свои правила: сайты через VPN или напрямую',
    'Windows: автозапуск с режимом TUN',
    'Задержка: зелёный до 350 мс, жёлтый до 700',
    'Исправлен QR-код при «Поделиться»',
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
