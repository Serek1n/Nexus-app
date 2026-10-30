import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../changelog.dart';
import '../../models.dart';
import '../../services/app_updater.dart';
import '../../platform/android_system.dart';
import '../../platform/windows_host.dart';
import '../../services/config_builder.dart';
import '../../services/traffic_log.dart';
import '../app_scope.dart';
import '../backup_sheet.dart';
import 'traffic_screen.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../platform/win_admin.dart';
import '../rollback_sheet.dart';
import 'apps_screen.dart';
import '../../l10n.dart';


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
          hintStyle: const TextStyle(color: NX.text3, fontSize: 13),
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

  /// Включение TUN: без прав администратора — перезапуск через окно UAC.
  Future<void> _toggleTun(BuildContext context, bool on) async {
    final app = AppScope.read(context);
    if (!on || WinAdmin.isAdmin) {
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
                            const TextStyle(color: NX.text2, fontSize: 12.5)),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        );

    Widget routeOption(RoutingMode m, String title, String text) {
      final on = st.routing == m;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: NeonCard(
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
                        style: const TextStyle(
                            color: NX.text2, fontSize: 12.5, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          PageHeader(title: tr('Настройки')),
          SectionTitle(tr('Маршрутизация')),
          routeOption(
            RoutingMode.smart,
            tr('Умный режим'),
            tr('Российские сайты, IP и приложения (Госуслуги, банки, VK, Яндекс) работают напрямую, без VPN; остальное — через Nexus'),
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
                            const TextStyle(color: NX.text2, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: NX.text3),
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
                            if (st.routing == RoutingMode.smart &&
                                st.ruAppsDirect)
                              tr('Российские — напрямую'),
                            if (st.bypassApps.isNotEmpty)
                              tr('выбрано: {0}', [st.bypassApps.length]),
                          ].join(' · ').ifEmpty(tr('Все приложения через VPN')),
                          style:
                              const TextStyle(color: NX.text2, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: NX.text3),
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
                    tr('Браузеры и программы Windows автоматически пойдут через Nexus'),
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
                        ? (WinAdmin.isAdmin
                            ? tr('Через Nexus идут все программы: Telegram, игры, всё, что не смотрит на прокси')
                            : tr('Включён, но Nexus запущен без прав администратора — работает системный прокси'))
                        : tr('Все программы через Nexus, как VPN на телефоне. Нужны права администратора'),
                    st.windowsTun,
                    (v) => _toggleTun(context, v),
                  ),
                  const Divider(height: 14),
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
                        _CopyChip('HTTP 127.0.0.1:$activeHttpPort'),
                        const SizedBox(width: 6),
                        _CopyChip('SOCKS 127.0.0.1:$activeSocksPort'),
                      ],
                    ),
                  ),
                  const Divider(height: 14),
                  // Telegram Desktop часто не смотрит на системный прокси —
                  // добавляем ему SOCKS-прокси Nexus одной ссылкой tg://.
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final url = 'tg://socks?server=127.0.0.1'
                          '&port=$activeSocksPort';
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
                ] else
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
              tr('Обход блокировок'),
              tr('Если провайдер блокирует подключение к серверу: Nexus режет первый пакет на части, и его сложнее распознать. Подключение чуть медленнее'),
              st.antiBlock,
              (v) async {
                app.updateSettings((s) => s.antiBlock = v);
                await app.reconnectIfActive();
              },
            ),
            ]),
          ),
          SectionTitle(tr('Работа в фоне')),
          NeonCard(
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
                        tr('Запускать вместе с Windows'),
                        tr('Nexus стартует свёрнутым в трей'),
                        st.launchAtStartup,
                        (v) {
                          app.updateSettings((s) => s.launchAtStartup = v);
                          Autostart.apply(v, tun: st.windowsTun);
                        },
                      ),
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
                            style: const TextStyle(
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
                                  : tr('Версия {0}', [appVersion]),
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
                            style: const TextStyle(
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
                _InfoRow(tr('Версия'), appVersion),
                _InfoRow(tr('Ядро'), app.coreVersion),
                _InfoRow(tr('Платформа'), app.isDesktop ? 'Windows' : 'Android'),
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
                      secondary: true,
                      onPressed: () => _reset(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
          Text(k, style: const TextStyle(color: NX.text2, fontSize: 13.5)),
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
          Clipboard.setData(ClipboardData(text: text.split(' ').last));
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
                    style: const TextStyle(color: NX.text2, fontSize: 12.5)),
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
                            const TextStyle(color: NX.text2, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: NX.text3),
            ],
          ),
        ),
      );
}
