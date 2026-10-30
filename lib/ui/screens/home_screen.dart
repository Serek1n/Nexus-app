import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../changelog.dart';
import '../../models.dart';
import '../../platform/android_system.dart';
import '../add_sheet.dart';
import '../app_scope.dart';
import '../connect_button.dart';
import '../theme.dart';
import '../widgets.dart';
import 'traffic_screen.dart';
import '../../l10n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenServers, this.wide = false});
  final VoidCallback onOpenServers;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final sel = app.selected;
    final sub = sel == null ? null : app.subscriptionOf(sel);

    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StatusPill(state: app.state, blocked: app.blocked),
        const SizedBox(height: 28),
        ConnectButton(
          state: app.state,
          blocked: app.blocked,
          size: wide ? 220 : 196,
          onTap: () {
            if (sel == null) {
              showAddSheet(context);
              return;
            }
            HapticFeedback.mediumImpact();
            app.toggle();
          },
        ),
        const SizedBox(height: 22),
        _TimerLine(state: app.state, since: app.connectedAt),
      ],
    );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (app.lastError != null) ...[
          _ErrorBanner(text: app.lastError!, onClose: app.clearError),
          const SizedBox(height: 10),
        ],
        if (app.reconnectNote != null) ...[
          _Notice(text: app.reconnectNote!, icon: Icons.autorenew_rounded),
          const SizedBox(height: 10),
        ],
        // Подсказка про батарею — всплывающим уведомлением, а не плашкой.
        if (app.batteryHintDue)
          Builder(builder: (ctx) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!app.batteryHintDue) return;
              app.markBatteryHintShown();
              ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 8),
                content: Row(children: [
                  Icon(Icons.battery_alert_rounded,
                      color: NX.amber, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          tr('Android может отключать VPN в фоне — разрешите Nexus работать без ограничений'))),
                ]),
                action: SnackBarAction(
                  label: tr('Разрешить'),
                  textColor: NX.violet,
                  onPressed: () async {
                    await AndroidSystem.requestIgnoreBattery();
                    await Future.delayed(const Duration(seconds: 2));
                    await app.refreshBattery();
                  },
                ),
              ));
            });
            return const SizedBox.shrink();
          }),
        if (app.state == ConnState.connected &&
            app.core.modeWarning != null) ...[
          _Notice(
              text: app.core.modeWarning!, icon: Icons.lan_outlined),
          const SizedBox(height: 10),
        ],
        if (app.state == ConnState.connected && app.exitWarning != null) ...[
          _Notice(
            text: app.exitWarning!,
            icon: Icons.gpp_maybe_rounded,
            onTap: app.reconnect,
          ),
          const SizedBox(height: 10),
        ],
        if (app.failoverNote != null) ...[
          _Notice(text: app.failoverNote!, icon: Icons.alt_route_rounded),
          const SizedBox(height: 10),
        ],
        if (app.blocked) ...[
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              color: NX.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NX.red.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.gpp_bad_rounded, color: NX.red, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('VPN оборвался — интернет заблокирован, чтобы ничего не ушло мимо'),
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: TextButton(
                    onPressed: app.reconnect,
                    child: Text(tr('Переподключить'),
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (app.appUpdate != null) ...[
          const _UpdateCard(),
          const SizedBox(height: 10),
        ],
        if (sub != null && _subWarning(sub) != null) ...[
          _Notice(text: _subWarning(sub)!),
          const SizedBox(height: 10),
        ],
        if (sel != null)
          _ServerRow(onTap: onOpenServers)
        else
          NeonCard(
            onTap: () => showAddSheet(context),
            child: Row(
              children: [
                Icon(Icons.add_link_rounded, color: NX.violet),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Добавьте подписку'),
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text(tr('Вставьте ссылку из бота NEXUS'),
                          style: TextStyle(color: NX.text2, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: NX.text3),
              ],
            ),
          ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          child: app.state == ConnState.connected && !app.blocked
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ValueListenableBuilder<ConnStats>(
                    valueListenable: app.statsNotifier,
                    builder: (_, st, __) => _StatsRow(stats: st),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (sub != null) ...[
          const SizedBox(height: 10),
          _SubscriptionStrip(sub: sub),
        ],
      ],
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 8, 32, 24),
        child: Row(
          children: [
            Expanded(child: Center(child: hero)),
            const SizedBox(width: 24),
            SizedBox(
              width: 380,
              child: Center(child: SingleChildScrollView(child: details)),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Row(
            children: [
              const NexusLogo(size: 28),
              const Spacer(),
              NxIconButton(
                icon: Icons.add_rounded,
                tooltip: tr('Добавить'),
                onPressed: () => showAddSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 36),
          Center(child: hero),
          const SizedBox(height: 36),
          details,
        ],
      ),
    );
  }
}

/// Предупреждение о скором окончании подписки или трафика.
String? _subWarning(Subscription sub) {
  final days = sub.expire?.difference(DateTime.now()).inDays;
  if (days != null && days < 0) return tr('Подписка «{0}» закончилась — продлите её в боте', [sub.title]);
  if (days != null && days <= 3) {
    return tr('Подписка заканчивается через {0} {1} — продлите её в боте', [days, plural(days, tr('день'), tr('дня'), tr('дней'))]);
  }
  if (sub.total > 0 && sub.used / sub.total >= 0.9) {
    return tr('Использовано {0}% трафика подписки', [(sub.used / sub.total * 100).round()]);
  }
  return null;
}

/// Карточка обновления: что именно обновляется и до какой версии.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final u = app.appUpdate!;
    final newApp = u.version.replaceFirst(RegExp(r'^Nexus\s*'), '').trim();
    final appChanged = newApp.isNotEmpty && newApp != appVersion;
    // На Windows ядро обновляется отдельно, в релизе важна только версия Nexus.
    final xrayChanged = !app.isDesktop &&
        u.xray.isNotEmpty &&
        !app.coreVersion.contains(u.xray);
    final title = switch ((appChanged, xrayChanged)) {
      (true, true) => 'Nexus $newApp + Xray ${u.xray}',
      (false, true) => 'Xray ${u.xray}',
      _ => 'Nexus ${newApp.isEmpty ? '' : newApp}'.trim(),
    };
    final progress = app.updateProgress;
    final ready = app.updateFile != null;
    final status = progress != null
        ? tr('Загрузка {0}%', [(progress * 100).round()])
        : ready
            ? tr('Готово к установке')
            : tr('Доступно обновление');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: NX.violet.withValues(alpha: 0.28)),
        gradient: LinearGradient(
          colors: [NX.violet.withValues(alpha: 0.14), NX.surface],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
        children: [
          InkWell(
            // Нажатие на карточку — список изменений.
            onTap: u.notes.isEmpty
                ? null
                : () => _showNotes(context, title, u.notes),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: NX.neon,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    xrayChanged && !appChanged
                        ? Icons.memory_rounded
                        : Icons.arrow_downward_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: ready ? NX.mint : NX.text2,
                              fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (progress == null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: NX.violet,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    onPressed: app.installAppUpdate,
                    child: Text(tr('Установить')),
                  ),
              ],
            ),
          ),
          ),
          if (progress != null)
            LinearProgressIndicator(
              value: progress,
              minHeight: 3,
              color: NX.violet,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
      ),
    );
  }

  void _showNotes(BuildContext context, String title, List<String> notes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: NX.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: NX.strokeStrong)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Что нового в {0}', [title]),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ChangeList(notes),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(
      {required this.text, this.icon = Icons.schedule_rounded, this.onTap});
  final String text;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        // Спокойная карточка: цвет несёт только значок, без жёлтой заливки.
        decoration: BoxDecoration(
          color: NX.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NX.stroke),
        ),
        child: Row(
          children: [
            Icon(icon, color: NX.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: NX.text, fontSize: 13)),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  color: NX.text3, size: 18),
          ],
        ),
      ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state, this.blocked = false});
  final ConnState state;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final (text, color) = blocked
        ? (tr('Нет соединения'), NX.red)
        : switch (state) {
      ConnState.connected => (tr('Подключено'), NX.mint),
      ConnState.connecting => (tr('Подключение…'), NX.violet),
      ConnState.disconnecting => (tr('Отключение…'), NX.text2),
      ConnState.disconnected => (tr('Не подключено'), NX.text3),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: TextStyle(
                  color: state == ConnState.disconnected ? NX.text2 : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TimerLine extends StatefulWidget {
  const _TimerLine({required this.state, required this.since});
  final ConnState state;
  final DateTime? since;

  @override
  State<_TimerLine> createState() => _TimerLineState();
}

/// Один таймер на всё время подключения (не пересоздаётся при перерисовке).
class _TimerLineState extends State<_TimerLine> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TimerLine old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final on = widget.state == ConnState.connected && widget.since != null;
    if (on && _t == null) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on) {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state == ConnState.connected && widget.since != null) {
      final app = AppScope.of(context);
      final lat = app.liveLatency;
      return Column(
        children: [
          Text(
            fmtDuration(DateTime.now().difference(widget.since!)),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: app.measureLatency,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: lat == null
                  ? Text(tr('Проверяю задержку…'),
                      style: TextStyle(color: NX.text3, fontSize: 12.5))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PingBadge(ping: lat),
                        const SizedBox(width: 6),
                        const Icon(Icons.refresh_rounded,
                            size: 14, color: NX.text3),
                      ],
                    ),
            ),
          ),
        ],
      );
    }
    final last = AppScope.of(context).lastSession;
    final idle = widget.state == ConnState.disconnected;
    return SizedBox(
      height: idle && last != null ? 46 : 38,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            idle ? tr('Нажмите, чтобы подключиться') : '',
            style: const TextStyle(color: NX.text3, fontSize: 13.5),
          ),
          if (idle && last != null) ...[
            const SizedBox(height: 3),
            Text(tr('Прошлая сессия: {0}', [last]),
                style: const TextStyle(
                    color: NX.text3,
                    fontSize: 11.5,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final ConnStats stats;

  @override
  Widget build(BuildContext context) {
    Widget cell(IconData icon, String label, String value) => Expanded(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 14, color: NX.text3),
                  const SizedBox(width: 4),
                  Text(label,
                      style: const TextStyle(color: NX.text3, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        );
    Widget sep() => Container(width: 1, height: 30, color: NX.stroke);
    final app = AppScope.of(context);
    String mbps(double v) =>
        tr('{0} Мбит/с', [v >= 100 ? v.round() : v.toStringAsFixed(1)]);
    // Тест скорости: нажатие на ячейку запускает замер через текущий сервер.
    final speed = Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: app.speedTesting
            ? null
            : () async {
                final err = await app.runSpeedTest();
                if (err != null && context.mounted) {
                  toast(context, err, error: true);
                }
              },
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.speed_rounded,
                    size: 14,
                    color: app.speedTesting ? NX.mint : NX.text3),
                const SizedBox(width: 4),
                Text(tr('Скорость'),
                    style: TextStyle(
                        color: app.speedTesting ? NX.mint : NX.text3,
                        fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                app.speedTesting
                    ? mbps(app.speedLive ?? 0)
                    : app.speedMbps != null
                        ? mbps(app.speedMbps!)
                        : tr('Проверить'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: app.speedTesting
                        ? NX.mint
                        : app.speedMbps != null
                            ? NX.text
                            : NX.violet,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ],
        ),
      ),
    );
    return NeonCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          cell(Icons.south_rounded, tr('Загрузка'), fmtSpeed(stats.downloadSpeed)),
          sep(),
          cell(Icons.north_rounded, tr('Отдача'), fmtSpeed(stats.uploadSpeed)),
          sep(),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const TrafficScreen())),
              child: Row(children: [
                cell(Icons.swap_vert_rounded, tr('Всего'),
                    fmtBytes(stats.upload + stats.download)),
              ]),
            ),
          ),
          sep(),
          speed,
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.selected!;
    if (app.settings.autoMode) return _AutoRow(onTap: onTap);
    return NeonCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: [
          ServerAvatar(server: s),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(s.protocol,
                      style: const TextStyle(color: NX.text3, fontSize: 12.5)),
                  const SizedBox(width: 10),
                  PingBadge(
                      ping: app.state == ConnState.connected &&
                              app.liveLatency != null
                          ? app.liveLatency
                          : s.ping),
                ]),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Самый быстрый'),
            onPressed: app.pingingAll
                ? null
                : () async {
                    await app.selectFastest();
                    if (context.mounted) {
                      toast(context,
                          tr('Выбран: {0}', [app.selected?.cleanName ?? '—']));
                    }
                  },
            icon: app.pingingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bolt_rounded, color: NX.text2, size: 20),
          ),
          const Icon(Icons.chevron_right_rounded, color: NX.text3),
        ],
      ),
    );
  }
}

/// Режим «Авто»: вместо одного сервера — пул самых быстрых.
class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final n = app.autoPool().length;
    final sub = app.subscriptionOf(app.selected!);
    return NeonCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(colors: [
                NX.violet.withValues(alpha: 0.30),
                NX.mint.withValues(alpha: 0.18),
              ]),
            ),
            child: const Icon(Icons.bolt_rounded, color: NX.text, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Авто'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                // Статистика ядра (и с ней результаты проверки серверов)
                // обновляется отдельно от остального интерфейса.
                ValueListenableBuilder<ConnStats>(
                  valueListenable: app.statsNotifier,
                  builder: (_, __, ___) {
                    final cur = app.autoCurrent;
                    final live = app.state == ConnState.connected;
                    return Row(children: [
                      Flexible(
                        child: Text(
                          cur != null
                              ? tr('Сейчас: {0}', [cur.$1.cleanName])
                              : tr('Самый быстрый из {0}{1}', [
                                  live && app.activeAutoPool.isNotEmpty
                                      ? app.activeAutoPool.length
                                      : n,
                                  sub == null ? '' : ' · ${sub.title}'
                                ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NX.text3, fontSize: 12.5),
                        ),
                      ),
                      if (live && (cur != null || app.liveLatency != null)) ...[
                        const SizedBox(width: 10),
                        PingBadge(ping: cur?.$2 ?? app.liveLatency),
                      ],
                    ]);
                  },
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: NX.text3),
        ],
      ),
    );
  }
}

class _SubscriptionStrip extends StatelessWidget {
  const _SubscriptionStrip({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final unlimited = sub.total <= 0;
    final frac = unlimited ? null : (sub.used / sub.total).clamp(0.0, 1.0);
    final days = sub.expire?.difference(DateTime.now()).inDays;
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(sub.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
              if (days != null)
                Text(
                  days < 0
                      ? tr('Истекла')
                      : tr('ещё {0} {1}', [days, plural(days, tr('день'), tr('дня'), tr('дней'))]),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: days < 0
                        ? NX.red
                        : days <= 3
                            ? NX.amber
                            : NX.text2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TrafficBar(fraction: frac),
          const SizedBox(height: 8),
          Text(
            unlimited
                ? tr('{0} · без лимита', [fmtBytes(sub.used)])
                : tr('{0} из {1}', [fmtBytes(sub.used), fmtBytes(sub.total)]),
            style: const TextStyle(
                color: NX.text3,
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// Полоска трафика (null — без лимита).
class TrafficBar extends StatelessWidget {
  const TrafficBar({super.key, required this.fraction});
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final f = fraction;
    final color = f == null
        ? NX.text3.withValues(alpha: 0.4)
        : f > 0.9
            ? NX.red
            : f > 0.75
                ? NX.amber
                : NX.violet;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 5,
        child: Stack(
          children: [
            Container(color: NX.surface2),
            FractionallySizedBox(
              widthFactor: f ?? 1,
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        decoration: BoxDecoration(
          color: NX.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NX.red.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: NX.red, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: NX.text, fontSize: 13)),
            ),
            IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 18, color: NX.text2),
            ),
          ],
        ),
      );
}
