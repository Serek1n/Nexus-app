import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../add_sheet.dart';
import '../app_scope.dart';
import '../connect_button.dart';
import '../theme.dart';
import '../widgets.dart';

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
        _StatusPill(state: app.state),
        const SizedBox(height: 28),
        ConnectButton(
          state: app.state,
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
        if (app.androidUpdate != null) ...[
          NeonCard(
            onTap: app.updateProgress == null ? app.installAndroidUpdate : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.system_update_rounded,
                    color: NX.violet, size: 19),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    app.updateProgress != null
                        ? 'Загрузка ${(app.updateProgress! * 100).round()}%'
                        : 'Доступно обновление'
                            '${app.androidUpdate!.xray.isEmpty ? '' : ' · Xray ${app.androidUpdate!.xray.replaceFirst('v', '')}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                if (app.updateProgress == null)
                  const Text('Обновить',
                      style: TextStyle(
                          color: NX.violet,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
              ],
            ),
          ),
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
            child: const Row(
              children: [
                Icon(Icons.add_link_rounded, color: NX.violet),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Добавьте подписку',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      SizedBox(height: 2),
                      Text('Вставьте ссылку из бота NEXUS',
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
          child: app.state == ConnState.connected
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ValueListenableBuilder<ConnStats>(
                    valueListenable: app.statsNotifier,
                    builder: (_, st, __) => _StatsRow(stats: st),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 10),
        const _RoutingSwitch(),
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
                tooltip: 'Добавить',
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
  if (days != null && days < 0) return 'Подписка «${sub.title}» закончилась — продлите её в боте';
  if (days != null && days <= 3) {
    return 'Подписка заканчивается через $days ${plural(days, 'день', 'дня', 'дней')} — продлите её в боте';
  }
  if (sub.total > 0 && sub.used / sub.total >= 0.9) {
    return 'Использовано ${(sub.used / sub.total * 100).round()}% трафика подписки';
  }
  return null;
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: NX.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NX.amber.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, color: NX.amber, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(color: NX.text, fontSize: 13)),
            ),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.state});
  final ConnState state;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (state) {
      ConnState.connected => ('Подключено', NX.mint),
      ConnState.connecting => ('Подключение…', NX.violet),
      ConnState.disconnecting => ('Отключение…', NX.text2),
      ConnState.disconnected => ('Не подключено', NX.text3),
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

class _TimerLine extends StatelessWidget {
  const _TimerLine({required this.state, required this.since});
  final ConnState state;
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    if (state == ConnState.connected && since != null) {
      return StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (_, __) => Text(
          fmtDuration(DateTime.now().difference(since!)),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
    }
    return SizedBox(
      height: 38,
      child: Center(
        child: Text(
          state == ConnState.disconnected ? 'Нажмите, чтобы подключиться' : '',
          style: const TextStyle(color: NX.text3, fontSize: 13.5),
        ),
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
    return NeonCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          cell(Icons.south_rounded, 'Загрузка', fmtSpeed(stats.downloadSpeed)),
          sep(),
          cell(Icons.north_rounded, 'Отдача', fmtSpeed(stats.uploadSpeed)),
          sep(),
          cell(Icons.swap_vert_rounded, 'Всего',
              fmtBytes(stats.upload + stats.download)),
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
                  PingBadge(ping: s.ping),
                ]),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Самый быстрый',
            onPressed: app.pingingAll
                ? null
                : () async {
                    await app.selectFastest();
                    if (context.mounted) {
                      toast(context,
                          'Выбран: ${app.selected?.cleanName ?? '—'}');
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

class _RoutingSwitch extends StatelessWidget {
  const _RoutingSwitch();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Widget seg(RoutingMode m, String title) {
      final on = app.settings.routing == m;
      return Expanded(
        child: GestureDetector(
          onTap: () async {
            if (on) return;
            app.updateSettings((s) => s.routing = m);
            await app.reconnectIfActive();
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: on ? NX.surface2 : Colors.transparent,
                border: Border.all(
                    color: on ? NX.strokeStrong : Colors.transparent),
              ),
              child: Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: on ? NX.text : NX.text3)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: NX.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: NX.stroke),
      ),
      child: Row(
        children: [
          seg(RoutingMode.smart, 'Умный режим'),
          const SizedBox(width: 4),
          seg(RoutingMode.global, 'Весь трафик'),
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
                      ? 'Истекла'
                      : 'ещё $days ${plural(days, 'день', 'дня', 'дней')}',
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
                ? '${fmtBytes(sub.used)} · без лимита'
                : '${fmtBytes(sub.used)} из ${fmtBytes(sub.total)}',
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
