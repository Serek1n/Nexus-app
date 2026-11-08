import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart' show platformName;
import '../../changelog.dart';
import '../../models.dart';
import '../../services/pin.dart';
import '../../services/app_updater.dart';
import '../../platform/android_system.dart';
import '../../platform/windows_host.dart';
import '../../services/config_builder.dart';
import '../../services/traffic_log.dart';
import '../app_scope.dart';
import '../backup_sheet.dart';
import 'diagnostics_screen.dart';
import 'traffic_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../platform/win_admin.dart';
import '../rollback_sheet.dart';
import 'apps_screen.dart';
import '../../l10n.dart';
import '../../platform/secure_clipboard.dart';


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Свои правила маршрутизации: сайты/IP через VPN и напрямую.
  Future<void> _editRules(BuildContext context) async {
    final app = AppScope.read(context);
    final viaVpn =
        TextEditingController(text: app.settings.customProxy.join('\n'));
    final direct =
        TextEditingController(text: app.settings.customDirect.join('\n'));
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: NX.text3, fontSize: 13),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Свои правила')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    tr('По одному сайту или IP в строке. Поддомены входят автоматически: «ozon.ru» — это и «www.ozon.ru». Свои правила важнее режима маршрутизации.'),
                    style: TextStyle(color: NX.text2, fontSize: 12.5)),
                const SizedBox(height: 14),
                Text(tr('Всегда через VPN'),
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: viaVpn,
                  minLines: 3,
                  maxLines: 6,
                  decoration: deco('example.com'),
                ),
                const SizedBox(height: 14),
                Text(tr('Всегда напрямую'),
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: direct,
                  minLines: 3,
                  maxLines: 6,
                  decoration: deco('bank.ru\n192.168.0.0/16'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Отмена'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Сохранить'))),
        ],
      ),
    );
    final p = parseRuleList(viaVpn.text), d = parseRuleList(direct.text);
    viaVpn.dispose();
    direct.dispose();
    if (ok != true) return;
    app.updateSettings((s) {
      s.customProxy = p;
      s.customDirect = d;
    });
    await app.reconnectIfActive();
    if (context.mounted) {
      toast(context, tr('Сохранено: через VPN {0}, напрямую {1}', [p.length, d.length]));
    }
  }

  /// Windows: программы через VPN или напрямую (по имени процесса).
  Future<void> _editApps(BuildContext context) async {
    final app = AppScope.read(context);
    final viaVpn = TextEditingController(text: app.settings.appsProxy.join('\n'));
    final direct = TextEditingController(text: app.settings.appsDirect.join('\n'));
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: NX.text3, fontSize: 13),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Программы')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    tr('По одной программе в строке — имя файла, как в Диспетчере задач (Discord.exe). Лучше всего работает в режиме TUN.'),
                    style: TextStyle(color: NX.text2, fontSize: 12.5)),
                const SizedBox(height: 14),
                Text(tr('Всегда через VPN'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: viaVpn,
                  minLines: 3,
                  maxLines: 6,
                  decoration: deco('Discord.exe\nTelegram.exe'),
                ),
                const SizedBox(height: 14),
                Text(tr('Всегда напрямую'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                TextField(
                  controller: direct,
                  minLines: 3,
                  maxLines: 6,
                  decoration: deco('steam.exe\nqbittorrent.exe'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Отмена'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Сохранить'))),
        ],
      ),
    );
    final p = parseProcessList(viaVpn.text), d = parseProcessList(direct.text);
    viaVpn.dispose();
    direct.dispose();
    if (ok != true) return;
    app.updateSettings((s) {
      s.appsProxy = p;
      s.appsDirect = d;
    });
    await app.reconnectIfActive();
    if (context.mounted) {
      toast(context, tr('Сохранено: через VPN {0}, напрямую {1}', [p.length, d.length]));
    }
  }

  /// Включение TUN: без прав администратора — перезапуск через окно UAC.
  Future<void> _toggleTun(BuildContext context, bool on) async {
    final app = AppScope.read(context);
    // Linux и macOS: права нужны только ядру — их спросят при подключении.
    if (!on || WinAdmin.isAdmin || !Platform.isWindows) {
      app.updateSettings((s) => s.windowsTun = on);
      // Автозапуск: с TUN — задачей с правами администратора.
      Autostart.apply(app.settings.launchAtStartup, tun: on);
      await app.reconnectIfActive();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Нужны права администратора')),
        content: Text(
            tr('Режим TUN создаёт виртуальную сетевую карту, и для этого Windows просит права администратора. Nexus перезапустится — подтвердите запрос Windows. Подписки и настройки сохранятся.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('Отмена'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr('Перезапустить'))),
        ],
      ),
    );
    if (ok != true) return;
    final wasOn = app.state == ConnState.connected;
    app.updateSettings((s) => s.windowsTun = true);
    await app.flushSaves();
    if (await WinAdmin.relaunchElevated(connect: wasOn)) {
      await app.quitApp?.call();
    } else {
      app.updateSettings((s) => s.windowsTun = false);
      if (context.mounted) {
        toast(context, tr('Windows не дал прав администратора — TUN не включён'),
            error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.settings;

    Widget switchRow(IconData icon, String title, String sub, bool value,
            ValueChanged<bool> onChanged) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, color: NX.violet, size: 21),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style:
                            TextStyle(color: NX.text2, fontSize: 12.5)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        );

    Widget routeOption(RoutingMode m, String title, String text) {
      final on = st.routing == m;
      return NeonCard(
          active: on,
          onTap: () async {
            app.updateSettings((s) => s.routing = m);
            await app.reconnectIfActive();
          },
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: on ? NX.violet : NX.text3, width: on ? 6 : 1.6),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text(text,
                        style: TextStyle(
                            color: NX.text2, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: _gapped([
          PageHeader(title: tr('Настройки')),
          SectionTitle(tr('Маршрутизация')),
          routeOption(
            RoutingMode.smart,
            tr('Умный режим'),
            tr('Российские сайты, IP и приложения (Госуслуги, банки, VK, Яндекс) работают напрямую, без VPN; остальное — через Nexus'),
          ),
          routeOption(
            RoutingMode.blocked,
            tr('Только заблокированное'),
            tr('Через Nexus — YouTube, Instagram, Discord, Telegram, ИИ-сервисы и другие недоступные сайты; всё остальное — напрямую. Меньше нагрузки, банки и маркетплейсы не замечают VPN'),
          ),
          routeOption(
            RoutingMode.global,
            tr('Весь трафик'),
            tr('Абсолютно всё идёт через сервер Nexus'),
          ),
          NeonCard(
            onTap: () => _editRules(context),
            child: Row(
              children: [
                const Icon(Icons.rule_rounded, color: NX.violet, size: 21),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Свои правила'),
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text(
                        st.customProxy.isEmpty && st.customDirect.isEmpty
                            ? tr('Выберите сайты, которые всегда идут через VPN или напрямую')
                            : tr('Через VPN: {0} · напрямую: {1}', [st.customProxy.length, st.customDirect.length]),
                        style:
                            TextStyle(color: NX.text2, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: NX.text3),
              ],
            ),
          ),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: switchRow(
              Icons.block_rounded,
              tr('Блокировать рекламу'),
              tr('Рекламные сети и трекеры не загружаются — страницы открываются быстрее, меньше трафика. Если сайт сломался, добавьте его в «Свои правила»'),
              st.blockAds,
              (v) async {
                app.updateSettings((s) => s.blockAds = v);
                await app.reconnectIfActive();
              },
            ),
          ),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.dns_rounded, color: NX.violet, size: 21),
                  const SizedBox(width: 14),
                  Text(tr('DNS'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5)),
                ]),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 35),
                  child: Text(
                      tr('Запросы зашифрованы и идут через сервер. AdGuard дополнительно отсекает рекламу на уровне DNS'),
                      style: TextStyle(color: NX.text2, fontSize: 12.5)),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 35),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in kDnsProviders.entries)
                      ChoiceChip(
                        label: Text(e.value.name),
                        selected: st.dns == e.key,
                        onSelected: (_) async {
                          if (st.dns == e.key) return;
                          app.updateSettings((s) => s.dns = e.key);
                          await app.reconnectIfActive();
                        },
                      ),
                  ]),
                ),
              ],
            ),
          ),
          if (app.isDesktop)
            NeonCard(
              onTap: () => _editApps(context),
              child: Row(
                children: [
                  const Icon(Icons.apps_rounded, color: NX.violet, size: 21),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Программы'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(
                          st.appsProxy.isEmpty && st.appsDirect.isEmpty
                              ? tr('Выберите программы, которые всегда идут через VPN или напрямую')
                              : tr('Через VPN: {0} · напрямую: {1}',
                                  [st.appsProxy.length, st.appsDirect.length]),
                          style: TextStyle(color: NX.text2, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: NX.text3),
                ],
              ),
            ),
          if (!app.isDesktop)
            NeonCard(
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppsScreen())),
              child: Row(
                children: [
                  const Icon(Icons.apps_rounded, color: NX.violet, size: 21),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Приложения без VPN'),
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (st.routing != RoutingMode.global &&
                                st.ruAppsDirect)
                              tr('Российские — напрямую'),
                            if (st.bypassApps.isNotEmpty)
                              tr('выбрано: {0}', [st.bypassApps.length]),
                          ].join(' · ').ifEmpty(tr('Все приложения через VPN')),
                          style:
                              TextStyle(color: NX.text2, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: NX.text3),
                ],
              ),
            ),
          SectionTitle(tr('Подключение')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(
              children: [
                if (app.isDesktop) ...[
                  switchRow(
                    Icons.lan_rounded,
                    tr('Системный прокси'),
                    tr('Браузеры и программы {0} автоматически пойдут через Nexus', [platformName()]),
                    st.windowsSystemProxy,
                    (v) async {
                      app.updateSettings((s) => s.windowsSystemProxy = v);
                      await app.reconnectIfActive();
                    },
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.lan_outlined,
                    tr('Режим TUN'),
                    st.windowsTun
                        ? (!Platform.isWindows || WinAdmin.isAdmin
                            ? tr('Через Nexus идут все программы: Telegram, игры, всё, что не смотрит на прокси')
                            : tr('Включён, но Nexus запущен без прав администратора — работает системный прокси'))
                        : Platform.isLinux
                            ? tr('Все программы через Nexus, как VPN на телефоне. Один раз попросит пароль, чтобы дать ядру право управлять сетью')
                            : Platform.isMacOS
                                ? tr('Все программы через Nexus, как VPN на телефоне. При подключении macOS спросит пароль администратора')
                                : tr('Все программы через Nexus, как VPN на телефоне. Нужны права администратора'),
                    st.windowsTun,
                    (v) => _toggleTun(context, v),
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.password_rounded,
                    tr('SOCKS-прокси с паролем'),
                    tr('Другие программы на компьютере не смогут незаметно пользоваться вашим VPN. Telegram получит пароль кнопкой ниже'),
                    st.socksAuth,
                    (v) => app.setSocksAuth(v),
                  ),                  const Divider(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.settings_ethernet_rounded,
                            color: NX.violet, size: 21),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(tr('Локальный прокси'),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5)),
                        ),
                        app.core.httpLocked
                            ? Tooltip(
                                message: tr('В режиме TUN системный прокси не нужен — HTTP-прокси закрыт паролем, им пользуется только Nexus'),
                                child: Tag(tr('HTTP · закрыт'), color: NX.text3),
                              )
                            : _CopyChip('HTTP 127.0.0.1:$activeHttpPort'),
                        const SizedBox(width: 6),
                        _CopyChip(app.socksAccount == null
                            ? 'SOCKS 127.0.0.1:$activeSocksPort'
                            : 'SOCKS ${app.socksAccount}@127.0.0.1:$activeSocksPort'),
                      ],
                    ),
                  ),
                  const Divider(height: 14),
                  // Telegram Desktop часто не смотрит на системный прокси —
                  // добавляем ему SOCKS-прокси Nexus одной ссылкой tg://.
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final acc = app.socksAccount;
                      final url = 'tg://socks?server=127.0.0.1'
                          '&port=$activeSocksPort'
                          '${acc == null ? '' : '&user=${Uri.encodeComponent(acc.split(':').first)}&pass=${Uri.encodeComponent(acc.substring(acc.indexOf(':') + 1))}'}';
                      try {
                        await Process.start(
                            'rundll32', ['url.dll,FileProtocolHandler', url]);
                        if (context.mounted) {
                          toast(context,
                              tr('Подтвердите прокси в окне Telegram'));
                        }
                      } catch (_) {
                        if (context.mounted) {
                          toast(context, tr('Telegram не установлен'),
                              error: true);
                        }
                      }
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.send_rounded,
                              color: NX.violet, size: 21),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Подключить Telegram'),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5)),
                                SizedBox(height: 2),
                                Text(
                                    tr('Telegram Desktop не всегда использует системный прокси — добавим ему прокси Nexus'),
                                    style: TextStyle(
                                        color: NX.text2, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: NX.text3),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  switchRow(
                    Icons.vpn_lock_rounded,
                    tr('Режим VPN'),
                    st.androidVpnMode
                        ? tr('Весь трафик телефона идёт через Nexus')
                        : tr('Только прокси 127.0.0.1:10807 — им сможет пользоваться любое приложение на телефоне'),
                    st.androidVpnMode,
                    (v) async {
                      app.updateSettings((s) => s.androidVpnMode = v);
                      await app.reconnectIfActive();
                    },
                  ),
                  // Режим «только прокси»: им может пользоваться любое приложение
                  // на телефоне — по желанию закрываем паролем.
                  if (!st.androidVpnMode) ...[
                    const Divider(height: 14),
                    switchRow(
                      Icons.password_rounded,
                      tr('SOCKS-прокси с паролем'),
                      tr('Пользоваться прокси смогут только приложения, которым вы дали логин и пароль'),
                      st.socksAuth,
                      (v) => app.setSocksAuth(v),
                    ),
                    if (app.socksAccount != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 35),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _CopyChip(
                              'SOCKS ${app.socksAccount}@127.0.0.1:10807'),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(children: [
            switchRow(
              Icons.bolt_rounded,
              tr('Режим «Авто»'),
              tr('Nexus сам держит соединение через самый быстрый сервер подписки и незаметно переходит на другой, если этот упал'),
              st.autoMode,
              (v) => app.setAutoMode(v),
            ),
            const Divider(height: 14),
            switchRow(
              Icons.call_split_rounded,
              tr('Маскировка соединения'),
              tr('Если провайдер блокирует подключение к серверу: Nexus режет первый пакет на части, и его сложнее распознать. Подключение чуть медленнее'),
              st.antiBlock,
              (v) async {
                app.updateSettings((s) => s.antiBlock = v);
                await app.reconnectIfActive();
              },
            ),
            if (st.antiBlock)
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 2, 6, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final (fast, label) in [
                        (false, tr('Надёжная')),
                        (true, tr('Быстрая')),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: st.antiBlockFast == fast,
                          onSelected: (_) async {
                            if (st.antiBlockFast == fast) return;
                            app.updateSettings((s) => s.antiBlockFast = fast);
                            await app.reconnectIfActive();
                          },
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      st.antiBlockFast
                          ? tr('Паузы только между первыми частями: соединение открывается на ~0,05 с дольше. Если сервер перестал подключаться — выберите «Надёжная»')
                          : tr('Паузы между всеми частями: надёжнее против умных фильтров, соединение открывается на ~0,2 с дольше'),
                      style: TextStyle(color: NX.text3, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          // На телевизоре нет батареи — экономия энергии VPN не мешает,
          // а системного экрана «Без ограничений» там обычно нет.
          if (!app.isTv) SectionTitle(tr('Работа в фоне')),
          if (!app.isTv) NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: app.isDesktop
                ? Column(
                    children: [
                      switchRow(
                        Icons.minimize_rounded,
                        tr('Сворачивать в трей'),
                        tr('Кнопка «закрыть» прячет окно, VPN продолжает работать. Выйти можно из меню значка в трее'),
                        st.closeToTray,
                        (v) => app.updateSettings((s) => s.closeToTray = v),
                      ),
                      const Divider(height: 14),
                      switchRow(
                        Icons.power_rounded,
                        tr('Запускать вместе с {0}', [platformName()]),
                        tr('Nexus стартует свёрнутым в трей'),
                        st.launchAtStartup,
                        (v) {
                          app.updateSettings((s) => s.launchAtStartup = v);
                          Autostart.apply(v, tun: st.windowsTun);
                        },
                      ),
                      if (Platform.isWindows) ...[
                      const Divider(height: 14),
                      switchRow(
                        Icons.keyboard_rounded,
                        tr('Горячая клавиша Ctrl+Alt+N'),
                        app.hotkeyOk
                            ? tr('Подключить или отключить VPN из любой программы, даже когда Nexus свёрнут')
                            : tr('Ctrl+Alt+N уже занята другой программой — закройте её и включите снова'),
                        st.hotkey,
                        (v) async {
                          app.updateSettings((s) => s.hotkey = v);
                          await app.applyHotkey();
                        },
                      ),
                      ],
                    ],
                  )
                : const _AndroidBackground(),
          ),
          if (app.isDesktop) ...[
            SectionTitle(tr('Защита')),
            NeonCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Column(
                children: [
                  switchRow(
                    Icons.shield_rounded,
                    'Kill switch',
                    tr('Если VPN оборвётся, интернет блокируется, а не идёт напрямую'),
                    st.windowsKillSwitch,
                    (v) => app.updateSettings((s) => s.windowsKillSwitch = v),
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.content_paste_off_rounded,
                    tr('Очищать буфер обмена'),
                    tr('После добавления ключа или подписки'),
                    st.clearClipboard,
                    (v) => app.updateSettings((s) => s.clearClipboard = v),
                  ),
                ],
              ),
            ),
          ],
          if (!app.isDesktop) ...[
            SectionTitle(tr('Защита')),
            NeonCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Column(
                children: [
                  switchRow(
                    Icons.screenshot_monitor_rounded,
                    tr('Скрывать экран'),
                    tr('Запрет скриншотов и размытие в списке недавних приложений'),
                    st.secureScreen,
                    (v) {
                      app.updateSettings((s) => s.secureScreen = v);
                      AndroidSystem.setSecureScreen(v);
                    },
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.content_paste_off_rounded,
                    tr('Очищать буфер обмена'),
                    tr('После добавления ключа или подписки'),
                    st.clearClipboard,
                    (v) => app.updateSettings((s) => s.clearClipboard = v),
                  ),
                  const Divider(height: 14),
                  InkWell(
                    onTap: AndroidSystem.openVpnSettings,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.shield_rounded,
                              color: NX.violet, size: 21),
                          SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Kill switch',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5)),
                                SizedBox(height: 2),
                                Text(
                                    tr('В настройках VPN выберите Nexus и включите «Постоянная VPN» и «Блокировать соединения без VPN»'),
                                    style: TextStyle(
                                        color: NX.text2, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          Icon(Icons.open_in_new_rounded,
                              color: NX.text3, size: 18),
                          SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SectionTitle(tr('Запуск')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(
              children: [
                switchRow(
                  Icons.autorenew_rounded,
                  tr('Держать соединение'),
                  tr('Переподключаться при обрыве и раз в 45 секунд проверять, что трафик идёт'),
                  st.autoReconnect,
                  (v) => app.updateSettings((s) => s.autoReconnect = v),
                ),
                const Divider(height: 14),
                switchRow(
                  Icons.alt_route_rounded,
                  tr('Автовыбор при сбое'),
                  tr('Если сервер не пропускает трафик, Nexus сам переключится на следующий'),
                  st.autoFailover,
                  (v) => app.updateSettings((s) => s.autoFailover = v),
                ),
                const Divider(height: 14),
                switchRow(
                  Icons.sync_rounded,
                  tr('Обновлять подписки'),
                  tr('При запуске, подключении и переподключении VPN'),
                  st.autoUpdateOnStart,
                  (v) => app.updateSettings((s) => s.autoUpdateOnStart = v),
                ),
                const Divider(height: 14),
                switchRow(
                  Icons.flash_on_rounded,
                  tr('Автоподключение'),
                  tr('Подключаться сразу после запуска'),
                  st.autoConnectOnStart,
                  (v) => app.updateSettings((s) => s.autoConnectOnStart = v),
                ),
              ],
            ),
          ),
          SectionTitle(tr('Ядро Xray')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.memory_rounded,
                        color: NX.violet, size: 21),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(app.coreVersion,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5)),
                          const SizedBox(height: 2),
                          Text(
                            app.core.canUpdateCore
                                ? (app.coreUpdateStatus ??
                                    (app.isDesktop
                                        ? tr('Новые версии берутся с GitHub XTLS/Xray-core')
                                        : tr('Свежий Xray приходит обновлением Nexus')))
                                : tr('Обновляется вместе с приложением'),
                            style: TextStyle(
                                color: NX.text2, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (app.core.canUpdateCore)
                      NeonButton(
                        label: tr('Проверить'),
                        secondary: true,
                        loading: app.coreUpdating,
                        onPressed: () => app.updateCore(),
                      ),
                  ],
                ),
                if (app.core.canUpdateCore) ...[
                  const Divider(height: 22),
                  switchRow(
                    Icons.update_rounded,
                    tr('Автообновление ядра'),
                    app.isDesktop
                        ? tr('Раз в сутки проверять и ставить новую версию')
                        : tr('Раз в сутки проверять и предлагать обновление'),
                    st.autoUpdateCore,
                    (v) => app.updateSettings((s) => s.autoUpdateCore = v),
                  ),
                ],
              ],
            ),
          ),
          SectionTitle(tr('Обновления Nexus')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.system_update_rounded,
                        color: NX.violet, size: 21),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              app.appUpdate != null
                                  ? tr('Доступна {0}', [app.appUpdate!.version])
                                  : tr('Версия {0}', [appVersionLabel]),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5)),
                          const SizedBox(height: 2),
                          Text(
                            !AppUpdater.configured
                                ? tr('Эта сборка без источника обновлений')
                                : app.updateStatus ??
                                    (app.updateFile != null
                                        ? tr('Скачано и проверено — можно установить')
                                        : app.appUpdate != null
                                            ? tr('Нажмите «Установить» — скачаем и проверим')
                                            : tr('Новые версии приходят с GitHub')),
                            style: TextStyle(
                                color: NX.text2, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (AppUpdater.configured && app.appUpdate == null)
                      NeonButton(
                        label: tr('Проверить'),
                        secondary: true,
                        loading: app.checkingUpdate,
                        onPressed: () => app.checkAppUpdate(),
                      ),
                  ],
                ),
                if (app.appUpdate != null &&
                    app.appUpdate!.notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ChangeList(app.appUpdate!.notes),
                ],
                if (app.appUpdate != null) ...[
                  const SizedBox(height: 12),
                  if (app.updateProgress != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: app.updateProgress,
                        minHeight: 5,
                        backgroundColor: NX.surface2,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  NeonButton(
                    label: app.isDesktop
                        ? tr('Установить и перезапустить')
                        : tr('Установить обновление'),
                    icon: Icons.download_rounded,
                    expand: true,
                    loading: app.updateProgress != null,
                    onPressed: app.installAppUpdate,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NeonButton(
                      label: tr('Что нового'),
                      icon: Icons.notes_rounded,
                      secondary: true,
                      onPressed: () => showChangelog(context),
                    ),
                    if (AppUpdater.configured)
                      NeonButton(
                        label: tr('Откатить версию'),
                        icon: Icons.history_rounded,
                        secondary: true,
                        onPressed: () => showRollbackSheet(context),
                      ),
                  ],
                ),
                if (AppUpdater.configured) ...[
                  const Divider(height: 22),
                  switchRow(
                    Icons.autorenew_rounded,
                    tr('Проверять обновления'),
                    tr('Сообщать о новой версии; скачивание — по кнопке «Установить»'),
                    st.autoUpdateApp,
                    (v) => app.updateSettings((s) => s.autoUpdateApp = v),
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.science_rounded,
                    tr('Бета-версии'),
                    tr('Получать пробные сборки раньше остальных. Если что-то сломается — «Откатить версию»'),
                    st.betaUpdates,
                    (v) {
                      app.updateSettings((s) => s.betaUpdates = v);
                      app.checkAppUpdate();
                    },
                  ),
                ],
              ],
            ),
          ),
          SectionTitle(tr('Доступ к Nexus')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(
              children: [
                switchRow(
                  Icons.lock_outline_rounded,
                  tr('Вход по PIN-коду'),
                  app.isDesktop
                      ? tr('Без PIN никто не откроет окно Nexus и не увидит ключи и подписки. Подключение из трея и по Ctrl+Alt+N работает и так')
                      : tr('Без PIN никто не откроет Nexus и не увидит ключи и подписки. Подключение кнопкой в шторке и виджетом работает и так'),
                  app.pinEnabled,
                  (v) => v ? _setPin(context) : _removePin(context),
                ),
                if (app.pinEnabled) ...[
                  const Divider(height: 14),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _setPin(context, change: true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        const Icon(Icons.password_rounded, color: NX.violet, size: 21),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(tr('Сменить PIN-код'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14.5)),
                        ),
                        Icon(Icons.chevron_right_rounded, color: NX.text3),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SectionTitle(tr('Данные')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.network_check_rounded,
                  title: tr('Проверка связи'),
                  subtitle: tr('Найдёт, что не работает: интернет, сервер, сайты через VPN'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DiagnosticsScreen())),
                ),
                const Divider(height: 6),
                _NavRow(
                  icon: Icons.bar_chart_rounded,
                  title: tr('Статистика трафика'),
                  subtitle: tr('Сегодня: {0}', [fmtBytes(app.traffic.total(TrafficLog.dayKey(DateTime.now())))]),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const TrafficScreen())),
                ),
                const Divider(height: 6),
                _NavRow(
                  icon: Icons.backup_rounded,
                  title: tr('Резервная копия'),
                  subtitle: tr('Подписки, серверы и настройки под паролем. Восстановить — через «Добавить»'),
                  onTap: () => showBackupExport(context),
                ),
              ],
            ),
          ),
          SectionTitle(tr('Оформление')),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (v, label, icon) in [
                  ('dark', tr('Тёмная'), Icons.dark_mode_rounded),
                  ('light', tr('Светлая'), Icons.light_mode_rounded),
                  ('system', tr('Как в системе'), Icons.brightness_auto_rounded),
                ])
                  ChoiceChip(
                    avatar: Icon(icon, size: 17),
                    label: Text(label),
                    selected: st.theme == v,
                    showCheckmark: false,
                    onSelected: (_) => app.setTheme(v),
                  ),
              ],
            ),
          ),
          const SectionTitle('Язык · Language'),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (v, label) in [
                  ('system', tr('Как в системе')),
                  ('ru', 'Русский'),
                  ('en', 'English'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: st.language == v,
                    onSelected: (_) => app.setLanguage(v),
                  ),
              ],
            ),
          ),
          SectionTitle(tr('О приложении')),
          NeonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NexusLogo(size: 30),
                const SizedBox(height: 14),
                _InfoRow(tr('Версия'), appVersionLabel),
                _InfoRow(tr('Ядро'), app.coreVersion),
                _InfoRow(tr('Платформа'), platformName()),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NeonButton(
                      label: tr('Журнал'),
                      icon: Icons.receipt_long_rounded,
                      secondary: true,
                      onPressed: () => _showLogs(context),
                    ),
                    NeonButton(
                      label: tr('Отчёт для поддержки'),
                      icon: Icons.support_agent_rounded,
                      secondary: true,
                      onPressed: () async {
                        final app = AppScope.read(context);
                        final text = await app.supportReport();
                        await Clipboard.setData(ClipboardData(text: text));
                        if (!context.mounted) return;
                        toast(context, tr('Отчёт скопирован — отправьте его в поддержку. Ключей и ссылок подписок в нём нет'));
                        if (!app.isDesktop) await AndroidSystem.shareText(text);
                      },
                    ),
                    NeonButton(
                      label: tr('Сбросить всё'),
                      icon: Icons.restart_alt_rounded,
                      danger: true,
                      onPressed: () => _reset(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// Ровные промежутки между карточками (после заголовков разделов — нет).
  static List<Widget> _gapped(List<Widget> xs) {
    final out = <Widget>[];
    for (var i = 0; i < xs.length; i++) {
      out.add(xs[i]);
      final next = i + 1 < xs.length ? xs[i + 1] : null;
      if (next != null &&
          xs[i] is! SectionTitle &&
          xs[i] is! PageHeader &&
          next is! SectionTitle) {
        out.add(const SizedBox(height: 10));
      }
    }
    return out;
  }

  Future<void> _showLogs(BuildContext context) async {
    final app = AppScope.read(context);
    final lines = await app.core.fetchLogs();
    if (!context.mounted) return;
    final text = lines.isEmpty ? tr('Журнал пуст') : lines.join('\n');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Журнал ядра')),
        content: SizedBox(
          width: 560,
          height: 360,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NX.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NX.stroke),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(text,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11.5, height: 1.4)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
            },
            child: Text(tr('Скопировать')),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Закрыть'))),
        ],
      ),
    );
  }

  /// Окно ввода PIN: [twice] — с повтором (новый PIN).
  Future<String?> _askPin(BuildContext context,
      {required String title, bool twice = false}) {
    final a = TextEditingController(), b = TextEditingController();
    String? err;
    InputDecoration deco(String hint) =>
        InputDecoration(hintText: hint, counterText: '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: a,
              autofocus: true,
              obscureText: true,
              maxLength: 8,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: deco(twice ? tr('4–8 цифр') : tr('PIN-код')),
            ),
            if (twice)
              TextField(
                controller: b,
                obscureText: true,
                maxLength: 8,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: deco(tr('Ещё раз')),
              ),
            if (err != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(err!, style: const TextStyle(color: NX.red, fontSize: 13)),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Отмена'))),
            TextButton(
              onPressed: () {
                if (a.text.length < 4) {
                  set(() => err = tr('Не короче 4 цифр'));
                  return;
                }
                if (twice && a.text != b.text) {
                  set(() => err = tr('PIN-коды не совпадают'));
                  return;
                }
                if (twice && RegExp(r'^(\d)\1+$').hasMatch(a.text)) {
                  set(() => err = tr('Слишком простой PIN-код'));
                  return;
                }
                Navigator.pop(ctx, a.text);
              },
              child: Text(tr('Готово')),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _checkPin(BuildContext context) async {
    final app = AppScope.read(context);
    final h = app.settings.pinHash;
    if (h == null) return true;
    final cur = await _askPin(context, title: tr('Текущий PIN-код'));
    if (cur == null) return false;
    final ok = await Pin.verify(cur, h);
    if (!ok && context.mounted) toast(context, tr('Неверный PIN-код'));
    return ok;
  }

  Future<void> _setPin(BuildContext context, {bool change = false}) async {
    if (change && !await _checkPin(context)) return;
    if (!context.mounted) return;
    final pin = await _askPin(context, title: tr('Новый PIN-код'), twice: true);
    if (pin == null || !context.mounted) return;
    await AppScope.read(context).setPin(pin);
    if (context.mounted) {
      toast(context, tr('PIN-код включён. Его не восстановить — если забудете, поможет только «Сбросить всё»'));
    }
  }

  Future<void> _removePin(BuildContext context) async {
    if (!await _checkPin(context)) return;
    if (!context.mounted) return;
    await AppScope.read(context).setPin(null);
    if (context.mounted) toast(context, tr('Вход по PIN-коду выключен'));
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Сбросить всё?')),
        content: Text(
            tr('Будут удалены все подписки, серверы и настройки.'),
            style: TextStyle(color: NX.text2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Сбросить'), style: TextStyle(color: NX.red))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await AppScope.read(context).resetAll();
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.k, this.v);
  final String k, v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Text(k, style: TextStyle(color: NX.text2, fontSize: 13.5)),
          const Spacer(),
          Text(v,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
      );
}

class _CopyChip extends StatelessWidget {
  const _CopyChip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          copySecret(text.split(' ').last);
          toast(context, tr('Скопировано: {0}', [text.split(' ').last]));
        },
        child: Tag(text, color: NX.cyan),
      );
}

/// Android: статус экономии батареи и кнопка исключения.
class _AndroidBackground extends StatefulWidget {
  const _AndroidBackground();

  @override
  State<_AndroidBackground> createState() => _AndroidBackgroundState();
}

class _AndroidBackgroundState extends State<_AndroidBackground>
    with WidgetsBindingObserver {
  bool? _ok;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Пользователь возвращается из системных настроек — обновляем статус.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await AndroidSystem.isIgnoringBattery();
    if (mounted) setState(() => _ok = ok);
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ok ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(ok ? Icons.battery_full_rounded : Icons.battery_alert_rounded,
              color: ok ? NX.mint : NX.amber, size: 21),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? tr('Работа в фоне разрешена') : tr('Система может остановить VPN'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                    ok
                        ? tr('Экономия батареи не мешает Nexus')
                        : tr('Отключите для Nexus экономию батареи, чтобы VPN не обрывался'),
                    style: TextStyle(color: NX.text2, fontSize: 12.5)),
              ],
            ),
          ),
          if (!ok)
            NeonButton(
              label: tr('Разрешить'),
              secondary: true,
              onPressed: AndroidSystem.requestIgnoreBattery,
            ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Строка-переход: значок, заголовок, пояснение, стрелка.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: NX.violet, size: 21),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            TextStyle(color: NX.text2, fontSize: 12.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: NX.text3),
            ],
          ),
        ),
      );
}
