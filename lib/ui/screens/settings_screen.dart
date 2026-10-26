import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../changelog.dart';
import '../../models.dart';
import '../../services/app_updater.dart';
import '../../platform/android_system.dart';
import '../../platform/windows_host.dart';
import '../../services/config_builder.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';
import '../rollback_sheet.dart';
import 'apps_screen.dart';


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
          const PageHeader(title: 'Настройки'),
          const SectionTitle('Маршрутизация'),
          routeOption(
            RoutingMode.smart,
            'Умный режим',
            'Российские сайты, IP и приложения (Госуслуги, банки, VK, Яндекс) '
                'работают напрямую, без VPN; остальное — через Nexus',
          ),
          routeOption(
            RoutingMode.global,
            'Весь трафик',
            'Абсолютно всё идёт через сервер Nexus',
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
                        const Text('Приложения без VPN',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5)),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (st.routing == RoutingMode.smart &&
                                st.ruAppsDirect)
                              'Российские — напрямую',
                            if (st.bypassApps.isNotEmpty)
                              'выбрано: ${st.bypassApps.length}',
                          ].join(' · ').ifEmpty('Все приложения через VPN'),
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
          const SectionTitle('Подключение'),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(
              children: [
                if (app.isDesktop) ...[
                  switchRow(
                    Icons.lan_rounded,
                    'Системный прокси',
                    'Браузеры и программы Windows автоматически пойдут через Nexus',
                    st.windowsSystemProxy,
                    (v) async {
                      app.updateSettings((s) => s.windowsSystemProxy = v);
                      await app.reconnectIfActive();
                    },
                  ),
                  const Divider(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.settings_ethernet_rounded,
                            color: NX.violet, size: 21),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text('Локальный прокси',
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
                ] else
                  switchRow(
                    Icons.vpn_lock_rounded,
                    'Режим VPN',
                    st.androidVpnMode
                        ? 'Весь трафик телефона идёт через Nexus'
                        : 'Только прокси 127.0.0.1:10807 — им сможет пользоваться любое приложение на телефоне',
                    st.androidVpnMode,
                    (v) async {
                      app.updateSettings((s) => s.androidVpnMode = v);
                      await app.reconnectIfActive();
                    },
                  ),
              ],
            ),
          ),
          const SectionTitle('Работа в фоне'),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: app.isDesktop
                ? Column(
                    children: [
                      switchRow(
                        Icons.minimize_rounded,
                        'Сворачивать в трей',
                        'Кнопка «закрыть» прячет окно, VPN продолжает работать. '
                            'Выйти можно из меню значка в трее',
                        st.closeToTray,
                        (v) => app.updateSettings((s) => s.closeToTray = v),
                      ),
                      const Divider(height: 14),
                      switchRow(
                        Icons.power_rounded,
                        'Запускать вместе с Windows',
                        'Nexus стартует свёрнутым в трей',
                        st.launchAtStartup,
                        (v) {
                          app.updateSettings((s) => s.launchAtStartup = v);
                          Autostart.apply(v);
                        },
                      ),
                    ],
                  )
                : const _AndroidBackground(),
          ),
          if (app.isDesktop) ...[
            const SectionTitle('Защита'),
            NeonCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Column(
                children: [
                  switchRow(
                    Icons.shield_rounded,
                    'Kill switch',
                    'Если VPN оборвётся, интернет блокируется, а не идёт напрямую',
                    st.windowsKillSwitch,
                    (v) => app.updateSettings((s) => s.windowsKillSwitch = v),
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.content_paste_off_rounded,
                    'Очищать буфер обмена',
                    'После добавления ключа или подписки',
                    st.clearClipboard,
                    (v) => app.updateSettings((s) => s.clearClipboard = v),
                  ),
                ],
              ),
            ),
          ],
          if (!app.isDesktop) ...[
            const SectionTitle('Защита'),
            NeonCard(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Column(
                children: [
                  switchRow(
                    Icons.screenshot_monitor_rounded,
                    'Скрывать экран',
                    'Запрет скриншотов и размытие в списке недавних приложений',
                    st.secureScreen,
                    (v) {
                      app.updateSettings((s) => s.secureScreen = v);
                      AndroidSystem.setSecureScreen(v);
                    },
                  ),
                  const Divider(height: 14),
                  switchRow(
                    Icons.content_paste_off_rounded,
                    'Очищать буфер обмена',
                    'После добавления ключа или подписки',
                    st.clearClipboard,
                    (v) => app.updateSettings((s) => s.clearClipboard = v),
                  ),
                  const Divider(height: 14),
                  InkWell(
                    onTap: AndroidSystem.openVpnSettings,
                    child: const Padding(
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
                                    'В настройках VPN выберите Nexus и включите '
                                    '«Постоянная VPN» и «Блокировать соединения без VPN»',
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
          const SectionTitle('Запуск'),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(
              children: [
                switchRow(
                  Icons.autorenew_rounded,
                  'Держать соединение',
                  'Переподключаться при обрыве и раз в 45 секунд проверять, что трафик идёт',
                  st.autoReconnect,
                  (v) => app.updateSettings((s) => s.autoReconnect = v),
                ),
                const Divider(height: 14),
                switchRow(
                  Icons.alt_route_rounded,
                  'Автовыбор при сбое',
                  'Если сервер не пропускает трафик, Nexus сам переключится на следующий',
                  st.autoFailover,
                  (v) => app.updateSettings((s) => s.autoFailover = v),
                ),
                const Divider(height: 14),
                switchRow(
                  Icons.sync_rounded,
                  'Обновлять подписки',
                  'При запуске, подключении и переподключении VPN',
                  st.autoUpdateOnStart,
                  (v) => app.updateSettings((s) => s.autoUpdateOnStart = v),
                ),
                const Divider(height: 14),
                switchRow(
                  Icons.flash_on_rounded,
                  'Автоподключение',
                  'Подключаться сразу после запуска',
                  st.autoConnectOnStart,
                  (v) => app.updateSettings((s) => s.autoConnectOnStart = v),
                ),
              ],
            ),
          ),
          const SectionTitle('Ядро Xray'),
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
                                        ? 'Новые версии берутся с GitHub XTLS/Xray-core'
                                        : 'Свежий Xray приходит обновлением Nexus'))
                                : 'Обновляется вместе с приложением',
                            style: const TextStyle(
                                color: NX.text2, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (app.core.canUpdateCore)
                      NeonButton(
                        label: 'Проверить',
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
                    'Автообновление ядра',
                    app.isDesktop
                        ? 'Раз в сутки проверять и ставить новую версию'
                        : 'Раз в сутки проверять и предлагать обновление',
                    st.autoUpdateCore,
                    (v) => app.updateSettings((s) => s.autoUpdateCore = v),
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('Обновления Nexus'),
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
                                  ? 'Доступна ${app.appUpdate!.version}'
                                  : 'Версия $appVersion',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5)),
                          const SizedBox(height: 2),
                          Text(
                            !AppUpdater.configured
                                ? 'Эта сборка без источника обновлений'
                                : app.updateStatus ??
                                    (app.updateFile != null
                                        ? 'Скачано и проверено — можно установить'
                                        : 'Новые версии приходят с GitHub'),
                            style: const TextStyle(
                                color: NX.text2, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (AppUpdater.configured && app.appUpdate == null)
                      NeonButton(
                        label: 'Проверить',
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
                        ? 'Установить и перезапустить'
                        : 'Установить обновление',
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
                      label: 'Что нового',
                      icon: Icons.notes_rounded,
                      secondary: true,
                      onPressed: () => showChangelog(context),
                    ),
                    if (AppUpdater.configured)
                      NeonButton(
                        label: 'Откатить версию',
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
                    'Автообновление',
                    'Проверять и скачивать новые версии в фоне',
                    st.autoUpdateApp,
                    (v) => app.updateSettings((s) => s.autoUpdateApp = v),
                  ),
                ],
              ],
            ),
          ),
          const SectionTitle('О приложении'),
          NeonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NexusLogo(size: 30),
                const SizedBox(height: 14),
                _InfoRow('Версия', appVersion),
                _InfoRow('Ядро', app.coreVersion),
                _InfoRow('Платформа', app.isDesktop ? 'Windows' : 'Android'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    NeonButton(
                      label: 'Журнал',
                      icon: Icons.receipt_long_rounded,
                      secondary: true,
                      onPressed: () => _showLogs(context),
                    ),
                    NeonButton(
                      label: 'Сбросить всё',
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
    final text = lines.isEmpty ? 'Журнал пуст' : lines.join('\n');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Журнал ядра'),
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
            child: const Text('Скопировать'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить всё?'),
        content: const Text(
            'Будут удалены все подписки, серверы и настройки.',
            style: TextStyle(color: NX.text2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сбросить', style: TextStyle(color: NX.red))),
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
          toast(context, 'Скопировано: ${text.split(' ').last}');
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
                Text(ok ? 'Работа в фоне разрешена' : 'Система может остановить VPN',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                    ok
                        ? 'Экономия батареи не мешает Nexus'
                        : 'Отключите для Nexus экономию батареи, чтобы VPN не обрывался',
                    style: const TextStyle(color: NX.text2, fontSize: 12.5)),
              ],
            ),
          ),
          if (!ok)
            NeonButton(
              label: 'Разрешить',
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
