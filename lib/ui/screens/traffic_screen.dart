import 'package:flutter/material.dart';

import '../../services/traffic_log.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../l10n.dart';

List<String> get _months => [
  tr('январь'), tr('февраль'), tr('март'), tr('апрель'), tr('май'), tr('июнь'), tr('июль'), tr('август'),
  tr('сентябрь'), tr('октябрь'), tr('ноябрь'), tr('декабрь'),
];

/// Трафик через VPN по дням и месяцам.
class TrafficScreen extends StatefulWidget {
  const TrafficScreen({super.key});

  @override
  State<TrafficScreen> createState() => _TrafficScreenState();
}

class _TrafficScreenState extends State<TrafficScreen> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final log = app.traffic;
    final now = DateTime.now();
    String month(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}';
    final prev = DateTime(now.year, now.month - 1);
    final days = log.lastDays(14);
    final maxDay = days.fold<int>(1, (m, e) => e.$2 + e.$3 > m ? e.$2 + e.$3 : m);
    final pick = _picked ?? days.length - 1;
    final (pd, pu, pdn) = days[pick];

    Widget stat(String label, int bytes) => Expanded(
          child: NeonCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(color: NX.text3, fontSize: 12.5)),
                const SizedBox(height: 4),
                Text(fmtBytes(bytes),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 17)),
              ],
            ),
          ),
        );

    return Scaffold(
      backgroundColor: NX.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 32),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(tr('Статистика трафика'),
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  Row(children: [
                    stat(tr('Сегодня'), log.total(TrafficLog.dayKey(now))),
                    const SizedBox(width: 10),
                    stat(_months[now.month - 1], log.total(month(now))),
                    const SizedBox(width: 10),
                    stat(_months[prev.month - 1], log.total(month(prev))),
                  ]),
                  SectionTitle(tr('Последние 14 дней')),
                  NeonCard(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 150,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var i = 0; i < days.length; i++)
                                Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => setState(() => _picked = i),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 3),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          _Bar(
                                            down: days[i].$3 / maxDay,
                                            up: days[i].$2 / maxDay,
                                            active: i == pick,
                                          ),
                                          const SizedBox(height: 6),
                                          Text('${days[i].$1.day}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: i == pick
                                                      ? NX.text
                                                      : NX.text3,
                                                  fontWeight: i == pick
                                                      ? FontWeight.w800
                                                      : FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(children: [
                          Text(
                              '${pd.day} ${_months[pd.month - 1].substring(0, 3)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          const Spacer(),
                          const _Dot(NX.violet),
                          Text(' ↓ ${fmtBytes(pdn)}',
                              style: const TextStyle(
                                  color: NX.text2, fontSize: 13)),
                          const SizedBox(width: 12),
                          const _Dot(NX.mint),
                          Text(' ↑ ${fmtBytes(pu)}',
                              style: const TextStyle(
                                  color: NX.text2, fontSize: 13)),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tr('Считается только трафик через VPN, данные хранятся на этом устройстве. Оператор и провайдер могут считать иначе.'),
                    style: TextStyle(color: NX.text3, fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: log.days.isEmpty
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(tr('Сбросить статистику?')),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(tr('Отмена'))),
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(tr('Сбросить'),
                                            style: TextStyle(color: NX.red))),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                log.clear();
                                setState(() => _picked = null);
                              }
                            },
                      icon: const Icon(Icons.delete_outline_rounded,
                          color: NX.text3),
                      label: Text(tr('Сбросить статистику'),
                          style: TextStyle(color: NX.text2)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.down, required this.up, required this.active});
  final double down, up;
  final bool active;

  @override
  Widget build(BuildContext context) {
    const h = 118.0;
    final d = (down * h).clamp(0.0, h), u = (up * h).clamp(0.0, h);
    final empty = d + u < 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              height: u,
              color: NX.mint.withValues(alpha: active ? 1 : 0.55)),
          Container(
              height: empty ? 2 : d,
              color: empty
                  ? NX.stroke
                  : NX.violet.withValues(alpha: active ? 1 : 0.55)),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
