import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../add_sheet.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_screen.dart' show TrafficBar;

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          PageHeader(
            title: 'Подписки',
            subtitle: app.subscriptions.isEmpty
                ? null
                : 'Обновляются автоматически при запуске',
            actions: [
              if (app.subscriptions.isNotEmpty) ...[
                NxIconButton(
                  icon: Icons.sync_rounded,
                  tooltip: 'Обновить все',
                  spinning: app.refreshing.isNotEmpty,
                  onPressed: () => app.refreshAll(),
                ),
                const SizedBox(width: 8),
              ],
              NxIconButton(
                icon: Icons.add_rounded,
                tooltip: 'Добавить',
                onPressed: () => showAddSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (app.subscriptions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: EmptyState(
                icon: Icons.workspace_premium_rounded,
                title: 'Нет подписок',
                text:
                    'Получите ссылку на подписку в Discord-боте NEXUS_VPN\nи вставьте её сюда',
                action: NeonButton(
                  label: 'Вставить ссылку',
                  icon: Icons.content_paste_rounded,
                  onPressed: () => showAddSheet(context),
                ),
              ),
            )
          else
            for (final sub in app.subscriptions) ...[
              _SubCard(sub: sub),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  const _SubCard({required this.sub});
  final Subscription sub;

  String _ago(DateTime? t) {
    if (t == null) return 'ещё не обновлялась';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'только что';
    if (d.inHours < 1) {
      return '${d.inMinutes} ${plural(d.inMinutes, 'минуту', 'минуты', 'минут')} назад';
    }
    if (d.inDays < 1) {
      return '${d.inHours} ${plural(d.inHours, 'час', 'часа', 'часов')} назад';
    }
    return '${d.inDays} ${plural(d.inDays, 'день', 'дня', 'дней')} назад';
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final count = app.serversOf(sub.id).length;
    final unlimited = sub.total <= 0;
    final frac = unlimited ? null : (sub.used / sub.total).clamp(0.0, 1.0);
    final days = sub.expire?.difference(DateTime.now()).inDays;
    final busy = app.refreshing.contains(sub.id);

    return NeonCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: NX.violet.withValues(alpha: 0.14),
                ),
                child: const Icon(Icons.workspace_premium_rounded,
                    color: NX.violet, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                    const SizedBox(height: 2),
                    Text(
                        '$count ${plural(count, 'сервер', 'сервера', 'серверов')} · ${_ago(sub.updatedAt)}',
                        style:
                            const TextStyle(color: NX.text2, fontSize: 12.5)),
                  ],
                ),
              ),
              NxIconButton(
                icon: Icons.sync_rounded,
                tooltip: 'Обновить',
                spinning: busy,
                onPressed: () => app.refresh(sub),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: NX.text3),
                color: NX.surface2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: NX.stroke),
                ),
                onSelected: (v) async {
                  switch (v) {
                    case 'copy':
                      await Clipboard.setData(ClipboardData(text: sub.url));
                      if (context.mounted) toast(context, 'Ссылка скопирована');
                    case 'rename':
                      await _rename(context);
                    case 'delete':
                      await _delete(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('Скопировать ссылку')),
                  PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('Удалить', style: TextStyle(color: NX.red))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(fmtBytes(sub.used),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                        unlimited ? '  · безлимит' : '  из ${fmtBytes(sub.total)}',
                        style:
                            const TextStyle(color: NX.text2, fontSize: 13)),
                    const Spacer(),
                    if (frac != null)
                      Text('${(frac * 100).round()}%',
                          style: const TextStyle(
                              color: NX.text2,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 8),
                TrafficBar(fraction: frac),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.event_rounded, size: 15, color: NX.text3),
                    const SizedBox(width: 6),
                    Text(
                      sub.expire == null
                          ? 'Бессрочно'
                          : 'До ${_date(sub.expire!)}',
                      style: const TextStyle(color: NX.text2, fontSize: 12.5),
                    ),
                    const SizedBox(width: 8),
                    if (days != null)
                      Tag(
                        days < 0
                            ? 'ИСТЕКЛА'
                            : 'ОСТАЛОСЬ $days ${plural(days, 'ДЕНЬ', 'ДНЯ', 'ДНЕЙ')}',
                        color: days < 0
                            ? NX.red
                            : days <= 3
                                ? NX.amber
                                : NX.mint,
                      ),
                  ],
                ),
                if (sub.announce != null && sub.announce!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: NX.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: NX.cyan.withValues(alpha: 0.3)),
                    ),
                    child: Text(sub.announce!,
                        style:
                            const TextStyle(fontSize: 12.5, color: NX.text)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final ctrl = TextEditingController(text: sub.title);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Название подписки'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (res != null && context.mounted) {
      AppScope.read(context).renameSubscription(sub, res);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить подписку?'),
        content: Text('«${sub.title}» и все её серверы будут удалены.',
            style: const TextStyle(color: NX.text2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить', style: TextStyle(color: NX.red))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      AppScope.read(context).removeSubscription(sub);
    }
  }
}
