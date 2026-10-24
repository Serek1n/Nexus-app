import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../services/config_builder.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';

const appVersion = '1.1.0';

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
            'Российские сайты и сервисы (госуслуги, банки, VK, Яндекс) '
                'открываются напрямую, остальное — через Nexus',
          ),
          routeOption(
            RoutingMode.global,
            'Весь трафик',
            'Абсолютно всё идёт через сервер Nexus',
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
                        _CopyChip('HTTP 127.0.0.1:$kHttpPort'),
                        const SizedBox(width: 6),
                        _CopyChip('SOCKS 127.0.0.1:$kSocksPort'),
                      ],
                    ),
                  ),
                ] else
                  switchRow(
                    Icons.vpn_lock_rounded,
                    'Режим VPN',
                    st.androidVpnMode
                        ? 'Весь трафик телефона идёт через Nexus'
                        : 'Только локальный прокси 127.0.0.1:10807',
                    st.androidVpnMode,
                    (v) async {
                      app.updateSettings((s) => s.androidVpnMode = v);
                      await app.reconnectIfActive();
                    },
                  ),
              ],
            ),
          ),
          const SectionTitle('Запуск'),
          NeonCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
            child: Column(
              children: [
                switchRow(
                  Icons.sync_rounded,
                  'Обновлять подписки',
                  'При каждом запуске приложения',
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
                                    'Новые версии берутся с GitHub XTLS/Xray-core')
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
                    'Раз в сутки проверять и ставить новую версию',
                    st.autoUpdateCore,
                    (v) => app.updateSettings((s) => s.autoUpdateCore = v),
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
