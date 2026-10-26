import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../changelog.dart';
import '../platform/android_system.dart';
import '../services/app_updater.dart';
import 'app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

/// Окно «Откатить версию»: список прошлых релизов.
Future<void> showRollbackSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: Container(
          decoration: const BoxDecoration(
            color: NX.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: NX.strokeStrong)),
          ),
          child: const SafeArea(top: false, child: _RollbackBody()),
        ),
      ),
    );

class _RollbackBody extends StatefulWidget {
  const _RollbackBody();

  @override
  State<_RollbackBody> createState() => _RollbackBodyState();
}

class _RollbackBodyState extends State<_RollbackBody> {
  late final Future<(int, List<AppRelease>)> _data = _load();
  int? _busy;
  String? _error;

  Future<(int, List<AppRelease>)> _load() async {
    final current = await AppUpdater.currentBuild();
    final all = await AppUpdater.history();
    return (current, all.where((r) => r.build < current).toList());
  }

  Future<void> _install(AppRelease r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Откатить на ${r.version}?'),
        content: const Text(
            'Nexus установит выбранную версию и перезапустится. Подписки и '
            'настройки сохранятся. Текущую версию автоматически предлагать '
            'не будем — только более новые.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Откатить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = r.build;
      _error = null;
    });
    try {
      await AppScope.read(context).rollbackTo(r);
    } catch (e) {
      final s = e.toString();
      if (mounted) {
        setState(() =>
            _error = s.startsWith('Exception: ') ? s.substring(11) : s);
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final android = Platform.isAndroid;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
          child: Row(children: [
            const Expanded(
              child: Text('Откатить версию',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: NX.text2),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            android
                ? 'Android не даёт поставить старую версию поверх новой. '
                    'Скопируйте подписки, удалите Nexus, скачайте нужную '
                    'версию со страницы релиза и вставьте подписки обратно.'
                : 'Сейчас установлена $appVersion. Выберите версию, '
                    'которая работала хорошо.',
            style: const TextStyle(color: NX.text2, fontSize: 13, height: 1.4),
          ),
        ),
        if (android)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: NeonButton(
              label: 'Скопировать подписки',
              icon: Icons.copy_rounded,
              secondary: true,
              onPressed: () async {
                final app = AppScope.read(context);
                await Clipboard.setData(
                    ClipboardData(text: app.exportSubscriptions()));
                if (context.mounted) {
                  toast(context,
                      'Скопировано подписок: ${app.subscriptions.length}');
                }
              },
            ),
          ),
        if (_error != null)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: NX.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NX.red.withValues(alpha: 0.4)),
            ),
            child: Text(_error!,
                style: const TextStyle(color: NX.red, fontSize: 13)),
          ),
        Flexible(
          child: FutureBuilder<(int, List<AppRelease>)>(
            future: _data,
            builder: (context, snap) {
              if (snap.hasError) {
                final s = snap.error.toString();
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                      s.startsWith('Exception: ') ? s.substring(11) : s,
                      style: const TextStyle(color: NX.red, fontSize: 13)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final list = snap.data!.$2;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Более ранних версий пока нет',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: NX.text3)),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = list[i];
                  return NeonCard(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.version,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              if (r.date != null)
                                Text(_date(r.date),
                                    style: const TextStyle(
                                        color: NX.text3, fontSize: 12)),
                              if (r.notes.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ChangeList(r.notes.take(3).toList()),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (android)
                          NeonButton(
                            label: 'Открыть',
                            secondary: true,
                            onPressed: r.pageUrl.isEmpty
                                ? null
                                : () => AndroidSystem.openUrl(r.pageUrl),
                          )
                        else
                          NeonButton(
                            label: 'Откатить',
                            secondary: true,
                            loading: _busy == r.build,
                            onPressed: _busy != null ? null : () => _install(r),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
