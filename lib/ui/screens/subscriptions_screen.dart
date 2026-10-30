import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models.dart';
import '../../platform/links.dart';
import '../add_sheet.dart';
import '../share_sheet.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';
import 'home_screen.dart' show TrafficBar;
import '../../l10n.dart';

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SafeArea(
      bottom: false,
      // Потянуть список вниз — обновить все подписки.
      child: RefreshIndicator(
        color: NX.violet,
        backgroundColor: NX.surface2,
        onRefresh: () => app.subscriptions.isEmpty
            ? Future<void>.value()
            : app.refreshAll(),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          PageHeader(
            title: tr('Подписки'),
            subtitle: app.subscriptions.isEmpty
                ? null
                : tr('Обновляются автоматически при запуске'),
            actions: [
              if (app.subscriptions.isNotEmpty) ...[
                NxIconButton(
                  icon: Icons.sync_rounded,
                  tooltip: tr('Обновить все'),
                  spinning: app.refreshing.isNotEmpty,
                  onPressed: () => app.refreshAll(),
                ),
                const SizedBox(width: 8),
              ],
              NxIconButton(
                icon: Icons.add_rounded,
                tooltip: tr('Добавить'),
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
                title: tr('Нет подписок'),
                text:
                    tr('Получите ссылку на подписку в Discord-боте NEXUS_VPN\nи вставьте её сюда'),
                action: NeonButton(
                  label: tr('Вставить ссылку'),
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
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  const _SubCard({required this.sub});
  final Subscription sub;

  String _ago(DateTime? t) {
    if (t == null) return tr('ещё не обновлялась');
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return tr('только что');
    if (d.inHours < 1) {
      return tr('{0} {1} назад', [d.inMinutes, plural(d.inMinutes, tr('минуту'), tr('минуты'), tr('минут'))]);
    }
    if (d.inDays < 1) {
      return tr('{0} {1} назад', [d.inHours, plural(d.inHours, tr('час'), tr('часа'), tr('часов'))]);
    }
    return tr('{0} {1} назад', [d.inDays, plural(d.inDays, tr('день'), tr('дня'), tr('дней'))]);
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
                        '${count} ${plural(count, tr('сервер'), tr('сервера'), tr('серверов'))} · ${_ago(sub.updatedAt)}',
                        style:
                            const TextStyle(color: NX.text2, fontSize: 12.5)),
                    if (sub.url.startsWith('http://')) ...[
                      const SizedBox(height: 6),
                      Tooltip(
                        message:
                            tr('Подписка загружается без шифрования: её могут подменить или подсмотреть ключи. Попросите https-ссылку.'),
                        child: Tag(tr('HTTP · без шифрования'), color: NX.amber),
                      ),
                    ],
                  ],
                ),
              ),
              NxIconButton(
                icon: Icons.sync_rounded,
                tooltip: tr('Обновить'),
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
                    case 'share':
                      await showShareSheet(
                        context,
                        title: tr('Подписка «{0}»', [sub.title]),
                        text: sub.url,
                        warning: tr('По этой ссылке получают все серверы подписки и тратят её трафик. Делитесь только с теми, кому доверяете, и если владелец подписки не против.'),
                      );
                    case 'copy':
                      await Clipboard.setData(ClipboardData(text: sub.url));
                      if (context.mounted) toast(context, tr('Ссылка скопирована'));
                    case 'rename':
                      await _rename(context);
                    case 'delete':
                      await _delete(context);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'share', child: Text(tr('Поделиться (QR)'))),
                  PopupMenuItem(value: 'copy', child: Text(tr('Скопировать ссылку'))),
                  PopupMenuItem(value: 'rename', child: Text(tr('Переименовать'))),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text(tr('Удалить'), style: TextStyle(color: NX.red))),
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
                        unlimited ? tr('  · безлимит') : tr('  из {0}', [fmtBytes(sub.total)]),
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
                          ? tr('Бессрочно')
                          : tr('До {0}', [_date(sub.expire!)]),
                      style: const TextStyle(color: NX.text2, fontSize: 12.5),
                    ),
                    const SizedBox(width: 8),
                    if (days != null)
                      Tag(
                        days < 0
                            ? tr('ИСТЕКЛА')
                            : tr('ОСТАЛОСЬ {0} {1}', [days, plural(days, tr('ДЕНЬ'), tr('ДНЯ'), tr('ДНЕЙ'))]),
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
                // Ссылки от панели: поддержка и личный кабинет.
                if ([sub.supportUrl, sub.webPageUrl]
                    .any((u) => u != null && isSafeWebLink(u))) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 4, children: [
                    for (final (url, icon, label) in [
                      (sub.supportUrl, Icons.support_agent_rounded, tr('Поддержка')),
                      (sub.webPageUrl, Icons.open_in_new_rounded, tr('Личный кабинет')),
                    ])
                      if (url != null && isSafeWebLink(url))
                        TextButton.icon(
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact),
                          onPressed: () => openWebLink(url),
                          icon: Icon(icon, size: 17, color: NX.violet),
                          label: Text(label,
                              style: const TextStyle(color: NX.text2, fontSize: 13)),
                        ),
                  ]),
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
        title: Text(tr('Название подписки')),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Сохранить'))),
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
        title: Text(tr('Удалить подписку?')),
        content: Text(tr('«{0}» и все её серверы будут удалены.', [sub.title]),
            style: const TextStyle(color: NX.text2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Отмена'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Удалить'), style: TextStyle(color: NX.red))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      AppScope.read(context).removeSubscription(sub);
    }
  }
}
