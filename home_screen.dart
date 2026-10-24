import 'package:flutter/material.dart';

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

    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConnectButton(
          state: app.state,
          size: wide ? 270 : 240,
          onTap: () {
            if (sel == null) {
              showAddSheet(context);
            } else {
              app.toggle();
            }
          },
        ),
        const SizedBox(height: 8),
        _StatusLabel(state: app.state, since: app.connectedAt),
      ],
    );

    final details = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (app.lastError != null) ...[
          _ErrorBanner(text: app.lastError!, onClose: app.clearError),
          const SizedBox(height: 12),
        ],
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: app.state == ConnState.connected
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _StatsRow(stats: app.stats),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (sel != null)
          _SelectedServerCard(onTap: onOpenServers)
        else
          NeonCard(
            onTap: () => showAddSheet(context),
            active: true,
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
        const SizedBox(height: 12),
        const _RoutingSwitch(),
        if (sel != null && app.subscriptionOf(sel) != null) ...[
          const SizedBox(height: 12),
          _SubscriptionMini(sub: app.subscriptionOf(sel)!),
        ],
      ],
    );

    if (wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 12, 32, 24),
        child: Row(
          children: [
            Expanded(flex: 5, child: Center(child: hero)),
            const SizedBox(width: 32),
            Expanded(
              flex: 4,
              child: Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: details,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 120),
        children: [
          Row(
            children: [
              const NexusLogo(size: 30),
              const Spacer(),
              NxIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Добавить',
                onPressed: () => showAddSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Center(child: hero),
          const SizedBox(height: 26),
          details,
        ],
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.state, required this.since});
  final ConnState state;
  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (state) {
      ConnState.connected => ('Защищено', NX.mint),
      ConnState.connecting => ('Подключение…', NX.cyan),
      ConnState.disconnecting => ('Отключение…', NX.text2),
      ConnState.disconnected => ('Не подключено', NX.text2),
    };
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: state == ConnState.connected
                    ? NX.glow(NX.mint, strength: 0.5)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Text(text,
                style: TextStyle(
                  fontFamily: NX.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  color: state == ConnState.connected ? NX.text : NX.text2,
                )),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 22,
          child: state == ConnState.connected && since != null
              ? StreamBuilder(
                  stream: Stream.periodic(const Duration(seconds: 1)),
                  builder: (_, __) => Text(
                    fmtDuration(DateTime.now().difference(since!)),
                    style: const TextStyle(
                      color: NX.text2,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                )
              : Text(
                  state == ConnState.disconnected
                      ? 'Нажмите, чтобы подключиться'
                      : '',
                  style: const TextStyle(color: NX.text3, fontSize: 13),
                ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final ConnStats stats;

  @override
  Widget build(BuildContext context) {
    Widget cell(IconData icon, Color c, String label, String value) =>
        Expanded(
          child: NeonCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: c, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: NX.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 2),
                      Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        cell(Icons.south_rounded, NX.cyan, 'ЗАГРУЗКА',
            fmtSpeed(stats.downloadSpeed)),
        const SizedBox(width: 10),
        cell(Icons.north_rounded, NX.violet, 'ОТДАЧА',
            fmtSpeed(stats.uploadSpeed)),
        const SizedBox(width: 10),
        cell(Icons.data_usage_rounded, NX.mint, 'ВСЕГО',
            fmtBytes(stats.upload + stats.download)),
      ],
    );
  }
}

class _SelectedServerCard extends StatelessWidget {
  const _SelectedServerCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.selected!;
    return NeonCard(
      onTap: onTap,
      child: Row(
        children: [
          ServerAvatar(server: s),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('СЕРВЕР',
                    style: TextStyle(
                        color: NX.text3,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const SizedBox(height: 3),
                Text(s.cleanName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15.5)),
                const SizedBox(height: 6),
                Row(children: [
                  Tag(s.protocol, color: NX.cyan),
                  const SizedBox(width: 8),
                  PingBadge(ping: s.ping),
                ]),
              ],
            ),
          ),
          NxIconButton(
            icon: Icons.bolt_rounded,
            tooltip: 'Самый быстрый',
            spinning: app.pingingAll,
            onPressed: () async {
              await app.selectFastest();
              if (context.mounted) {
                toast(context, 'Выбран: ${app.selected?.cleanName ?? '—'}');
              }
            },
          ),
          const SizedBox(width: 4),
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
    Widget seg(RoutingMode m, IconData icon, String title, String sub) {
      final on = app.settings.routing == m;
      return Expanded(
        child: GestureDetector(
          onTap: () async {
            if (on) return;
            app.updateSettings((s) => s.routing = m);
            await app.reconnectIfActive();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: on
                  ? LinearGradient(colors: [
                      NX.violet.withValues(alpha: 0.35),
                      NX.indigo.withValues(alpha: 0.25),
                    ])
                  : null,
              border: Border.all(
                  color: on
                      ? NX.violet.withValues(alpha: 0.8)
                      : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: on ? NX.text : NX.text3),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: on ? NX.text : NX.text2)),
                      Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: NX.text3, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return NeonCard(
      padding: const EdgeInsets.all(5),
      radius: 18,
      child: Row(
        children: [
          seg(RoutingMode.smart, Icons.alt_route_rounded, 'Умный',
              'РФ — напрямую'),
          const SizedBox(width: 4),
          seg(RoutingMode.global, Icons.public_rounded, 'Весь трафик',
              'Всё через Nexus'),
        ],
      ),
    );
  }
}

class _SubscriptionMini extends StatelessWidget {
  const _SubscriptionMini({required this.sub});
  final Subscription sub;

  @override
  Widget build(BuildContext context) {
    final unlimited = sub.total <= 0;
    final frac = unlimited ? 0.0 : (sub.used / sub.total).clamp(0.0, 1.0);
    final days = sub.expire?.difference(DateTime.now()).inDays;
    return NeonCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  size: 18, color: NX.violet),
              const SizedBox(width: 8),
              Expanded(
                child: Text(sub.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (days != null)
                Tag(
                  days < 0
                      ? 'истекла'
                      : '$days ${plural(days, 'день', 'дня', 'дней')}',
                  color: days < 0
                      ? NX.red
                      : days <= 3
                          ? NX.amber
                          : NX.mint,
                ),
            ],
          ),
          const SizedBox(height: 12),
          TrafficBar(fraction: unlimited ? null : frac),
          const SizedBox(height: 8),
          Text(
            unlimited
                ? 'Использовано ${fmtBytes(sub.used)} · безлимит'
                : 'Использовано ${fmtBytes(sub.used)} из ${fmtBytes(sub.total)}',
            style: const TextStyle(color: NX.text2, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Полоска трафика (null — безлимит, бегущий градиент).
class TrafficBar extends StatelessWidget {
  const TrafficBar({super.key, required this.fraction});
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final f = fraction;
    final danger = f != null && f > 0.9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 7,
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.06)),
            FractionallySizedBox(
              widthFactor: f ?? 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: danger
                      ? const LinearGradient(colors: [NX.amber, NX.red])
                      : f == null
                          ? LinearGradient(colors: [
                              NX.violet.withValues(alpha: 0.5),
                              NX.cyan.withValues(alpha: 0.5),
                            ])
                          : NX.neon,
                ),
              ),
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
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: NX.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NX.red.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: NX.red, size: 20),
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
