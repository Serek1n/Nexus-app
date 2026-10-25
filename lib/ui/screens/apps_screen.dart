import 'package:flutter/material.dart';

import '../../models.dart';
import '../../platform/android_system.dart';
import '../../services/ru_apps.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// Android: выбор приложений, которые работают мимо VPN.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<(String, String)>? _apps;
  String _q = '';
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    AndroidSystem.listApps().then((a) {
      if (mounted) setState(() => _apps = a);
    });
  }

  Future<bool> _leave() async {
    if (_changed) await AppScope.read(context).reconnectIfActive();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final st = app.settings;
    final ruAuto = st.routing == RoutingMode.smart && st.ruAppsDirect;
    final apps = (_apps ?? const <(String, String)>[])
        .where((a) =>
            _q.isEmpty ||
            a.$2.toLowerCase().contains(_q) ||
            a.$1.toLowerCase().contains(_q))
        .toList();
    // Сначала российские, потом выбранные, потом остальные.
    int rank((String, String) a) => ruBypassApps.containsKey(a.$1)
        ? 0
        : st.bypassApps.contains(a.$1)
            ? 1
            : 2;
    apps.sort((a, b) => rank(a).compareTo(rank(b)));

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: NX.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text('Приложения без VPN',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 20)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: NeonCard(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.flag_rounded, color: NX.violet, size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Российские приложения напрямую',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14)),
                            SizedBox(height: 2),
                            Text(
                                'Банки, Госуслуги, VK, Яндекс, маркетплейсы — '
                                'в умном режиме не видят VPN',
                                style:
                                    TextStyle(color: NX.text2, fontSize: 12)),
                          ],
                        ),
                      ),
                      Switch(
                        value: st.ruAppsDirect,
                        onChanged: (v) {
                          _changed = true;
                          app.updateSettings((s) => s.ruAppsDirect = v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (st.routing != RoutingMode.smart)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(
                    'Сейчас включён режим «Весь трафик»: российские приложения '
                    'идут через VPN. Отмеченные вручную — всегда напрямую.',
                    style: TextStyle(color: NX.amber, fontSize: 12.5),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Поиск приложения',
                    prefixIcon: Icon(Icons.search_rounded, color: NX.text3),
                  ),
                ),
              ),
              Expanded(
                child: _apps == null
                    ? const Center(child: CircularProgressIndicator())
                    : apps.isEmpty
                        ? const EmptyState(
                            icon: Icons.apps_rounded,
                            title: 'Ничего не найдено',
                            text: 'Измените запрос поиска')
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                            itemCount: apps.length,
                            itemBuilder: (_, i) {
                              final (pkg, label) = apps[i];
                              final isRu = ruBypassApps.containsKey(pkg);
                              final auto = isRu && ruAuto;
                              final on = auto || st.bypassApps.contains(pkg);
                              return ListTile(
                                dense: true,
                                title: Text(label,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14.5)),
                                subtitle: Text(
                                    auto ? 'Напрямую автоматически' : pkg,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: auto ? NX.mint : NX.text3,
                                        fontSize: 12)),
                                trailing: Checkbox(
                                  value: on,
                                  onChanged: auto
                                      ? null
                                      : (v) {
                                          _changed = true;
                                          app.updateSettings((s) {
                                            if (v == true) {
                                              s.bypassApps = [
                                                ...s.bypassApps,
                                                pkg
                                              ];
                                            } else {
                                              s.bypassApps = s.bypassApps
                                                  .where((p) => p != pkg)
                                                  .toList();
                                            }
                                          });
                                        },
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
